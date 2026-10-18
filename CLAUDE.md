# Study Assistant: guide for Claude and contributors

A study app for students: pick what you will study, lock distracting apps, and unlock them by passing an AI-generated exam. Parents can link with a QR code. An admin panel controls everything.

> **Scope:** this repository only. It sits inside a folder belonging to another project (Joruri BD); never read, change or borrow from anything outside `study-assistant/`.

## Layout
```
backend/   Node 24 + TypeScript, Fastify 5, Prisma 6 (SQLite in dev, Postgres in prod), zod, vitest
  src/modules/<feature>/   *.schemas.ts → *.service.ts → *.routes.ts
  src/lib/                 crypto, errors, validation, phone, age, clock
  test/                    API tests through app.inject (FakeNotifier captures OTPs)
app/       Flutter 3.47 (Android first), Riverpod 3, go_router 18, dio
  lib/core/                config, network (ApiClient + token refresh), theme, widgets (3D design system)
  lib/features/<feature>/  data / domain / application / presentation
  lib/app/                 providers, routes + guard, router
  tool/icon/               renders launcher icons from LogoPainter
admin/     (coming) web admin panel
docs/      architecture notes and assets
.claude/agents/            junior-coder, senior-coder, code-reviewer, qa-tester
```

## Commands
```bash
# Backend
cd backend && npm ci && cp .env.example .env    # first time; set JWT_SECRET and OTP_SECRET
npm run db:push        # create/update the dev SQLite database
npm run dev            # API on :8080; OTPs are printed in the log in development
npm run lint && npm run typecheck && npm test && npm run build

# App
cd app && flutter pub get
adb reverse tcp:8080 tcp:8080          # phone or emulator reaches the local API
flutter run                             # --release to judge speed
dart format . && flutter analyze && flutter test test
flutter test tool/icon/render_icon_test.dart && dart run flutter_launcher_icons   # after logo changes
```

## Product rules (never break these)
- A study session locks the apps the student chose. **Unlocking requires passing an exam** on what they said they would study. A failed exam keeps the apps locked. There is no bypass.
- The student sets the exam pattern, total marks and pass mark. **The pass mark is at least 50%**, and the student may choose higher.
- **Students under 15 must have a parent linked** before using study features. The server reports `parentalControl.required`, and the app gate is `guardRoute()`. A student aged 15 or over may link a parent if they choose.
- Parent accounts are 18+. A parent links by scanning the student's QR (single-use code, 10-minute expiry). Parents can block apps, see screen time and set questions.
- Signup verifies by email or SMS OTP (6 digits, 10-minute expiry, 5 atomic attempts, a 60 s cooldown and 5 per hour **per destination**). Only verified contacts can sign in or reset a password.

## Conventions
- **Errors:** the API always returns `{ error: { code, message, details? } }`. `message` is safe to show users; clients branch on `code`. Field errors go in `details.fields`.
- **Security:** passwords use scrypt. OTPs and pairing codes are stored only as HMACs. Refresh tokens are opaque, stored hashed, and rotate on use; reuse revokes the session family. Every authenticated route uses `requireAuth(prisma, roles)`.
- **Time:** inject `Clock` for anything that expires. The server stores UTC.
- **UI:** use the design system in `app/lib/core/widgets` (`Button3D`, `ClayCard`, `PageShell`, `MessageBanner`, `Pencil3D`) and colours from `AppColors`. Copy is short, warm and encouraging. Every screen handles loading, error, small screens and large text.
- **Formatting:** Dart uses a 120-column page width (set in `analysis_options.yaml`). TypeScript is checked by ESLint with typed rules.

## Git and pull requests
- Never commit to `main`. Use one branch per part of the work (`feat/…`, `fix/…`, `chore/…`, `docs/…`) and conventional commits (`feat(app): …`, `fix(api): …`).
- Commits are authored by the configured git user (the repo owner). **Never add `Co-Authored-By` trailers or any AI attribution** to commits or PR descriptions.
- Every change goes through the pipeline before its PR: **junior-coder → senior-coder → code-reviewer → qa-tester** (or run `/ship <task>`). The PR description uses `.github/pull_request_template.md` and includes the review verdict and QA evidence.
- Keep `README.md` and `.gitignore` up to date in the same PR as the change that affects them.
