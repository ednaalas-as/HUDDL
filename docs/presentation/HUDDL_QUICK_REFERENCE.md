# HUDDL — Quick Reference (last-minute review)

**No passwords here.** They're in `HUDDL_ACCOUNTS_PRIVATE.md` (local only, never commit).

## Elevator pitch
"HUDDL is a native SwiftUI app that matches people for sports games. You swipe on games instead of people, apply with fixed teams, chat with your team, and share results afterwards. The backend is entirely Firebase: Auth, Firestore, Storage, Cloud Functions, Messaging and Security Rules. It currently runs on the Firebase Emulator Suite."

## Stack facts
- SwiftUI, iOS 17+, Xcode 26.0.1 · Firebase iOS SDK **12.19.3** · Cloud Functions TypeScript, Node 20, region `asia-southeast1`
- Emulator project ID **`demo-huddl`** · ports: Auth 9099, Firestore 8080, Storage 9199, Functions 5001, UI 4000
- **Real project `huddl-app-ph`** exists (Spark plan): Firestore in Singapore with rules and indexes deployed. Functions and Storage need Blaze (no card), so the demo runs on the emulator.

## Demo accounts (by username)

| Username | Name | Sport | Demo role |
|---|---|---|---|
| `ednaalas-as` | Edna Alas-as | Volleyball | Main user / host (Beach Volley Sunday) |
| `beaannebalmes` | Bea Anne Balmes | Volleyball | Invites Edna; DM partner; hosts Saturday 6v6 Open |
| `roselledeleon` | Roselle Jean De Leon | Badminton | Pending applicant; hosts Friday Night Doubles |
| `kyleabandia` | Kyle Allen Abandia | Badminton | Block/report target; hosts Badminton Smash Session |
| `jhonlloydvalencia` | Jhon Lloyd Valencia | Chess | Pending applicant (decline demo); hosts Rapid Chess Ladder |
| `thessasurell` | Thessalonica Surell | Chess | **Applicant in the demo** |
| `altheaaringo` | Althea Trisha Mae Aringo | Billiards | Hosts 8-Ball Night (group play) |
| `desireeferrer` | Desiree Ann Ferrer | Billiards | Joined Saturday 6v6 (leave-game demo) |

There's no admin role. Every account is a normal player; "host" means "created this game".

## Commands
Start the emulators (leave running):
```bash
~/Desktop/HUDDL/firebase/emulators.sh
```
Reset the demo data:
```bash
npm --prefix ~/Desktop/HUDDL/firebase/functions run seed
```
Build and run in the simulator:
```bash
~/Desktop/HUDDL/run-sim.sh
```
Backend checks (re-seed afterwards):
```bash
npm --prefix ~/Desktop/HUDDL/firebase/functions test
```
Database viewer: http://127.0.0.1:4000

## Ten concepts to explain confidently
1. **Username login:** Cloud Function `signInWithUsername` finds the email privately → custom token. Emails are never public.
2. **Unique usernames:** a transaction creates `usernames/{name}` + `users/{uid}` together.
3. **Security rules:** server-enforced. Users write only their own data; games are changed only by functions.
4. **No overbooking:** `acceptApplication` is a transaction that re-checks capacity.
5. **No duplicates:** document ID = user's uid (applications, invites, likes, reposts).
6. **10 km discovery:** geohash cells + exact haversine distance.
7. **Real time:** Firestore snapshot listeners (feed, rosters, chat, notifications); no polling.
8. **Two-way silent blocking:** a private `blockedBy` document written by a trigger.
9. **Notifications:** server writes `notifications/{uid}/items`, and a trigger sends FCM (production only).
10. **NoSQL design:** embedded rosters, subcollections for growing data, denormalized player refs.

## Test numbers (latest)
- **4/4** unit tests · **13/13** UI tests (incl. all 8 accounts signing in) · **33/33** backend checks
- Fixed bugs worth mentioning:
  - 2 launch crashes;
  - tab bar covering Send;
  - rules hiding likes and PENDING chips;
  - block not saving;
  - "-1 likes".

## Say honestly if asked
Demo runs on the emulator. The real project exists, but full deployment needs the Blaze plan (payment method). Push, Google/Facebook login and real emails need production. Media upload, post result, share moments, the automatic lifecycle and delete account are implemented but not yet tested in the app.

## Key files
`FirebaseBootstrap.swift` · `SessionStore.swift` · `Router.swift` · `AppData.swift` · `GameService.swift` · `HuddleView.swift` · `GameDetailsView.swift` · `functions/src/index.ts` · `firestore.rules` · `functions/src/seed.ts`
