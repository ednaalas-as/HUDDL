# HUDDL — Panel Questions & Answers (45)

Format: **Q** → short spoken answer. ▸ marks extra technical detail and 📄 marks the file to cite.

---
## A. Project overview and objectives

**1. What is HUDDL in one sentence?**
A native iOS app that matches strangers for sports games: you swipe on games instead of people, apply to join, and play with fixed teams. Afterwards you share results and moments with the community.

**2. What problem does it solve?**
Finding people to play with at the right level, place and time is hard, and pickup games often fall apart when people don't show up. HUDDL makes joining explicit (apply, commitment checkbox, fixed teams) and puts discovery, chat and results in one place.

**3. Who are the target users?**
Recreational players in a local area. Our sample community is Lucena City, Quezon, with eight seeded players across volleyball, badminton, chess and billiards.

**4. What are the main features?**
Swipe discovery within 10 km, Interested/Not interested lists, applications with team selection, hosting with custom formats, applicant management, personal invites, team chats and DMs, a social feed, notifications, profiles, blocking/reporting, and post-game results and moments.

**5. What's the scope? What's out of scope?**
In scope: everything above, on iOS, with Firebase. Out of scope or not yet done: production deployment, Google/Facebook login, real push delivery, writing reviews, a reliability formula. See the Known Limitations doc.

---
## B. System architecture

**6. Describe the architecture.**
SwiftUI views on top, observable state stores in the middle, a service layer that talks to Firebase, and Cloud Functions for anything that must be trusted.
▸ `SessionStore` handles auth, `AppData` holds live per-user data, `Router` handles navigation. Services like `GameService` wrap Firestore and callable functions. Security rules guard every direct read and write.
📄 `docs/presentation/HUDDL_SYSTEM_ARCHITECTURE.md`, `HUDDL/App/*`, `HUDDL/Services/*`

**7. Is it MVVM?**
Mostly, in a lightweight SwiftUI style. Models are Codable structs, views are SwiftUI, and shared state lives in `@Observable` classes that act as view-models. Small screens keep state in `@State` and call services directly. We didn't add separate repository classes; the service enums play that role.

**8. Where does the business logic live?**
Validation for user experience runs in the app. The rules that matter for fairness and security (capacity, rosters, accepting, invites, results, account deletion) run in Cloud Functions, because the app can be modified by an attacker but the server can't.
📄 `firebase/functions/src/index.ts`

**9. Walk me through what happens when someone taps "Send application".**
The app checks the team, commitment and group size, then calls the `applyToGame` function. The function runs a Firestore transaction that re-checks the game is open, the team has room, there's no duplicate, and the commitment is true. It writes the application with the user's uid as its ID, then notifies the host. The app shows "Application sent".
📄 `ApplyView.swift` → `GameService.apply` (line 134) → `index.ts:145`

**10. How does navigation work?**
A `Router` object holds the selected tab and one navigation stack per tab, plus full-screen flows such as Host and Apply. Routes are a typed enum, so `.game(id)` always opens Game Details. The floating tab bar shows only on root screens.
📄 `HUDDL/App/Router.swift` (Route at line 4, isAtRoot at line 61)

---
## C. SwiftUI and native iOS

**11. Why SwiftUI?**
It's Apple's modern native UI framework: declarative, less code, live previews, and built-in accessibility and Dynamic Type. The design was made "iOS/SwiftUI style" on purpose, and the requirement was a genuinely native app, not a web wrapper.

**12. Why not React Native or Flutter?**
The project required native SwiftUI. Native also gives the best performance, the newest iOS APIs (`@Observable`, PhotosPicker, sheets with detents), and pixel-level control to match the Figma design.

**13. What's the minimum iOS version and why?**
iOS 17, which the project owner chose. It enables the `@Observable` macro and modern SwiftUI APIs while still covering most active iPhones.

**14. How did you reproduce the Figma design?**
We read the Figma file's exact values (colours, gradients, Inter font weights, radii, positions) and rebuilt each Figma component as a reusable SwiftUI view: the header, floating tab bar, chips, toast, confirm dialog and venue cover. Artwork was exported from Figma.
📄 `HUDDL/DesignSystem/*`

**15. How do you handle loading, errors and empty states?**
Each screen has explicit states: a `ProgressView` while loading, `ErrorStateView` with "Try again", `EmptyStateView` with a next action. Feedback follows the design patterns: a top toast for 2.8 s, a centered confirmation dialog for destructive actions, and full-screen loading and success screens.
📄 `HUDDL/DesignSystem/Feedback.swift`

**16. Is the app accessible?**
Partly verified. Main controls have accessibility labels, the Inter font scales with Dynamic Type, and toasts are announced to VoiceOver. A full VoiceOver and large-text audit hasn't been done; that's listed as future work.

---
## D. Firebase and Cloud Firestore

**17. Why Firebase?**
One platform gives us authentication, a real-time database, file storage, server functions, push notifications and security rules, with no servers to manage, and a local emulator for safe testing. It was also a project requirement.

**18. Does Firebase have its own database?**
Yes. Firebase offers two: Cloud Firestore and the older Realtime Database. HUDDL uses **Cloud Firestore**.

**19. Why Firestore instead of Realtime Database?**
Firestore has richer queries (compound filters, `array-contains`, collection-group queries), better structure for nested data, transactions, offline support, and Codable support in Swift. It's Google's recommended database for new apps.

**20. Is Firestore SQL or NoSQL?**
NoSQL. It stores documents (JSON-like maps) in collections. There are no tables, joins or fixed schema. We design documents around the screens' queries and sometimes copy small pieces of data (denormalization).

**21. Are you using real Firebase right now?**
For the demo, no, and I'll be clear about that. The app runs on the **Firebase Emulator Suite**, Google's official local version of Firebase, under project `demo-huddl`. We did create the real project, **`huddl-app-ph`**, with the Firestore database in Singapore and our security rules and indexes deployed. But HUDDL's Cloud Functions and photo Storage require Firebase's paid **Blaze** plan, which needs a payment method we don't have. The app switches automatically: with the project's `GoogleService-Info.plist` bundled, it uses production; without it, the emulators. So going live needs billing, not code changes.
📄 `HUDDL/Services/FirebaseBootstrap.swift:16`, `firebase/.firebaserc`

**21b. Why not just use the free plan?**
On Spark, Auth and Firestore are free, but Cloud Functions aren't available. Our fairness and security logic (accepting applicants without overbooking, invites, results, username sign-in that keeps emails private) runs in Cloud Functions on purpose, because code inside the app can be modified by an attacker. Moving it into the app to fit the free plan would weaken security, so we kept the right architecture and demo it locally.

**22. What do Cloud Functions do?**
Trusted operations the app can't be allowed to do itself, for example accepting an applicant, joining from an invite, posting results and deleting accounts. They also react to database changes: counting likes, creating team chats, sending notifications. And they run a scheduled job that starts and ends games.
📄 `firebase/functions/src/index.ts`

---
## E. Database structure and relationships

**23. What are your main collections?**
`users`, `usernames`, `venues`, `games` (with `applications` and `invites` subcollections), `posts` (with `likes`, `comments`, `reposts`), `chats` (with `messages`), `notifications/{uid}/items`, `reviews`, `reports`, `supportTickets`.
📄 `HUDDL_FIREBASE_DATABASE_GUIDE.md` §3

**24. How are users related to games?**
A game stores its host and its two teams. Each team is an array of small player references, plus a flat `memberIds` list. That lets us query "games I'm in" with one `array-contains` query, and show a full roster with one read.

**25. Why are applications a subcollection and not an array in the game?**
Applications grow over time and need their own security: only the applicant and the host may read them. A subcollection gives each application its own document and rules. Using the applicant's uid as the document ID also prevents duplicates.

**26. How do chats relate to games?**
Each game has exactly one team chat with ID `game_<gameId>`. DMs use `dm_<uidA>_<uidB>` with the uids sorted, so two people always get the same conversation. Messages are a subcollection.

**27. What is denormalization and why use it?**
Copying a few fields (name, username, photo) into other documents so a screen needs one read instead of many. The trade-off: renamed users keep the old name in old copies. That's normal in NoSQL design.

---
## F. Authentication and account security

**28. How are accounts authenticated?**
Firebase Authentication with email and password. Users type a **username**; a Cloud Function looks up that user's email on the server, verifies the password with Firebase Auth, and returns a custom sign-in token. The app then signs in with that token.
📄 `index.ts:113` (`signInWithUsername`), `SessionStore.swift:99`

**29. How do you ensure usernames are unique?**
A `usernames/{name}` document is created inside the same Firestore **transaction** as the user profile. If the name already exists, the transaction aborts and the new Auth account is deleted. Security rules also forbid overwriting a username document.
📄 `SessionStore.swift:60–95`, `firestore.rules:36`

**30. How are passwords protected?**
We never store passwords. Firebase Authentication stores salted, hashed passwords (Google uses a modified scrypt) and only ever compares hashes. Our Cloud Function passes the password straight to Firebase Auth's verification endpoint and never saves it. Our seed's *temporary* passwords exist only in a git-ignored local file.

**31. Why aren't emails stored in user profiles?**
Profiles are readable by other signed-in players, so storing emails there would leak them. Emails live only in Firebase Auth; the username record contains just the uid. Our backend test checks this.

**32. How do you prevent unauthorized access?**
Firestore Security Rules run on Google's servers, so they can't be bypassed by a modified app. Users can only write their own data. Games can't be modified by the app at all. Chats require membership, notifications are private, and posts respect their audience. We test this: 33 backend checks, including attempts to tamper with stats, rosters and other people's DMs.
📄 `firebase/firestore.rules`, `smoke-test.ts`

**33. What happens when you forget your password?**
Firebase sends a reset link. The app enforces a 60-second resend cooldown, and for privacy doesn't reveal whether the email exists. In the emulator, the link shows in the Emulator UI instead of a real inbox.

---
## G. Game discovery and matchmaking

**34. How do you find games within 10 km?**
We use **geohashes**: location strings where nearby places share prefixes. We query the user's 4-character geohash cell and its 8 neighbours for open public games, then filter by exact distance with the haversine formula.
📄 `GameService.discover` (line 36), `FirebaseBootstrap.swift` (`Geo`)

**35. How do you prevent users from joining a full game?**
Three layers:
1. The app disables full teams and shows a toast.
2. The `applyToGame` function rejects full teams.
3. When the host accepts, `acceptApplication` runs a **transaction** that re-reads the game and checks capacity, so even simultaneous accepts can't overbook. When the last spot fills, remaining applicants are told the game is full.
📄 `index.ts:145`, `index.ts:202`

**36. How do group applications work?**
The applicant picks group members. The server checks the game allows groups and the team has enough open spots for the whole group. On accept, all members are added together as one fixed team. If there isn't room, the application becomes "no room" instead of partially joining. The server rules are tested; the full group flow in the app isn't yet.

**37. How do you prevent duplicate requests?**
Unique document IDs: one application, invite, like or repost per user per item, keyed by uid. The server refuses a second pending application. Buttons show a loading state while a request runs, so they can't be double-submitted.

---
## H. Social feed and communication

**38. How do two users communicate in real time?**
Both apps listen to the same Firestore `messages` collection. When one sends, Firestore pushes the new document to every listener in about a second, with no polling. A trigger updates the chat preview and unread counts.
📄 `ChatService.send` (`SocialService.swift:219`), `onMessageCreated` (`index.ts:696`)

**39. How are images stored?**
Images are resized and compressed on the phone, uploaded to Cloud Storage under the user's own folder (for example `posts/{uid}/…`), and the download URL is saved in Firestore. Storage rules restrict uploads to your own folder and limit file size. This code exists but hasn't been exercised in a test yet.
📄 `StorageService.swift`, `storage.rules`

**40. How do notifications work?**
Every important event makes the server write a notification document for the recipient, which appears instantly in the in-app list. A trigger then sends a push through Firebase Cloud Messaging, if the user's settings allow it. Real pushes need the production project and an Apple push key, so on the emulator only the in-app list works.
📄 `notify()` (`index.ts:82`), `onNotificationCreated` (`index.ts:713`), `PushService.swift`

**41. How does blocking work, and is it really private?**
Blocking writes to my private block list. The server copies it into a private document only the other person's app can read, and no one can query it. Both apps then hide each other's games, posts, invites and DMs, and the server refuses DMs and invites across a block. The blocked person isn't notified.

**42. What happens without an internet connection?**
In production mode Firestore keeps an offline cache: you can see previously loaded data, and simple writes are queued until you're back online. Server actions like applying or accepting need a connection, and the app shows "You're offline. Check your connection and try again." Locally, everything runs on the Mac, so no internet is needed for the demo.

---
## I. Testing and quality assurance

**43. How did you test the application?**
Four layers:
1. **4 unit tests** for validation and distance maths.
2. **13 automated end-to-end UI tests** that drive the real app against the emulators: sign-up, sign-in, feed, swipe, apply, host, accept, invites, chat, block, settings, and all 8 accounts signing in.
3. **33 backend checks** that call the real functions and try forbidden actions.
4. Manual checks against Figma.

All pass in the latest runs. Testing found and fixed real bugs, including two launch crashes, the tab bar covering the Send button, and security-rule bugs that hid likes and pending statuses.
📄 `HUDDL_TESTING_REPORT.md`

**44. Do you have complete test coverage?**
No. We cover the core flows and the important security rules. Media upload, post-result and share-moments screens, the automatic game lifecycle, account deletion and real push or social login aren't tested yet. They're listed openly in the limitations document.

---
## J. Limitations, scalability and future work

**45. What are the current limitations?**
- Production is only partly deployed: `huddl-app-ph` has Firestore and rules, but Functions and Storage need the Blaze plan, so the demo runs on the emulator.
- Push, social login and real emails need production setup.
- Some features are implemented but not yet tested in the app.
- No reliability or rating formula; no review writing.
- The FCM token should move to a private document.

**46. How can it scale to more users?**
Firestore and Cloud Functions scale automatically, and queries are indexed. To grow further:
- move search to a dedicated index;
- paginate the feed and chat history;
- add App Check to block non-app clients;
- shard hot counters if posts get very popular;
- shorten scheduled-job windows by region.

**47. If you had more time, what would you add first?**
Deploy to a real Firebase project with push notifications; add UI tests for media and post-game flows; implement the reliability score and review writing once designed; then Google and Facebook sign-in.
