# API reference (v1)

Base URL: `http://localhost:8080` in development. JSON in and out. Authenticated routes need `Authorization: Bearer <accessToken>`.
Errors always look like `{ "error": { "code", "message", "details?" } }`; the codes are listed in [architecture.md](architecture.md#error-contract).

## Auth: `/v1/auth`
| Method | Path | Body | Success |
| --- | --- | --- | --- |
| POST | `/register` | `role` (`STUDENT`\|`PARENT`), `name`, `email?`, `phone?`, `password`, `dateOfBirth` (`YYYY-MM-DD`), `otpChannel` (`EMAIL`\|`SMS`) | `201 { userId, verification }` |
| POST | `/verify` | `userId`, `code` | `{ user, tokens }` |
| POST | `/verify/resend` | `userId`, `channel?` | `verification` |
| POST | `/login` | `identifier` (email or phone), `password` | `{ user, tokens }`, or `403 ACCOUNT_NOT_VERIFIED` |
| POST | `/password/forgot` | `identifier` | `{ sent: true }` (always) |
| POST | `/password/reset` | `identifier`, `code`, `newPassword` | `{ user, tokens }` |
| POST | `/refresh` | `refreshToken` | `{ user, tokens }` (the token rotates) |
| POST | `/logout` | `refreshToken` | `204` |

`verification` = `{ channel, destination (masked), expiresAt, resendAvailableAt }`
`tokens` = `{ accessToken, refreshToken, expiresIn }`

Rate limits: 10 requests per minute per IP on the endpoints that send codes or check secrets, and 300 per minute overall. Codes are also limited **per destination** (one per 60 s, five per hour per email or phone), whichever account asks.

Only a **verified** contact (one that has received a code) can be used to sign in or reset a password. An unverified contact does not block someone else from signing up with it.

## Profile: `/v1/me`
| Method | Path | Body | Success |
| --- | --- | --- | --- |
| GET | `/` | | `user` |
| PATCH | `/` | `name` | `user` |

`user` = `{ id, role, name, email, phone, dateOfBirth, age, verified, emailVerified, phoneVerified, parentalControl: { required, linkedParents } | null, linkedChildren | null }`

## Family: `/v1/family`
| Method | Path | Who | Body | Success |
| --- | --- | --- | --- | --- |
| POST | `/pairing-code` | student | | `{ code: "ABCD-EFGH", qrPayload, expiresAt }` |
| POST | `/links` | parent | `code` (QR payload or typed code) | `201 link` |
| GET | `/links` | student, parent | | `{ links: [link] }` |
| DELETE | `/links/:id` | either side | | `204` (a student under 15 cannot remove their last parent) |

`link` = `{ id, linkedAt, person: { id, name, role, age } }`

## Config: `/v1/config`
Public. These are the admin-tunable settings the app needs:
- `subjects`
- `minPassPercent` (never below 50)
- `minStudyMinutes`, `maxStudyMinutes`
- `earlyFinishPercent`
- `maxQuestions`
- `examRetryCooldownSeconds`
- `aiEnabled`
- `announcement`

## Study sessions: `/v1/sessions` (students)
| Method | Path | Body / query | Success |
| --- | --- | --- | --- |
| POST | `/` | `subject`, `topics`, `plannedMinutes`, `lockedApps[]`, `strict`, `exam: { questionCount, totalMarks, passMarks, questionTypes[], difficulty }` | `201 session` |
| GET | `/active` | | `{ session }` (or `null`) |
| POST | `/:id/finish` | | `session`, or `409 TOO_EARLY` before the early-finish point |
| GET | `/` | `?limit=` | `{ sessions }` |
| GET | `/stats` | `?utcOffsetMinutes=` | `{ todayMinutes, streakDays, week[7], totalMinutes, sessionsCompleted }` (`totalMinutes` covers the last 60 days) |

Rules:
- Students under 15 get `403 PARENT_REQUIRED` until a parent links.
- Only one session can run at a time (`409 SESSION_ACTIVE`).
- The pass mark must be at least the configured percent, and never below 50%.
- A session moves from `STUDYING` to `EXAM_PENDING` when the timer ends. Students cannot cancel it.

Every response carries `X-Server-Time`, so clients can run countdowns on server time.

## Devices: `/v1/devices` (students) and `/v1/device` (phone, `X-Device-Token`)
| Method | Path | Body | Success |
| --- | --- | --- | --- |
| POST | `/v1/devices` | `name`, `platform` (`android`), `appVersion?` | `201 { deviceId, deviceToken }` |
| GET | `/v1/devices` | | `{ devices }` |
| DELETE | `/v1/devices/:id` | | `204`, or `409 LOCK_ACTIVE` while a lock is running |
| GET | `/v1/device/state` | | `lockState` |
| POST | `/v1/device/heartbeat` | `protectionOn`, `usageAccess`, `shortcutOn?`, `appVersion?`, `installedApps?[{ package, label }]` | `lockState` |

`lockState` = `{ locked, wholePhone, packages[], strict, reasons[{ kind: SESSION | PARENT, id, title, status }] }`

## Exams and the study helper: `/v1` (students)
| Method | Path | Body | Success |
| --- | --- | --- | --- |
| POST | `/v1/sessions/:id/exam` | | `exam`: a new exam, or the one already running |
| POST | `/v1/exams/:id/submit` | `answers: { [questionId]: string }` | `exam` with `result` |
| GET | `/v1/exams/:id` | | `exam` |
| GET | `/v1/exams?limit=` | | `{ exams }` |
| POST | `/v1/tutor` | `messages[{ role: user \| assistant, content }]` (latest 20, first from the student) | `{ reply, remainingToday }` |

- **Answers:** multiple choice sends the option index (`"2"`), true/false sends `"true"`/`"false"`, short answers send text. Questions never include the answers until the exam is graded.
- **Time limit:** `expiresAt` is max(5 min, 90 s per question); a hand-in is accepted up to 60 s late.
- **Passing** (`score ≥ passMarks`) finishes the session and unlocks its apps. A fail keeps them locked; a new exam can start after `examRetryCooldownSeconds`, with fresh questions.
- **Source:** `AI` when `ANTHROPIC_API_KEY` is set, otherwise `PRACTICE` (a built-in, checked question bank plus arithmetic). If the AI fails mid-request, the exam falls back to practice questions instead of erroring.
- **Errors:** `EXAM_NOT_READY` (still studying), `EXAM_COOLDOWN` (`details.retryAt`), `EXAM_EXPIRED`, `ALREADY_PASSED`, `AI_OFF` (helper not set up, or switched off by the admin), `EXAM_IN_PROGRESS` (the helper pauses during an exam), `TUTOR_LIMIT` (`tutorDailyLimit` questions per rolling 24 h).
