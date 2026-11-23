# ClassPluse — Progress

## Phase 1 — Scaffold, DB, seed, health check ✅ (2026-11-20)
- [x] Monorepo layout, `.gitignore`, README (server setup)
- [x] `docker-compose.yml` (Postgres 17 + `classpluse_test` DB init script)
- [x] Server: Express 5 + TS strict, zod env validation, helmet, cors, pino, consistent error shape
- [x] `GET /health` and `GET /api/v1/health` (checks DB)
- [x] Prisma 7 schema (`@prisma/adapter-pg`), init migration, seed (demo lecturer + "POP Lecture 4: Loops")
- [x] `npm test` migrates the test DB first; 3/3 health tests pass; `npm run build` OK

### Decisions / notes
- **Local DB:** Docker isn't installed on this machine; using native PostgreSQL 17 (approved) with
  dev user `classpluse`/`classpluse`, same as the docker-compose defaults.
- **Session.code** is unique only among non-ENDED sessions (partial unique index
  `Session_code_active_key` in raw SQL in the init migration), plus a 6-digit CHECK constraint.
  Codes can be reused after a session ends. `prisma migrate diff` shows no drift.
- `PulseState.participantId` is the primary key (one current state per student).
- Added `createdAt/updatedAt` on `Slide`; enum names `SlideType`, `SessionStatus`, `PulseValue`.
- TypeScript pinned to 5.9 (ts-jest doesn't support TS 7 yet); Prisma 7.10; Express 5.

## Phase 2 — Auth + presentations/slides REST API ✅ (2026-11-21)
- [x] `POST /auth/register`, `POST /auth/login`, `GET /auth/me` (bcrypt, HS256 JWT, rate-limited 20/15 min/IP)
- [x] `GET/POST /presentations`, `GET/PATCH/DELETE /presentations/:id`
- [x] `POST /presentations/:id/slides`, `PATCH/DELETE /slides/:id`, `PATCH /presentations/:id/slides/reorder`
- [x] 47 tests passing (auth, presentations, slides, health); typecheck clean; smoke-tested against the seed

### Decisions / notes
- **Ownership:** another lecturer's presentation/slide returns **404, not 403**, so ids aren't revealed.
- **Editing lock:** presentations and slides can't be changed or deleted while a session for them is
  WAITING or LIVE (`409 SESSION_ACTIVE`).
- **Slide rules:** 2–6 options; QUIZ has exactly one correct option; POLL has none; labels unique
  (case-insensitive); question ≤ 300 chars; `imageUrl` must be https (Phase 7 will restrict it to
  our Cloudinary folder).
- **Editing options:** `PATCH /slides/:id` with `options` replaces the list. Options sent back with
  their `id` keep their identity (and past responses); options left out are deleted along with
  their responses. A type change is validated against the merged result.
- **Order** stays contiguous (0..n-1) after delete; reorder must list every slide exactly once.
- **Login** returns the same 401 for an unknown email and a wrong password, with similar timing.
- **Response shapes:** resources are returned directly (no `data` wrapper); lists are arrays.
  Errors: `{ error: { code, message, details? } }`.
- Tests run serially (`maxWorkers: 1`) because all files share the test DB; bcrypt cost 4 in tests.

## Phase 3 — Sessions, join, Socket.io realtime ✅ (2026-11-21)
- [x] `POST /sessions`, `GET /sessions/:id`, `GET /sessions/:id/summary`, `POST /join` (rate-limited)
- [x] Socket.io: auth on connect (lecturer JWT + sessionId, or participant token), rooms
  `session:<id>` and `session:<id>:lecturer`, all events from the spec with zod-validated payloads
  and ack callbacks `{ ok: true, ... } | { ok: false, error: { code, message } }`
- [x] Results/pulse/count broadcasts throttled per session (300 ms, leading + trailing)
- [x] Reconnect: the client gets `session:state`, counts, results (if allowed) and its own state again
- [x] 66 tests passing, including the full-flow socket.io-client test (lecturer + 3 students → end → summary)

### Decisions / notes (made overnight, please review)
- **Participant tokens are stored hashed** (SHA-256 in `Participant.anonToken`); the raw token
  only lives on the phone. No schema change.
- **Rejoin:** `POST /join` accepts an optional `participantToken`; if it belongs to that session the
  student keeps the same identity (so an app restart doesn't count them twice).
- **`POST /sessions` resumes** an existing WAITING/LIVE session for the presentation (200,
  `resumed: true`) instead of creating a second one, e.g. after the lecturer's app crashes.
- **Join rate limit** is 120/min per IP (`JOIN_RATE_LIMIT`) because a class usually shares one
  school Wi-Fi IP; 1,000,000 codes still make guessing impractical.
- **Visibility:** students never receive `isCorrect`, the code, or pulse totals. `results:update`
  goes to the lecturer room only, or to everyone when "Show live results" is on.
- **Extra events:** `me:state { answer, pulse }` is sent to a reconnecting student so the app can
  restore their selection. `session:state` also carries `totalSlides`, `currentSlide.index`, and
  for lecturers `code`, `presentationTitle`, `isLastSlide`.
- **Answers** are accepted only for the current slide of a LIVE session (`SLIDE_CLOSED` otherwise,
  so the app drops stale queued answers). **Pulse** works in WAITING and LIVE.
- `slide:next` on the last slide returns `NO_MORE_SLIDES`; the app shows "End session" instead.
- `session:end` disconnects student sockets; their tokens stop working for sockets and the code
  is freed for reuse.
- Per-socket limit of 10 events/second (spam taps get `RATE_LIMITED`).
- Fixed a race found by the tests: events sent immediately after connecting were dropped.
- Follow-up idea (not done): auto-end sessions left WAITING/LIVE for many hours.

## Phase 4 — Flutter shell ✅ (2026-11-21)
- [x] Flutter 3.47 project (`app.classpluse`), Riverpod 3, go_router 18, dio, socket_io_client 3,
  mobile_scanner 7, qr_flutter, shared_preferences
- [x] Theme from the **Figma file's variables** (read via the Figma MCP): brand `#5B4CF0`, tint
  `#EEEBFF`, bg `#F8F9FC`, text `#0F172A`/`#64748B`, border `#E6E8F0`, success `#15803D`,
  radius 12/16, Inter type scale. Danger `#B91C1C` from the spec (passes AA on white and on tint).
- [x] Widgets: PrimaryButton, SecondaryButton, AnswerOptionCard, CodeInput + NumberKeypad,
  LiveBadge/StatusPill, ResultBar, PulseButton, InlineBanner, EmptyState, SkeletonLoader, plus
  AppLogo, ListRowCard, StatCard, ScreenHeader, LabeledField/PasswordField
- [x] Welcome screen, login, sign-up (validation, error banners, loading), auth persisted, auto
  logout on 401, route guard for `/lecturer/**`
- [x] Deep link `classpluse://join/<code>` (Android intent filter + iOS URL type) → join screen
- [x] Widget tests: CodeInput, AnswerOptionCard, PulseButton (20 tests)

## Phase 5 — Lecturer screens ✅ (2026-11-21)
- [x] Home: greeting, Quick Start, presentation list (loading skeleton / empty / error + retry)
- [x] Builder: slide list with drag-to-reorder (+ "Move up/down" menu and screen-reader actions),
  add-slide sheet (Poll / Quiz), delete, rename, delete presentation, Present
- [x] Slide editor: type switch, question, 2–6 options, mark correct (quiz), client validation
  matching the server
- [x] Waiting room: QR (`classpluse://join/<code>`), large code "482 913", live joined count, Start
- [x] Live dashboard: slide x of n, joined/answered pills, large result bars (projector-readable,
  correct answer marked with icon + text), confusion pulse panel (% following / % lost with
  icons, numbers, and a warning at ≥ 30% lost), "Show live results to students" switch,
  End / Next slide (Finish on the last slide), offline banner
- [x] Summary: participants, responses, final pulse, per-question rows → detail with Previous/Next

## Phase 6 — Student screens ✅ (2026-11-21)
- [x] Join: six boxes + on-screen keypad, invalid code banner keeps digits, Scan QR (camera
  permission + denied state), auto-join from deep link / scan, rejoin with the stored token
- [x] Waiting room ("You're in!", joined count), question (large options, Submit disabled until a
  choice, "Answer recorded", change answer until the lecturer moves on), class results when allowed
- [x] Confusion pulse on its own tab, always available; repeat taps send nothing
- [x] Offline: banner with the spec text; answers saved to shared_preferences and resent on
  reconnect (stale ones dropped via `SLIDE_CLOSED`); pulse resent too
- [x] Ended screen with "Join another session"; Welcome shows "Join another session" for returning students

### Decisions / notes (made overnight, please review)
- **Design source:** the Figma file was readable, so its tokens/layouts were used over the spec's
  defaults (e.g. brand `#5B4CF0` instead of `#5B4BE6`, bg `#F8F9FC` instead of `#F7F7FB`).
- **Out-of-scope screens in the design** (Library, Insights, onboarding, notifications, Google
  sign-in, tab bar, CSV export) were left out. The lecturer home is a single screen.
- **Pulse placement:** the design gives the pulse its own screen, so students get a bottom bar with
  "Question" and "Pulse" tabs; the pulse tab works in the waiting room too.
- **Font:** Inter is set as the font family with system fallbacks, but the font files aren't
  bundled (that needs a download). README explains how to add them.
- **Lecturer token** is stored in shared_preferences (spec names it for the student token only).
  `flutter_secure_storage` would be safer; not added because it changes the stack.
- **Server change:** `session:state` now includes `presentationTitle` for students too (shown in
  the student "Live · <title>" badge; not personal data).
- **Leaving the waiting room** with ✕ keeps the session open; pressing Present again resumes it.
- Dev builds allow plain HTTP (debug/profile manifests only); release builds need HTTPS.
- The QR encodes `classpluse://join/<code>`; the scanner also accepts a plain 6-digit code.

## Phase 7 — Polish, accessibility, README ✅ (2026-11-21)
- [x] Contrast: every text/background pair checked against WCAG 2.1 AA (all ≥ 4.5:1 except the
  disabled button, which WCAG exempts). E.g. secondary text 4.52, white on brand 5.62,
  success pill 4.57, danger banner 5.30.
- [x] Automated a11y tests (`test/a11y_test.dart`): Android/iOS tap-target, labelled-target and
  text-contrast guidelines on Welcome, Join, Login, Session ended, pulse buttons and result bars
- [x] Screen-reader labels on every custom control (code boxes, keypad, options, pulse, bars,
  QR, live counts as live regions); colour never the only signal (icons + text everywhere)
- [x] Text scaling respected (capped at 160%); body text 16 px; projector-sized dashboard bars
- [x] Fixed after visual review: button text didn't inherit the font family, logo stretched in
  lists, the pulse split bar didn't render, student "Live" badge was truncated
- [x] Integration tests for both roles (see README); screenshot tool + `docs/screenshots/`
- [x] Fixed: harmless `WebSocketConnectionClosed` thrown by socket_io_client when the server ends
  a connection is now swallowed in a guarded zone (it surfaced as an uncaught error)
- [x] README: setup for both apps, env vars, physical devices, full session walkthrough, tests,
  API reference, troubleshooting
- [x] Cloudinary signed uploads (added 2026-11-21 after you added the keys): slide images and the
  lecturer avatar. See "Image uploads" below.

### Image uploads (Cloudinary)
- `POST /api/v1/uploads/signature { kind: avatar|slide }` (lecturer only, 30/min per IP) returns a
  signature for: folder `classpluse/<avatars|slides>/<lecturerId>`, formats jpg/jpeg/png/webp, and
  a resize-on-upload (`c_limit` 512 px for avatars, 1600 px for slides). The API secret never
  leaves the server; the app sends the file straight to Cloudinary, without our JWT.
- When a URL is saved (`POST/PATCH` slide `imageUrl`, `PATCH /auth/me { avatarUrl }`) the server
  checks it is in **this lecturer's** folder of our cloud, then asks Cloudinary's Admin API for the
  real format and size (max 5 MB). Anything else → `400 INVALID_IMAGE`; Cloudinary down → `502`.
- Replacing or removing an image, deleting a slide, or deleting a presentation deletes the
  image(s) from Cloudinary (best effort, after the database change succeeds).
- App: "Add image" on the slide editor (gallery or camera, scaled on the device, progress bar,
  Replace/Remove); the image shows above the question for students and on the lecturer dashboard.
  The home screen's account button is now the avatar (initials until a photo is added).
- Verified against the real Cloudinary account: upload, tampered signature refused (401), saving,
  serving, avatar/slide folder separation, deletion. Test images were removed afterwards.

### Decisions / notes (please review)
- **Added `image_picker`** (official Flutter plugin) to choose/take photos; there's no way to pick an
  image with the listed packages. Uploads use the existing `dio`. Server signing uses Node's
  `crypto` (no Cloudinary SDK added).
- **Data model unchanged**: uses the existing `Lecturer.avatarUrl` and `Slide.imageUrl`.
- **Slide `imageUrl` is now restricted** to our Cloudinary folder (any https URL was accepted before).
- New `PATCH /auth/me` also lets the name be changed (no UI for that yet).
- iOS: added the photo-library permission text and widened the camera text (QR scan or photo).

## Verification status (2026-11-21)
| Check | Result |
|---|---|
| Server `npm test` (REST + socket.io full-flow + uploads) | ✅ 88/88 |
| Server typecheck / build | ✅ |
| `flutter analyze` | ✅ no issues |
| `flutter test` (widgets + a11y + uploader) | ✅ 31/31 |
| Real Cloudinary upload via the app's uploader + local server | ✅ (one-off check, images deleted) |
| `integration_test/student_flow_test.dart` (flutter-tester, real server) | ✅ |
| `integration_test/lecturer_flow_test.dart` (flutter-tester, real server, 2 simulated students) | ✅ |
| Debug APK build (Android) | ✅ builds (`build/app/outputs/flutter-apk/app-debug.apk`) |
| Run on the Android emulator | ⚠️ **not verified**: the Pixel 6a emulator ran out of memory on this 8 GB PC (other apps open) and stopped responding during install |
| Real phones (1 lecturer + 2 students) | ⚠️ **not verified**: needs your devices (see README "Try a full session") |

### Environment notes
- `android/gradle.properties`: Gradle heap lowered from the template's 8 GB to 2 GB, and Kotlin
  incremental compilation turned off (it breaks when the project is on D: and the pub cache on C:).
- The first Android build auto-installed SDK CMake 3.22.1 (license accepted earlier).

## Next (suggested)
- Run the app on real devices and adjust anything that feels off.
- Optional: `flutter_secure_storage` for the lecturer token, auto-ending stale sessions, bundling Inter.
