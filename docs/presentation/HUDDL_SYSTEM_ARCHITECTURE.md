# HUDDL — System Architecture

## 1. The big picture

```
┌────────────────────────── iPhone (SwiftUI app) ──────────────────────────┐
│  Views (Features/*)  ──reads──▶  @Observable stores (SessionStore,       │
│        │                         AppData, Router, ToastCenter,           │
│        │ user taps               DialogCenter) + per-screen @State       │
│        ▼                                                                 │
│  Service layer (Services/*): SessionStore, GameService, SocialService,   │
│  ChatService, NotificationService, StorageService, FunctionsClient       │
└───────┬──────────────┬───────────────┬─────────────────┬─────────────────┘
        │ Auth SDK     │ Firestore SDK │ Storage SDK     │ Functions SDK (HTTPS callable)
        ▼              ▼               ▼                 ▼
  Firebase Auth   Cloud Firestore   Cloud Storage    Cloud Functions (TypeScript)
                  (guarded by       (guarded by      - trusted writes (apply, accept…)
                  firestore.rules)  storage.rules)   - triggers (counters, chat, push)
                        ▲                            - scheduled lifecycle
                        └──────── Admin SDK writes ──┘        │
                                                              ▼
                                                   Firebase Cloud Messaging → APNs
```

Locally, all of the Firebase boxes are the **Emulator Suite** on `127.0.0.1`:
- Auth: port 9099
- Firestore: port 8080
- Storage: port 9199
- Functions: port 5001
- Emulator UI: port 4000

## 2. Architectural style

HUDDL uses a **lightweight MVVM / service-layer** design that fits SwiftUI:

| Role | In HUDDL | Example |
|---|---|---|
| **Model** | `Codable` structs mapped to Firestore documents | `Game`, `Post`, `AppUser` in `HUDDL/Models/Models.swift` |
| **View** | SwiftUI `View` structs, one file per feature area | `GameDetailsView` in `Features/Game/GameDetailsView.swift` |
| **State / view-model** | `@Observable` classes for shared state, plus `@State` for per-screen state. Two screens use small dedicated models (`DiscoverModel` in `HuddleView.swift`, `LocationFetcher`). | `SessionStore`, `AppData`, `Router` |
| **Service (data access)** | Stateless `enum` namespaces that wrap the Firebase SDK. They play the role of a repository layer, but **there are no separate "Repository" classes**. | `GameService.swift`, `SocialService.swift` |
| **Trusted logic** | Cloud Functions; the client can't bypass them | `firebase/functions/src/index.ts` |

**Why this style?** With SwiftUI and `@Observable`, separate ViewModel classes for every screen would mostly forward calls, so most screens keep state in `@State` and call services directly. The rules that must be trustworthy (capacity, rosters, notifications) aren't in the app at all; they live on the server. That separation is the important one.

## 3. App startup and authentication flow

1. **`HUDDLApp.init()`** (`HUDDL/App/HUDDLApp.swift`) calls `FirebaseBootstrap.configure()` *before* any store touches Firebase.
   - This ordering fixed a launch crash found during testing.
2. **`FirebaseBootstrap.configure()`** (`HUDDL/Services/FirebaseBootstrap.swift:16`):
   - If `GoogleService-Info.plist` is bundled, it uses the real project.
   - **Otherwise** it builds offline options for project `demo-huddl` and points Auth, Firestore, Storage and Functions at the emulators (`useEmulator…`, lines 34–41).
   - Today there's no plist, so the app **always uses the emulators**.
3. **`RootView`** shows the splash, then `session.start()` attaches a Firebase Auth state listener (`SessionStore.swift:28`).
4. **`SessionStore.handleAuthChange`** (`SessionStore.swift:35`) listens to `users/{uid}` and sets `phase`:
   - `.signedOut` → `AuthFlowView` (onboarding / sign up / sign in / forgot password)
   - `.needsProfile` → `ProfileSetupView`
   - `.signedIn` → `WelcomeView` once after setup, then `MainTabView`
5. Sessions persist automatically, because Firebase Auth keeps the token in the iOS Keychain. "Remember me" off signs the user out at the next launch.

## 4. Navigation architecture

- **`Router`** (`HUDDL/App/Router.swift`) is an `@Observable` object with:
  - the selected tab (`home / huddle / chat / profile`);
  - **one `NavigationPath` per tab**, so each tab remembers its own back-stack;
  - `cover`: the full-screen flows (Host a game, Edit game, Share moments, Apply);
  - `huddleSegment`: Discover / Interested / Not interested.
- **`enum Route`** (`Router.swift:4`) lists every pushable screen, using typed IDs, for example `.game(id)`, `.player(uid)`, `.chat(id)`. **`RouteView`** (`Router.swift:138`) maps each route to its view.
- **States are not routes.** Loading, error, saved and empty are view state inside one screen, as the Figma file's state frames imply.
- **`MainTabView`** (`Features/Main/MainTabView.swift`) draws the custom floating tab bar with the orange "+" (that button is an *action* that opens Host a game, not a tab).
  - The bar is shown **only on a tab's root screen** (`Router.isAtRoot`, `Router.swift:61`). Pushed screens use their own bottom bars.
  - Hiding it fixed a real bug where the tab bar covered the chat Send button.
- Push notifications call `router.open(gameId:postId:)` to deep-link into the matching content.

## 5. Data flow (actual)

### Read path (real-time)
```
Firestore document changes
  → snapshot listener in a Service (e.g. GameService.listen, SocialService.listenFeed)
  → callback updates @State / AppData property on the main actor
  → SwiftUI re-renders the views that read it
```
Example: Game Details calls `GameService.listen(gameId)`. When the host accepts someone, the Cloud Function updates `games/{id}`, the listener fires, and the roster on screen updates by itself. Nobody has to refresh.

### Write path, simple owner data (direct Firestore write, checked by rules)
```
Tap ♥ → ActionBar.toggleLike() → optimistic UI → SocialService.setLike()
  → Firestore create posts/{p}/likes/{uid}  (rules: only your own uid)
  → trigger onLikeWritten updates likeCount → feed listener refreshes count
```

### Write path, trusted operations (Cloud Function)
```
Tap SEND APPLICATION → ApplyView.submit() validates locally
  → GameService.apply() → FunctionsClient.call("applyToGame")
  → Cloud Function runs a Firestore TRANSACTION (capacity, duplicates, commitment)
  → writes games/{id}/applications/{uid} + notifications/{host}/items/{id}
  → app shows "Application sent"; host's Notifications list updates in real time
```

## 6. Shared live data: `AppData`

`HUDDL/App/AppData.swift` starts the per-user listeners once after sign-in (`start(uid:)`, line 26). Many screens need the same facts at once, for example "Have I applied to this game?" for the PENDING chips on any list:

| Property | Source |
|---|---|
| `swipes` | `users/{uid}/swipes` |
| `applications` | collection-group `applications` where `applicantId == me` |
| `invites` | collection-group `invites` where `invitee.id == me && status == sent` |
| `blocked` / `blockedBy` | `users/{uid}/blocked` and the private `users/{uid}/private/blockedBy` |
| `hiddenPosts`, `likes` | `users/{uid}/hiddenPosts`, collection-group `likes` where `uid == me` |
| `notifications`, `threads` | `notifications/{uid}/items`, `chats where memberIds contains me` |

`relation(to:uid:)` (line 64) turns these into one of host / joined / pending / invited / declined / none. Cards and buttons use that value to decide what to show.

## 7. Cloud Functions (server)

File: `firebase/functions/src/index.ts`. Region: `asia-southeast1`. All functions are firebase-functions v2.

| Kind | Functions | Purpose |
|---|---|---|
| Callable (the app calls these) | `signInWithUsername`, `applyToGame`, `withdrawApplication`, `acceptApplication`, `declineApplication`, `leaveGame`, `editGame`, `cancelGame`, `invitePlayer`, `cancelInvite`, `respondInvite`, `postResult`, `createPost`, `repost`, `openDirectChat`, `deleteAccount` | Anything that changes rosters, other people's data, or needs secret checks |
| Firestore triggers | `onGameCreated`, `onGameUpdated`, `onLikeWritten`, `onCommentCreated`, `onCommentDeleted`, `onHelpfulCreated`, `onBlockWritten`, `onMessageCreated`, `onNotificationCreated` | Counters, team chats, activity cards, the private blocked-by list, chat previews and unread counts, sending pushes |
| Scheduled | `gameLifecycle` (every 10 min) → `runLifecycle` | Start, lock and end games; Expired list; read-only chats; "share your moments" prompts |
| Dev only | `devRunLifecycle` | Runs the lifecycle on demand, only in the emulator |

Note: in the local emulator the scheduler **doesn't run**, because the Pub/Sub emulator isn't started. The emulator log reports `gameLifecycle` as "ignored". Use `devRunLifecycle` to trigger it manually.

## 8. Media storage

`HUDDL/Services/StorageService.swift`:
- Photos are resized to 1600 px or less (800 px for avatars), converted to JPEG at quality 0.82, then uploaded to `avatars/{uid}/…`, `posts/{uid}/…`, `chats/{uid}/…` or `support/{uid}/…`.
- The download URL is stored in Firestore.
- `firebase/storage.rules` only lets you write inside your own `{uid}` folder:
  - images must be under 10 MB;
  - videos (posts only) must be under 100 MB.

## 9. Push notification architecture

```
Server code calls notify(uid, …)  →  writes notifications/{uid}/items/{id}   (in-app list, real time)
                                   →  trigger onNotificationCreated → sendPush()
                                       → checks user's settings.notifications.<pref>
                                       → Firebase Cloud Messaging → APNs → device banner
Tap banner → PushService.didReceive → Router.open(gameId:postId:)
```
- `HUDDL/Services/PushService.swift` registers for remote notifications and stores the FCM token on the user document.
- **In emulator mode, real pushes are skipped** (`isEnabled` is false). The in-app Notifications list works fully.
- Real pushes need the production project plus an APNs key. **Not verified.**

## 10. Security layers (defense in depth)

1. **Client validation** (`Services/Validation.swift`) gives fast, friendly error messages.
2. **Firestore and Storage Security Rules** (`firebase/firestore.rules`, `firebase/storage.rules`) are enforced by Google's servers, not the app, so a modified app can't bypass them.
3. **Cloud Functions** use transactions for anything multi-party (capacity, rosters, accept/decline, invites, results, account deletion).
4. **Privacy by structure:**
   - Emails live only in Firebase Auth.
   - Decline reasons are stored where only the host can read them.
   - Reports can't be read by anyone through the app.
   - Blocks are mirrored into a private document that only the blocked person's own client can read.
