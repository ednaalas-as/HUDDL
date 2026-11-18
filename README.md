# HUDDL — native iOS (SwiftUI + Firebase)

HUDDL connects players so they can play sports together: swipe on games, apply or host, chat with your team, and share results and moments after the game.

- **Client:** SwiftUI, iOS 17+, built with Xcode 26.0.1
- **Backend:** Firebase only. Auth, Cloud Firestore, Cloud Storage, Cloud Functions (TypeScript, `asia-southeast1`), FCM and Security Rules
- **Firebase iOS SDK:** 12.19.3 via Swift Package Manager. Firebase 13 needs Xcode 26.2+.
- **Design source of truth:** Figma file `HUDDL` (ENVERGA EDUCATION team)

## Run it locally (emulators, no real Firebase project needed)

Requirements: Xcode 26, Node 20, `firebase-tools` (`npm i -g firebase-tools`), and Java 21. The emulators need Java 21; install it with `brew install openjdk@21`.

1. **Start the Firebase emulators** (Auth, Firestore, Storage, Functions) and leave this running:
   ```bash
   ./firebase/emulators.sh
   ```
   Emulator UI: http://127.0.0.1:4000
2. **Seed the 8 player accounts and sample data** in a second terminal:
   ```bash
   npm --prefix firebase/functions run build && npm --prefix firebase/functions run seed
   ```
   Each player gets a real Firebase Auth account, a Firestore profile and a reserved username. Temporary passwords go to `firebase/functions/seed-credentials.local.json`, which is git-ignored and never committed.
3. **Build and launch** in the iPhone 17 Pro simulator:
   ```bash
   ./run-sim.sh
   ```
   Or open `HUDDL.xcodeproj` in Xcode and press Run. Without a `GoogleService-Info.plist` the app automatically uses the local emulators under the offline demo project `demo-huddl`.
4. Sign in with any seeded **username** (e.g. `ednaalas-as`) and its temporary password from the local credentials file.

## Tests

```bash
npm --prefix firebase/functions test        # backend + security-rules smoke test (needs emulators + seed)
xcodebuild test -project HUDDL.xcodeproj -scheme HUDDL -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
The scheme runs the unit tests (`HUDDLTests`) and the end-to-end UI tests (`HUDDLUITests`), which drive the real app against the emulators. Re-seed before running the UI tests, because they change data.

## Moving to a real Firebase project (later)

> Status: the project **`huddl-app-ph`** already exists (alias `production` in `firebase/.firebaserc`) on the free Spark plan. Its Firestore database is in `asia-southeast1`, with rules and indexes deployed, and the iOS app is registered. Its config is saved at `firebase/GoogleService-Info.plist` (git-ignored). Steps 3–5 below need the **Blaze** plan.

1. Create the project in the Firebase console. Enable Email/Password auth, Firestore, Storage and Functions (Blaze plan).
2. Add an iOS app with bundle ID `com.huddl.app` and drop `GoogleService-Info.plist` into `HUDDL/Resources/`. It's git-ignored.
3. Deploy rules, indexes and functions: `cd firebase && firebase use <project-id> && firebase deploy`.
   - Set `HUDDL_WEB_API_KEY` for the `signInWithUsername` function.
   - Grant the functions service account the **Service Account Token Creator** role, which custom-token sign-in needs.
4. Seed real accounts: put real emails in the local credentials file, then run
   ```bash
   HUDDL_SEED_PRODUCTION=1 GOOGLE_APPLICATION_CREDENTIALS=key.json npm --prefix firebase/functions run seed
   ```
5. For push notifications, upload an APNs key in Firebase → Cloud Messaging and enable the Push capability in Xcode.
6. Google and Facebook sign-in need provider setup and app IDs before those buttons can do more than explain they aren't available yet.

## Project layout

```
HUDDL/App            app entry, router (typed routes, one NavigationStack per tab), shared live data
HUDDL/DesignSystem   colors/gradients/Inter, header, floating tab bar, buttons, chips, toast, dialogs, sheets, fields
HUDDL/Models         Codable Firestore models
HUDDL/Services       Firebase bootstrap, session/auth, game/social/chat/notification services, storage, push
HUDDL/Features       Auth, Huddle, Game, Host, Social, Chat, Profile, Settings
firebase/            rules, indexes, Cloud Functions (trusted operations + triggers), seed, smoke test
```

## Assumptions where the design left rules OPEN (please confirm)

- Only the **host** posts a game's result. Opponents have a 24 h flag window, but no flag UI was designed.
- A game **ends** at start + its duration (default 2 h). It moves to Interested · Expired when it starts or fills up.
- **Rating** shows "—" until a formula is defined. **Reliability** only records late drops (leaving within 24 h of start).
- Writing reviews isn't designed. Reviews are display-only, and Firestore rules block creating them.
- Chess and Billiards were added as sport chips in the existing style for HUDDL's players.
