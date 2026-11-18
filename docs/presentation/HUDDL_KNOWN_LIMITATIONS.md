# HUDDL — Known Limitations & Honest Disclosures

Status legend:
- ✅ **Verified:** tested in the running app or the backend suite
- 🟡 **Implemented, not verified in the app:** the code exists and compiles, maybe backend-tested, but no app test
- ⛔ **Needs production config:** can't work on the local emulator
- ❌ **Not implemented**

## 1. Previously reported items, re-checked against the code (18 Nov 2026)

| Item | Status | What's actually there |
|---|---|---|
| Photo & video uploads | 🟡 | `StorageService.uploadImage/uploadVideo`; storage rules enforce owner folders and size limits. Never uploaded during testing. |
| Share moments with media | 🟡 | `ComposeMomentsView` → `createPost`. Backend checks pass (empty post refused, tags limited, post created, "Only me" private). The composer screen wasn't driven by a test. |
| Posting match results | 🟡 | `PostResultView` → `postResult` function (host-only, score validation, stats, feed post, notifications). **No automated check covers it.** |
| Game-ended chat behaviour | 🟡 | Rules refuse messages when `readOnly`; the lifecycle sets `readOnly`. The scheduler doesn't run locally; `devRunLifecycle` exists but wasn't exercised. |
| Account deletion | 🟡 | `DeleteAccountView` (type DELETE + confirm) → `deleteAccount` cascade. Not run, to protect the demo accounts. |
| Home-area location picker | 🟡 | List selection works in profile setup (the default). "Use my current location" (CoreLocation) wasn't tested. |
| Group applications | 🟡 | UI and server support groups; the server rejects groups on solo games (tested). A successful group application wasn't tested end to end. |
| Google & Facebook sign-in | ⛔/❌ | Buttons exist and show an honest "available once HUDDL's Firebase project is connected" message. No provider integration has been built yet. |
| Real push notifications | ⛔ | FCM code exists (`PushService`, `sendPush`). Disabled in emulator mode. Needs production plus an APNs key. **Unverified.** |
| Production password-reset emails | ⛔ | Works on the emulator (the link appears in the Emulator UI, not an inbox). The design's "expires in 30 minutes" isn't configurable in default Firebase. |
| Side-by-side Figma verification | 🟡 | Checked against Figma specs: onboarding, sign up/in, Home, Profile, My game, Applicants, confirm dialog, Discover card layout. **Not compared side by side:** Game details (non-host), Apply, Host form, Notifications, Chat, Search, Settings sub-screens, Share moments, Post result, Help/Terms. |

## 2. Other limitations found during the audit

1. **Production project is only partly deployed.** `huddl-app-ph` exists (Spark plan) with Firestore in Singapore and rules/indexes deployed, but **Cloud Functions and Storage need the Blaze plan**, which requires a payment method we don't have. Accounts, data and functions run only in the local emulator `demo-huddl`. Once billing exists, deployment takes about 30 minutes and needs no code changes.
2. **Scheduled lifecycle doesn't run locally** (no Pub/Sub emulator). So games don't auto-move to "started/ended", Expired notifications aren't sent, and chats don't auto-lock unless `devRunLifecycle` is called or a result is posted.
3. **`fcmToken` sits in the public `users/{uid}` document.** Any signed-in user can read it. Not a password, but it should move to `users/{uid}/private` before production.
4. **User profiles are readable by every signed-in user.** Fine for a social app (names, sports, stats), but there's no "private profile" option.
5. **Search filters on the device** (up to 200 games/players). Fine for a campus community; large-scale search would need an index service. Within Firebase that means a different query design or a Firebase Extension.
6. **Reliability score and rating:** no formula. Rating shows "—"; late drops are counted (`stats.lateDrops`) but never shown.
7. **Reviews:** display only; writing reviews isn't designed, and the rules block creating them. 0 reviews exist in the data.
8. **Flagging a result** within 24 h: the deadline is stored (`flagDeadline`), but there's no flag button (not designed).
9. **Only the host can post results** (an assumption; the design left this open).
10. **Venues are a fixed list of 6** from the design, with approximate coordinates and no photos. Hosts can't add venues or upload venue photos (not designed).
11. **Terms & Privacy text is placeholder** and must be replaced with reviewed legal text.
12. **Extra emulator accounts:** UI test 2 creates a new `testerNNNN@huddl.test` account each run. One manual account also exists (username `ednaalasas`). The seed doesn't delete these; a full wipe does (see the Database Guide).
13. **The app forces light mode**; dark mode wasn't designed.
14. **Onboarding pages 1–2 artwork** was exported at 1× from Figma and may look slightly soft.
15. **Profile photos for the 8 players** aren't set (initials are shown, as the project owner instructed).
16. **"Remember me"** is stored on the device; turning it off signs out at the next launch, not immediately.
17. **Swipe-left/right on a phone** works with drag gestures; only the buttons were automated in tests.
18. **iPad/landscape:** not supported (iPhone portrait only, by configuration).

## 3. Local emulator vs production: what works where

| Capability | Local emulator (now) | Needs production project |
|---|---|---|
| Sign up / sign in (username or email) | ✅ | Also needs the `HUDDL_WEB_API_KEY` env var and a Token Creator role for custom tokens |
| Firestore data, real-time listeners, rules | ✅ | Deploy rules + indexes |
| Cloud Functions (callable + triggers) | ✅ | Blaze plan + `firebase deploy` |
| Scheduled lifecycle | ❌ (manual dev trigger only) | ✅ automatically every 10 min |
| Storage uploads | ✅ in code, not exercised | Deploy storage rules |
| Push notifications | ❌ skipped | APNs key + Push capability |
| Password reset email | Link shown in Emulator UI | Real email delivery |
| Google / Facebook login | ❌ | Provider setup + SDK work |
| Offline persistence | In-memory cache (by design) | Persistent cache enabled automatically |

## 4. Future improvements (suggested)

1. Create the production project; deploy rules, functions and indexes; run the production seed with real emails.
2. Move `fcmToken` to a private subcollection; add App Check to block non-app clients.
3. Add UI tests for media upload, Post result, Share moments, lifecycle (via `devRunLifecycle`), cancel and delete.
4. Define the reliability and rating formulas; add review writing and result flagging (needs design).
5. Server-side search for larger communities; pagination for feed and chat history.
6. Venue suggestions and photos; host-uploaded venue photos.
7. Accessibility pass (VoiceOver labels already exist on main controls; test with large text).
8. Analytics/Crashlytics (Firebase), with the owner's consent.
