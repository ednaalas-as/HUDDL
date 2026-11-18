# HUDDL — Project Overview

> Audit date: **18 Nov 2026**. Everything here was checked against the source code in `~/Desktop/HUDDL` and the running local Firebase Emulator Suite. Nothing runs in a production Firebase project yet (see §6).

## 1. What HUDDL is

HUDDL is a **native iOS app** that helps strangers find people to play sports with. A host posts a game, for example a 2v2 beach volleyball match, and nearby players apply to join.

The core idea comes from dating apps, but **you swipe on games, not people**:
- **Swipe right** = Interested. The game is saved to your Interested list, where you can apply.
- **Swipe left** = Not interested. The game is moved aside, and you can bring it back later.

On top of matchmaking, HUDDL is a small **sports community**. After games, players post results, photos and "moments". The Home feed shows match results, hosting activity, and "X joined Y" updates.

Tagline from the design: **"Match Up. Match On."**

## 2. Objectives

1. Let players **discover games within 10 km** of their home area. The sample area is Lucena City, Quezon.
2. Let hosts **create games with fixed teams**, choose a format (1v1–6v6 or custom), and decide who joins.
3. Keep games **fair and reliable**:
   - Teams are fixed, and there are no substitutes.
   - Applying requires a commitment checkbox.
   - Capacity checks run on the server.
4. Support **communication**: team chats per game and direct messages.
5. Support **community**: a feed of results and moments, with likes, comments and reposts.
6. Protect **privacy and safety**:
   - Emails are never public.
   - Blocks are silent, and reports are anonymous.
   - Security rules restrict every read and write.
7. Build it **natively with SwiftUI**, with **Firebase as the only backend**.

## 3. Technology summary

| Layer | Technology | Where to see it |
|---|---|---|
| Client | SwiftUI, iOS 17+, Swift 5, Xcode 26.0.1 | `HUDDL/` |
| Backend | Firebase: Auth, Cloud Firestore, Cloud Storage, Cloud Functions (TypeScript, Node 20), Cloud Messaging, Security Rules | `firebase/` |
| Firebase iOS SDK | **12.19.3** (Swift Package Manager). Firebase 13 needs Xcode 26.2+. | `HUDDL.xcodeproj/project.pbxproj` |
| Local backend | Firebase Emulator Suite, project ID **`demo-huddl`** | `firebase/firebase.json`, `firebase/.firebaserc` |
| Design source | Figma file "HUDDL" (ENVERGA EDUCATION team) | — |

## 4. Feature list (scope)

| # | Feature | Status |
|---|---|---|
| 1 | Splash + 3 onboarding pages | Implemented, UI-tested |
| 2 | Sign up (username, email, password) and sign in by **username** | Implemented, UI-tested |
| 3 | Forgot password (reset link, 60 s resend cooldown) | Implemented, UI-tested on emulator |
| 4 | Profile setup (photo, sports, skill, home area) → Welcome | Implemented, UI-tested (without photo) |
| 5 | Home feed (results, moments, hosting/joined cards, like/comment/repost/share/hide/report) | Implemented; like, comment and menu are UI-tested |
| 6 | Search (games and players, recent searches) | Implemented; player search is UI-tested |
| 7 | Discover swipe deck (10 km radius) | Implemented, UI-tested |
| 8 | Interested / Not interested lists (Active/Expired, sort, move back, remove) | Implemented; main paths UI-tested |
| 9 | Game details (all states) | Implemented; joined state + leave dialog UI-tested |
| 10 | Apply (team, solo/group, note, commitment) | Implemented; solo apply UI-tested, group apply only backend-tested |
| 11 | Host a game / Edit / Cancel | Implemented; host + edit UI-tested, cancel backend-only |
| 12 | Applicants (accept / decline with private reason / no room) | Implemented, UI-tested |
| 13 | Personal invites (from game or profile; accept/decline) | Implemented; accept-from-notification UI-tested |
| 14 | Team chat and direct messages (text, photo, retry) | Implemented; DM text UI-tested |
| 15 | Player profiles, block/unblock, report | Implemented, UI-tested |
| 16 | Notifications list (invite, applied, accepted, ended…) | Implemented; invite flow UI-tested |
| 17 | Edit profile, Sports & skill, Password & security | Implemented; edit profile save UI-tested |
| 18 | Settings (notification toggles, invite privacy, help, contact support, terms, log out, delete account) | Implemented; toggles UI-tested |
| 19 | Post-game: post result, share moments, read-only ended chat | Implemented; **not UI-tested** (backend checks only) |
| 20 | Reviews | **Display only.** Writing reviews was never designed, and the rules block creating them. |

See `HUDDL_KNOWN_LIMITATIONS.md` for every gap.

## 5. Users in the system (seeded)

Eight real-person test accounts were requested by the project owner. Each has its own Firebase Auth account:
- Edna Alas-as and Bea Anne Balmes (volleyball)
- Roselle Jean De Leon and Kyle Allen Abandia (badminton)
- Jhon Lloyd Valencia and Thessalonica Surell (chess)
- Althea Trisha Mae Aringo and Desiree Ann Ferrer (billiards)

Usernames and their demo roles are in `HUDDL_QUICK_REFERENCE.md`. Passwords are only in the private file.

HUDDL has **no administrator role**. Every account is an ordinary player. "Host" isn't an account type; it's the relationship between a user and a game they created.

## 6. Environment honesty

- The app currently runs **only against the local Firebase Emulator Suite** (project `demo-huddl`).
- A real Firebase project, **`huddl-app-ph`** (display name "HUDDL"), was created on 18 Nov 2026 under the Google account that ran `firebase login`. It's on the free **Spark** plan, with an iOS app registered (`com.huddl.app`) and a Cloud Firestore database in **asia-southeast1 (Singapore)**, with HUDDL's security rules and indexes deployed. It **can't run the full app**: Cloud Functions and Cloud Storage need the paid **Blaze** plan, and no payment method is available. So the app is **presented on the Firebase Emulator Suite**, and the real project's config file (`firebase/GoogleService-Info.plist`, git-ignored) is deliberately **not** bundled into the app.
- The eight accounts exist **only in the local emulator**, not in `huddl-app-ph`.
- Moving to production is documented in `README.md` ("Moving to a real Firebase project").

## 7. Design decisions taken on the owner's behalf (open business rules)

The design left these rules open. The implementation uses minimal, clearly marked assumptions:
- Only the **host** may post a game's result. See `postResult` in `firebase/functions/src/index.ts:457`.
- A game **ends** at `startAt + durationMin`, with a default of 120 minutes. See `runLifecycle`, `index.ts:740`.
- **Rating** shows "—" until a formula exists. **Reliability** only counts "late drops" (leaving within 24 h of the start).
- **Chess and Billiards** were added as sport chips in the existing style for the seeded players.
