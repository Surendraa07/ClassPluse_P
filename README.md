# ClassPluse

Live classroom feedback: lecturers run poll/quiz slides, students join from their phones with a
6-digit code or QR scan (no account), answer, and send an anonymous "I'm following" / "I'm lost"
pulse. The lecturer sees class totals update live.

```
apps/server/         Node.js + Express + TypeScript + Prisma + Socket.io
apps/mobile/         Flutter app (Android + iOS): lecturer and student in one app
docker-compose.yml   PostgreSQL for local dev
PROGRESS.md          build log and decisions
```

## Prerequisites
- Node.js 20+ (tested on 24)
- PostgreSQL 17, either via Docker **or** a native install
- Flutter stable (tested on 3.47) with an Android emulator / device, or Xcode for iOS

## 1. Database

**Option A: Docker**
```bash
docker compose up -d
```
Creates user `classpluse` / password `classpluse`, databases `classpluse` and `classpluse_test`.

**Option B: native PostgreSQL**
Create a dev user that can create databases (Prisma creates both databases for you):
```sql
CREATE ROLE classpluse LOGIN PASSWORD 'classpluse' CREATEDB;
```

## 2. Server
```bash
cd apps/server
cp .env.example .env        # then set JWT_SECRET
npm install                 # also generates the Prisma client
npm run db:migrate          # apply migrations to DATABASE_URL
npm run db:seed             # demo data
npm run dev                 # http://localhost:4000 (listens on all interfaces)
```
Check: `curl http://localhost:4000/health` → `{"status":"ok","db":"up",...}`

Seeded login: **`demo@classpluse.app` / `Password123!`** with the presentation
"POP Lecture 4: Loops" (a poll and a quiz).

### Environment variables (`apps/server/.env`)
| Variable | Purpose |
|---|---|
| `PORT` | HTTP + Socket.io port (default 4000) |
| `DATABASE_URL` | Postgres connection for the app |
| `TEST_DATABASE_URL` | Separate DB used by `npm test` (wiped by tests) |
| `JWT_SECRET` | ≥ 32 chars, signs lecturer tokens |
| `JWT_EXPIRES_IN` | Access token lifetime, e.g. `7d` |
| `BCRYPT_ROUNDS` | Password hash cost (default 12) |
| `AUTH_RATE_LIMIT` | Max register/login requests per IP per 15 min (default 20) |
| `JOIN_RATE_LIMIT` | Max `POST /join` per IP per minute (default 120) |
| `BROADCAST_THROTTLE_MS` | Min ms between live result/pulse broadcasts (default 300) |
| `CORS_ORIGIN` | `*` or comma-separated origins |
| `LOG_LEVEL` | pino level |
| `CLOUDINARY_CLOUD_NAME` / `_API_KEY` / `_API_SECRET` | From your Cloudinary dashboard; needed for image uploads (everything else works without them) |
| `CLOUDINARY_FOLDER` | Top folder for uploads (default `classpluse`) |

### Image uploads (optional)
Slide images and lecturer avatars use Cloudinary signed uploads. Create a free account at
cloudinary.com and copy the cloud name, API key and API secret from the dashboard into `.env`.
Without them, the "Add image" and profile photo actions show "Image uploads are not set up".
Keep the API secret private; it stays on the server.

### Server scripts
| Command | What it does |
|---|---|
| `npm run dev` | Start with auto-reload |
| `npm test` | Migrate the test DB, then run Jest (REST + socket.io integration) |
| `npm run typecheck` / `npm run build` | Type-check / compile to `dist/` |
| `npm run db:migrate` / `db:seed` / `db:reset` | Prisma migrations and seed |

## 3. Mobile app
```bash
cd apps/mobile
flutter pub get
flutter run                                  # Android emulator: talks to http://10.0.2.2:4000
```

The app finds the server at:
- **Android emulator:** `http://10.0.2.2:4000` (the host machine) by default
- **iOS simulator:** `http://localhost:4000` by default
- **Physical phones:** pass your computer's LAN IP, with the phone on the same Wi-Fi:
  ```bash
  flutter run --dart-define=API_URL=http://192.168.1.20:4000
  ```
  (Windows may ask to allow Node.js through the firewall the first time.)

Debug builds allow plain HTTP for local development; release builds need an HTTPS server.

### Try a full session (one lecturer + two students)
1. Start the server (above).
2. Lecturer device: **I'm a teacher** → log in with the demo account → open
   "POP Lecture 4: Loops" → **Present**. The waiting room shows the QR code and the code.
3. Each student device: **Join a session** → type the code (or **Scan QR code**). They see
   "You're in!" and the lecturer's joined count goes up.
4. Lecturer: **Start lecture**. Students answer; bars and the answered count update live.
   Students can switch to the **Pulse** tab any time; the lecturer's confusion pulse panel updates.
5. Toggle **Show live results to students** to share the totals. **Next slide**, then **Finish**
   to see the summary. Students land on "Thanks for joining".

Deep links: the QR encodes `classpluse://join/<code>`. To test without a camera on Android:
```bash
adb shell am start -a android.intent.action.VIEW -d "classpluse://join/123456"
```

### Mobile tests
```bash
flutter analyze
flutter test                                    # widget + accessibility-guideline tests
```
Integration tests need the server running with the seed data. Run each file on its own:
```bash
flutter test integration_test/student_flow_test.dart  -d flutter-tester   # no phone/emulator needed
flutter test integration_test/lecturer_flow_test.dart -d flutter-tester
flutter test integration_test/student_flow_test.dart  -d emulator-5554    # on an Android emulator
```
- **student_flow_test:** the test logs in as the demo lecturer over the API and starts a session,
  then drives the student UI: wrong code → error banner → real code → waiting room → answer
  (the lecturer receives it) → change answer → pulse → session ended, and checks the summary.
- **lecturer_flow_test:** drives the lecturer UI (login → Present → waiting room with QR and code
  → start) while two simulated students join, answer and send a pulse. It checks the live counts,
  bars, pulse panel, the results toggle, the next slide, Finish and the summary.
- The `flutter-tester` device runs the real app code and real HTTP/Socket.io traffic; only the
  phone's storage plugin is replaced by an in-memory store. It can run one integration file per command.
- Login is rate-limited (20 per 15 min). If you run the tests many times in a row and get a 429,
  restart the server (the limiter is in memory) or raise `AUTH_RATE_LIMIT` in `.env`.

### Screenshots without a device
`flutter test tool/screens_test.dart --update-goldens` renders 15 key screens with sample data to
`apps/mobile/build/screenshots/`. The current set is in [`docs/screenshots/`](docs/screenshots/).

### Using the Inter font
The theme asks for Inter and falls back to the system font. To bundle Inter, download the
TTF files from Google Fonts (OFL licence) into `apps/mobile/assets/fonts/` and add to `pubspec.yaml`:
```yaml
flutter:
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
        - asset: assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
```

## 4. API reference

### REST (prefix `/api/v1`)
Lecturer routes need `Authorization: Bearer <token>` from register/login.

| Method & path | Body | Notes |
|---|---|---|
| `POST /auth/register` | `{ name, email, password }` | → `201 { token, lecturer }` |
| `POST /auth/login` | `{ email, password }` | → `{ token, lecturer }` |
| `GET /auth/me` | | → `{ lecturer }` |
| `PATCH /auth/me` | `{ name?, avatarUrl? }` | `avatarUrl` from a signed upload, or `null` to remove |
| `POST /uploads/signature` | `{ kind: avatar\|slide }` | → `{ uploadUrl, apiKey, signature, params, maxBytes }`; send `params`, `api_key`, `signature` and `file` to `uploadUrl` |
| `GET /presentations` | | → `[{ id, title, slideCount, createdAt, updatedAt }]` |
| `POST /presentations` | `{ title }` | → presentation with `slides` |
| `GET/PATCH/DELETE /presentations/:id` | PATCH: `{ title }` | |
| `POST /presentations/:id/slides` | `{ type: POLL\|QUIZ, question, imageUrl?, options: [{ label, isCorrect? }] }` | 2–6 options; quiz has exactly one correct; `imageUrl` must come from a signed upload |
| `PATCH /slides/:id` | any of the above; options may carry `id` to keep them | |
| `DELETE /slides/:id` | | |
| `PATCH /presentations/:id/slides/reorder` | `{ slideIds: [...] }` | every slide exactly once |
| `POST /sessions` | `{ presentationId }` | → `{ sessionId, code, status, resumed }` |
| `GET /sessions/:id` | | lecturer state incl. `code`, `participants` |
| `GET /sessions/:id/summary` | | per-question counts, %, % correct, pulse |
| `POST /join` | `{ code, participantToken? }` | no auth; → `{ participantToken, sessionId }`; 404 for invalid/ended codes |

Errors always look like `{ "error": { "code": "VALIDATION_ERROR", "message": "...", "details": [...] } }`.

### Socket.io
Connect to the server URL with `auth: { token, sessionId }` (lecturer) or
`auth: { participantToken }` (student). Each client event takes an ack callback that receives
`{ ok: true, ... }` or `{ ok: false, error: { code, message } }`.

| Direction | Event | Payload |
|---|---|---|
| lecturer → server | `session:start`, `slide:next`, `session:end` | none |
| lecturer → server | `slide:goto` / `results:toggle` | `{ slideId }` / `{ show }` |
| student → server | `answer:submit` / `pulse:set` | `{ slideId, optionId }` / `{ state: FOLLOWING\|LOST }` |
| server → room | `session:state` | `{ status, currentSlide, showResultsToStudents, totalSlides, presentationTitle, ... }` |
| server → room | `participants:count` | `{ count }` |
| server → lecturer (+ students if results shown) | `results:update` | `{ slideId, counts: [{ optionId, count }], answered, participants }` |
| server → lecturer | `pulse:update` | `{ following, lost, total }` |
| server → student | `me:state` | `{ answer, pulse }` (after reconnect) |
| server → room | `session:ended` | `{ sessionId }` |

## Troubleshooting
- **Android emulator won't start ("Insufficient RAM")**: close other apps, or start it with
  less memory: `emulator -avd <name> -memory 2048`. If it crashes on start, try `-gpu swiftshader_indirect`.
- **App shows "Can't reach the server"**: check the server is running and the URL fits your device
  (see above). On a phone, `http://<LAN-IP>:4000/health` should open in its browser.
- **`npm test` fails to connect**: check `TEST_DATABASE_URL` and that the dev user has `CREATEDB`.
