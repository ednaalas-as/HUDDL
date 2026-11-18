# HUDDL — Codebase Guide

## 1. Folder map (actual line counts, 18 Nov 2026)

```
HUDDL/                         ← iOS app (31 Swift files, ~7,600 lines)
├─ App/
│  ├─ HUDDLApp.swift      (83)   app entry; configures Firebase first; RootView picks splash/auth/setup/main
│  ├─ Router.swift        (183)  typed routes, one NavigationPath per tab, full-screen flows
│  └─ AppData.swift       (74)   shared live listeners (swipes, applications, invites, blocks, likes…)
├─ DesignSystem/                 Figma components rebuilt in SwiftUI
│  ├─ Theme.swift         (130)  colours, gradients, Inter font registration
│  ├─ Components.swift    (627)  header, buttons, chips, segmented controls, avatars, venue cover, cards
│  ├─ Feedback.swift      (417)  toast, confirm dialog, loading screen, success screen, sheets, form fields
│  └─ NavigationBar.swift (105)  floating tab bar with notched shape and orange "+"
├─ Models/Models.swift    (427)  all Codable Firestore models
├─ Services/
│  ├─ FirebaseBootstrap.swift (93) emulator vs production config; geohash + distance maths
│  ├─ SessionStore.swift  (194)  auth state, sign up/in, password reset, profile, delete
│  ├─ GameService.swift   (222)  games, discover, swipes, apply/accept/decline, invites, results
│  ├─ SocialService.swift (272)  feed, likes, comments, players, blocks; ChatService; NotificationService
│  ├─ FunctionsClient.swift (45) calls Cloud Functions; maps errors to readable messages
│  ├─ StorageService.swift (39)  image/video upload
│  ├─ PushService.swift   (71)   FCM registration, notification taps, AppDelegate
│  └─ Validation.swift    (44)   form rules (the Figma error copy)
├─ Features/
│  ├─ Auth/          LaunchViews (splash, onboarding, welcome), AuthViews (sign up/in/forgot), ProfileSetupView
│  ├─ Main/          MainTabView (tabs + shared GameRow, PlayerLine, ScreenScaffold)
│  ├─ Huddle/        HuddleView (Discover deck, Interested/Not interested lists)
│  ├─ Game/          GameDetailsView, ApplyView
│  ├─ Host/          HostGameView (host/edit), HostManageViews (Applicants, Invite, Post result)
│  ├─ Social/        HomeView (feed, Share moments), PostViews (cards, post detail, report, viewer)
│  ├─ Chat/          ChatViews (chat list, thread, Notifications, Search)
│  ├─ Profile/       ProfileViews (my profile, player profile, invite-to-game sheet)
│  ├─ Settings/      SettingsViews (settings, edit profile, sports, password, blocked, help, support, terms, delete)
│  └─ Shared/        PickerSheets (photo source, camera, home area + location, sport chips, FlowLayout)
└─ Resources/       Inter fonts, Figma-exported art, app icon
HUDDLTests/ValidationTests.swift     4 unit tests
HUDDLUITests/HUDDLUITests.swift      13 end-to-end UI tests
firebase/
├─ firebase.json, .firebaserc, firestore.indexes.json, emulators.sh
├─ firestore.rules (162), storage.rules (29)
└─ functions/src/ index.ts (780) · seed.ts (~265) · smoke-test.ts (146, 33 checks)
run-sim.sh                          build + install + launch in the simulator
```

## 2. The ten files to study first

| File | Why it matters | Key places |
|---|---|---|
| `HUDDL/Services/FirebaseBootstrap.swift` | How the app chooses emulator or production | `configure()` line 16; emulator hookup 34–41; `geohash` 55; `coveringPrefixes` 81 |
| `HUDDL/Services/SessionStore.swift` | The whole sign-up / sign-in story | `signUp` 60 (transaction at 76), `signIn` 99, `sendPasswordReset` 125, `completeProfile` 153 |
| `HUDDL/App/Router.swift` | Navigation design | `enum Route` 4, `isAtRoot` 61, `RouteView` 138 |
| `HUDDL/App/AppData.swift` | Real-time shared state | `start(uid:)` 26, `relation(to:)` 64 |
| `HUDDL/Services/GameService.swift` | Every game operation from the app | `discover` 36, `swipe` 98, `apply` 134, `accept` 162 |
| `HUDDL/Features/Huddle/HuddleView.swift` | Swipe deck and lists | `DiscoverModel.load`, `decide`, `SwipeListView` |
| `HUDDL/Features/Game/GameDetailsView.swift` | One screen, many states | `bottomBar(_:)` chooses the buttons per relation |
| `firebase/functions/src/index.ts` | All trusted logic | `signInWithUsername` 113, `applyToGame` 145, `acceptApplication` 202, `respondInvite` 414, `createPost` 496, `runLifecycle` 740 |
| `firebase/firestore.rules` | Who can read and write what | `users` 14, `usernames` 36, `games` 52, collection groups 84–85 and 108, `chats` 111 |
| `firebase/functions/src/seed.ts` | How the 8 accounts and demo data are created | `upsertUser`, `main` |

## 3. Feature walkthrough (what happens, step by step)

Each entry covers: where to find it, what the user does, what's stored, which Firebase services are involved, and what's validated.

**1. Splash and onboarding** (`LaunchViews.swift`)
- Splash shows the favicon and wordmark for about 1.4 s while Firebase Auth restores the session.
- Onboarding is a 3-page `TabView`, with SKIP (jumps to page 3), the arrow button, and Get Started → Sign up.
- `huddl.onboardingSeen` is stored on the device, so returning users land on Sign in.
- No Firebase involved.

**2. Registration and authentication** (`AuthViews.swift`, `SessionStore.swift`, `Validation.swift`)
- Sign up checks locally first: username (no spaces, 3–30 characters from `a-z 0-9 . _ -`), valid email, password of 8+ characters, matching confirmation.
- Then `signUp`:
  1. a quick "is the name free?" read;
  2. `Auth.createUser` with email and password;
  3. a **Firestore transaction** creates `usernames/{name}` plus `users/{uid}`;
  4. if the name was taken in the meantime, the new Auth account is deleted again.
- Sign in accepts a **username** (via the Cloud Function) or an email.
- "Remember me" off means sign-out at the next launch.
- Services: Auth, Firestore, Functions.

**3. Profile setup** (`ProfileSetupView.swift`)
- Photo (optional, uploaded to Storage `avatars/{uid}`), sports chips, skill level, home area (list or GPS).
- `completeProfile` writes these and sets `profileComplete = true`. The root view then switches to Welcome.
- At least one sport is required unless the user taps "Skip for now".

**4. Home feed** (`HomeView.swift`, `PostViews.swift`)
- A live query of `posts` where `audience == everyone` OR `visibleTo` contains me, newest first, 50 at a time.
- Hidden posts and blocked users are filtered out on the device.
- Card types:
  - match result card;
  - photo/video moments;
  - "is hosting a game" with VIEW;
  - "X and N others joined" with JOIN TOO.
- Actions:
  - **like:** optimistic heart, then `likes/{uid}`; a trigger updates the count;
  - **comment:** opens Post detail; an empty comment shows "Type a message first";
  - **repost:** a Cloud Function, once per user;
  - **share sheet**, and the **••• menu** (Report / Hide with Undo / Copy link).
- Photos open a full-screen viewer.

**5. Search** (`ChatViews.swift`, `SearchView`)
- One field; results update 300 ms after typing stops.
- Games are filtered by title, venue, sport or host. Players are filtered by name or username.
- The last 8 searches are stored on the device.
- No results → HOST A GAME button.
- *Implementation note:* it filters up to 200 documents on the device. Fine for a campus-sized community; not for millions of users (see Limitations).

**6. Game discovery** (`HuddleView.swift` → `GameService.discover`)
- Builds the 4-character geohash cells around the home area. Querying each cell for open, public games, then filtering by exact distance ≤ 10 km and future start time, gives the 10 km radius.
- The deck removes games you host, joined, already swiped, or that are hosted by blocked users.
- Swipe right or ♥ writes `swipes/{gameId} = interested`. Swipe left or ✕ writes `notInterested`.
- A toast confirms each swipe. The empty deck offers "Change home area" and "Host a game".

**7. Interested / Not interested** (`SwipeListView` in `HuddleView.swift`)
- Active vs Expired is decided on the device: a game is expired once it has started, ended, been cancelled, or filled up without you.
- Sort options: Soonest, Nearest, Newest, Most spots left.
- Row actions: APPLY, APPLIED (tap to withdraw, with confirmation), RESPOND (invite), VIEW, INTERESTED (move back), REMOVE (expired items).

**8. Game details** (`GameDetailsView.swift`)
- A live listener on `games/{id}`.
- The cover is always the venue photo or the neutral court placeholder, never a person.
- Rosters are grouped by team, every row opens that player's profile, and you're marked "(You)".
- The bottom bar depends on your relation to the game:

| Relation | Bottom bar |
|---|---|
| Not involved | APPLY TO JOIN |
| Pending | WITHDRAW |
| Invited | ACCEPT / DECLINE |
| Joined | LEAVE GAME + TEAM CHAT |
| Host | INVITE PLAYERS + TEAM CHAT; ••• menu (Edit / Invite / Share / Cancel) |
| Ended | FIND SIMILAR + SHARE MOMENTS, plus a RESULT & MOMENTS card |

**9. Applying and joining** (`ApplyView.swift` → `applyToGame`)
- Choose a team (a full team shows a toast instead), Solo or With my group, an optional note, and the **required commitment checkbox**.
- The server re-checks everything in a transaction.
- Result: `applications/{me}` with status pending, plus a notification to the host. The app shows the Application sent success screen.

**10. Hosting** (`HostGameView.swift`)
- Fields: sport, title (required), venue (required, from the venues collection), date and time (must be in the future), format chips or Custom (stepper capped at 6, always 2 teams), play type, invite-only.
- The Fixed teams and No substitutes toggles are locked; tapping them shows the "always on" toast.
- Posting writes `games/{id}` directly. The rules enforce the shape (see the Database Guide).
- The `onGameCreated` trigger then creates the team chat and the hosting card, and increments `stats.hosted`.
- Edit uses the `editGame` function. The format is locked once others have joined.

**11. Managing applicants** (`HostManageViews.swift`, `ApplicantsView`)
- Pending / Accepted / Declined tabs, updated live.
- **ACCEPT:** a confirmation (with special copy when it fills the last spot), then `acceptApplication`.
- **DECLINE:** a sheet with an optional *private* reason, then `declineApplication`.
- **NO ROOM:** when the group is bigger than the open spots.

**12. Invitations** (`InvitePlayersView`, `InviteToGameSheet`, `NotificationsView`)
- The host invites from the game or from a player's profile; only games with open spots are offered.
- The server checks the invitee's "Who can invite me" setting, blocks, and duplicate invites.
- The invitee accepts or declines from Notifications or Game Details. Accepting joins the team atomically, and the app shows "You're on Team X!".

**13. Team management**
- Teams A and B are arrays inside the game document; capacity comes from `format.playersPerTeam`.
- `recompute()` (`index.ts:62`) recalculates `memberIds`, `spotsLeft` and open/full status after every change.
- Leaving before the start reopens the spot. Rosters lock once the game starts (enforced in every function).

**14. Chat** (`ChatViews.swift`)
- The list has All / Game chats / Direct tabs, unread badges, and search.
- The thread listens to `messages`. Sending shows a "Sending…" bubble, and a failed send shows "Not sent · Tap to retry".
- Photos are uploaded to Storage `chats/{uid}`. Ended game chats show "Game ended · chat is read-only", and the rules enforce it.
- DMs are created by `openDirectChat`, which refuses if either person blocked the other.

**15. Player profiles** (`ProfileViews.swift`)
- Stats (games, wins, rating "—", hosted), sports chips, Matches / Hosted / Reviews tabs.
- Another player's profile adds INVITE TO GAME, MESSAGE, and a ••• menu (Share / Report / Block).

**16. Blocking and reporting**
- Blocking writes `users/{me}/blocked/{them}`. The `onBlockWritten` trigger adds you to *their* private `blockedBy` list.
- Both sides then hide each other's games, posts, DMs and invites. The blocked person isn't notified.
- Reports go to `reports` and can't be read back.

**17. Notifications** (`NotificationsView`)
- Live list with context actions: ACCEPT/DECLINE (invite), REVIEW (applied), SHARE (game ended).
- Tapping a notification opens the related game or post. "Clear all" keeps pending invites.

**18. Profile editing** (`EditProfileView`, `SportsSkillView`, `PasswordSecurityView`)
- Name, photo, home area, sports and skill.
- Password changes re-authenticate first; the new password needs 8+ characters including a number.

**19. Settings** (`SettingsView`)
- Four notification toggles (saved instantly), Who can invite me, Blocked players, Help center articles, Contact support (validated, with an optional screenshot), Terms & privacy (placeholder text), Log out (with confirmation), Delete account (type DELETE, then confirm, then the `deleteAccount` cascade).

**20. Post-game** (`PostResultView`, `ComposeMomentsView`)
- **Post result** (host only): winner, set scores (empty sets are rejected), photos, caption, then a confirmation. The `postResult` function updates stats, posts to the feed, notifies players, and makes the chat read-only.
- **Share moments:** media, caption, tag players from that game only, include-result toggle, audience. Then `createPost`.

**21. Results and reviews**
- Results: implemented as above.
- Reviews: display and "Helpful" voting only. There's no way to write a review (by design for now).

## 4. Key algorithms and techniques (explained simply)

### 4.1 Username sign-in without exposing emails
Firebase Auth signs in by **email**, but HUDDL users sign in by **username**. A naive solution stores the email next to the username, but then anyone could look up anyone's email. Instead:
```
App → callable signInWithUsername(username, password)
Server:
  uid   = usernames/{username}.uid             // no email stored there
  email = AdminAuth.getUser(uid).email          // only the server can see emails
  verify password with Auth REST API (signInWithPassword)
  if ok → return createCustomToken(uid)         // a one-time login ticket
App → Auth.signIn(withCustomToken: token)       // now signed in as that user
```
- Wrong password and unknown username both return the same message: "Wrong username or password".
- Code: `index.ts:113`, `SessionStore.signIn` line 99.

### 4.2 Username uniqueness
1. The client reads `usernames/{name}` for an early "taken" message.
2. The real guarantee is a **transaction**: if `usernames/{name}` exists, abort; otherwise create it **and** `users/{uid}` together.
3. Security rules also forbid overwriting an existing username document, because `update` is denied.
4. If the transaction fails, the just-created Auth account is deleted, so the user can try another name.

### 4.3 Capacity-safe accepting (no overbooking)
```
transaction:
  game = read games/{id}
  require caller == host, game not started/cancelled
  app  = read applications/{applicant}; require status pending/noRoom
  open = team.capacity − team.members.count
  if app.size (1 + group) > open: mark noRoom; stop
  team.members += applicant (+ group)
  write recompute(game)  → spotsLeft, memberIds, status (full when 0)
  mark application accepted
after: sync team chat, notify player(s), "joined" feed card;
       if last spot filled → decline remaining pending applicants with "game is full"
```
- Firestore transactions retry automatically if two hosts' devices race, so two accepts can't both take the last spot.
- The app can't change `games` directly at all.

### 4.4 Duplicate-submission prevention
- Applications use the **applicant's uid as the document ID**, so one person can only have one application per game, and the server refuses a second pending one.
- Invites use the invitee's uid; reposts use `reposts/{uid}`; likes use `likes/{uid}`. A second like is the same document, not a new one.
- Buttons show a loading state while a request runs (`isLoading`, `busy`), so they can't be double-tapped.

### 4.5 Like counter
- Tapping ♥ updates the screen immediately (optimistic), then writes `likes/{uid}`.
- The trigger `onLikeWritten` changes `likeCount` by ±1 inside a transaction that **never goes below 0**. A real "-1 likes" bug was found and fixed this way.
- The heart state comes from a collection-group listener: "my likes".

### 4.6 Geohash radius search
- A geohash turns latitude/longitude into a string; nearby places share prefixes.
- A 4-character cell is about 39 × 19 km. Querying the home cell **and its 8 neighbours**, then filtering by exact great-circle distance (the haversine formula) ≤ 10 km, finds every game in the radius.
- Code: `FirebaseBootstrap.swift`, `Geo`.

### 4.7 Private, two-way blocking
- You write `users/{me}/blocked/{them}`. The server mirrors it into `users/{them}/private/blockedBy`, which only they can read and nobody can write from the app.
- Each client hides both "people I blocked" and "people who blocked me", and the server refuses DMs and invites across a block.

### 4.8 Real-time updates
- Firestore snapshot listeners push changes over a persistent connection. The UI updates when data changes, with no polling.
- Listeners are removed in `onDisappear` / `stop()` to avoid leaks and extra reads.

### 4.9 Offline behaviour
- Production mode turns on Firestore's **persistent offline cache**: reads come from the cache, and writes are queued and sent later.
- Emulator mode uses an in-memory cache, so test data never goes stale.
- Network errors become "You're offline. Check your connection and try again." (`AppError.message`).
- Cloud Function calls (apply, accept…) **need a connection**.
