# API reference (v1)

Base URL: `http://localhost:8080` in development. A server published with `scripts/serve-public.ps1` has a changing `https://…trycloudflare.com` address; apps read the current one from the discovery file (`{ "apiBaseUrl" }`), see [architecture.md](architecture.md#reaching-the-server-from-any-network). JSON in and out. Authenticated routes need `Authorization: Bearer <accessToken>`.
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

A server without an SMS provider (`SMS_PROVIDER=none`) refuses SMS codes with `400 OTP_CHANNEL_OFF` before changing anything (signup, resend, or a reset typed as a phone number); `/v1/config` lists the channels it can use in `otpChannels`.

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
- `otpChannels`: how sign-up codes can be sent (`["EMAIL"]` or `["EMAIL", "SMS"]`); the app offers only these

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

## Calendar: `/v1/calendar` (any signed-in account)
| Method | Path | Body | Success |
| --- | --- | --- | --- |
| GET | `/v1/calendar` | | `{ events }` |
| POST | `/v1/calendar` | `event` | `201 event` |
| PUT | `/v1/calendar/:id` | `event` | `event` |
| DELETE | `/v1/calendar/:id` | | `204` |
| POST | `/v1/calendar/bulk` | `{ events[] }` (up to 300) | `201 { events }` |
| POST | `/v1/calendar/import` | `text?`, `file?: { mime, data (base64) }`, `utcOffsetMinutes` | `{ events }` (drafts, not saved) |

`event` = `{ kind: EXAM | CLASS | ASSIGNMENT | HOLIDAY | EVENT, title, subject?, location?, notes?, startsAt, endsAt?, allDay?, weekly?, repeatUntil?, reminders?: minutes[] }` (times are ISO 8601 with an offset).

- **Reminders** default to 1 day + 1 hour before exams, 15 minutes before classes, 1 day before assignments, none for holidays. The phone schedules them as notifications for the next 30 days, so they work offline.
- **Weekly** items (classes) repeat on the start's weekday until `repeatUntil`; the phone expands them.
- **Import** reads an academic calendar, exam routine or timetable (PDF or JPEG/PNG/WebP up to 8 MB, or text up to 20,000 characters) with the AI. Dates and times are read as the phone's local time (`utcOffsetMinutes`). The student reviews the drafts, then saves them with `/bulk`. Errors: `AI_OFF`, `AI_UNAVAILABLE`, `BAD_FILE`, `NOTHING_FOUND`. A calendar holds up to 2000 items (`CALENDAR_FULL`).

## Admin: `/v1/admin` (ADMIN accounts only)
The Control Room (`/admin/`, and inside the app for admin accounts) uses these. Admin accounts are made on the server (`npm run admin -- create <email> "<name>"`), never through the API.

| Method | Path | Body / query | Success |
| --- | --- | --- | --- |
| GET | `/stats` | | totals for `users` (incl. `online`, `signedIn`), `sessions` (incl. `minutesToday`), `exams` (`passRate`), `devices`, `ai`, and `activity` (14 days: `signups`, `sessions`, `studyMinutes`, `exams`, `passed`) |
| GET | `/users` | `q?` (name, email or phone), `role?`, `status?` (`active`\|`disabled`\|`unverified`), `presence?` (`online`\|`signedIn`\|`signedOut`), `page`, `pageSize` (≤ 100) | `{ total, page, pageSize, users }`, each with `presence`, `lastActiveAt`, `signedInDevices`, `studyMinutes` |
| GET | `/users/:id` | | the account: `presence`, `signedInDevices[]`, `study` (`todayMinutes`, `weekMinutes`, `totalMinutes`, `bySubject[]`), `lock` (running session and parent locks), `sessions` (with `studiedMinutes`), `exams`, `parents`/`children`, `devices`, `activity` (last 60 events) |
| PATCH | `/users/:id` | `{ disabled }` | the account |
| POST | `/users/:id/sign-out` | | the account (every session ended) |
| POST | `/users/:id/reset-password` | | `{ password }` (new random password, shown once; every session ended) |
| POST | `/users/:id/unlock` | `{ reason? }` | `{ endedSessions, endedParentLocks, user }` |
| GET | `/study` | `days` (0 = all time; default 7) | `{ totalMinutes, students[] (minutes, sessions, subjects[], lastStudiedAt), subjects[] }` |
| GET | `/activity` | `userId?`, `kind?`, `page`, `pageSize` (≤ 200) | `{ total, events[] }` (`kind`, `user`, `actor`, `ip`, `userAgent`, `detail`, `createdAt`) |
| GET | `/settings` | | every setting (the `/v1/config` ones plus `tutorDailyLimit`) |
| PATCH | `/settings` | any subset of the settings | all settings |
| POST | `/panel-session` | | `{ tokens }`: a separate session for the panel opened inside the app |

- **Presence:** `online` = an authenticated request in the last 5 minutes and a live session; `signedIn` = at least one live (unrevoked, unexpired) session; otherwise `signedOut`. `lastActiveAt` is written at most every 2 minutes.
- **Activity kinds:** `SIGNUP`, `LOGIN`, `LOGOUT`, `PASSWORD_RESET`, `ADMIN_DISABLED`, `ADMIN_ENABLED`, `ADMIN_SIGNED_OUT`, `ADMIN_PASSWORD_RESET`, `ADMIN_UNLOCKED`, `ADMIN_SETTINGS`.
- **Unlock (owner's override):** ends the student's running study session (status `CANCELLED` with `adminUnlockedAt`; the minutes already studied still count), any active parent locks, and any running exam, without an exam. The phone follows on its next sync (about a minute). The student and linked parents get an `ADMIN_UNLOCK` notification. Only for students (`NOT_A_STUDENT`).
- **Disabling** revokes every refresh token and refuses the account's requests (`401`); running app locks stay on. Admins cannot act on themselves (`CANNOT_DISABLE_SELF`) or on another admin (`CANNOT_MANAGE_ADMIN`).
- **Settings** keep their bounds: the pass mark never goes under 50%, minimum study time never exceeds the maximum, and unknown keys are refused. Only the settings sent are changed.
