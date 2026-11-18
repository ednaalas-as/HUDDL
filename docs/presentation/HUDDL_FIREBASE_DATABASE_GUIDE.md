# HUDDL — Firebase & Database Guide

## 1. Which Firebase setup HUDDL uses (verified 18 Nov 2026)

| Item | Actual value | Evidence |
|---|---|---|
| Project ID | **`demo-huddl`**. The `demo-` prefix makes it an offline-only emulator project. | `firebase/.firebaserc`; `FirebaseBootstrap.swift` (`options.projectID = "demo-huddl"`) |
| Production project | **`huddl-app-ph`** on the free Spark plan. Firestore (`asia-southeast1`) with rules and indexes deployed; iOS app registered. **Not used by the app**: Functions and Storage need Blaze. | `firebase/.firebaserc` alias `production`; `firebase firestore:databases:get` → asia-southeast1 |
| App connects to | **Emulator Suite** on `127.0.0.1` (automatic when the plist is missing) | `FirebaseBootstrap.swift:16–41` |
| Firebase iOS SDK | **12.19.3** (Auth, Firestore, Storage, Messaging, Functions via SPM) | `project.pbxproj` → `minimumVersion = 12.19.3`; build log "Checking out 12.19.3" |
| Functions runtime | Node 20, `firebase-functions` v6 (v2 API), `firebase-admin` v13, TypeScript | `firebase/functions/package.json` |
| Functions region | `asia-southeast1` | `index.ts` → `setGlobalOptions({ region: "asia-southeast1" })`; `FunctionsClient.region` |

### Emulator services and ports (`firebase/firebase.json`)

| Service | Port | Used for |
|---|---|---|
| Authentication | 9099 | Accounts, sign-in, password reset |
| Cloud Firestore | 8080 | All app data |
| Cloud Storage | 9199 | Photos and videos |
| Cloud Functions | 5001 | Callable functions and triggers |
| Emulator UI | 4000 | Browse data in a web browser: http://127.0.0.1:4000 |

Not emulated:
- **Cloud Messaging** has no emulator. Pushes are skipped locally, but the in-app notification list works.
- **Scheduled functions** don't run, because there's no Pub/Sub emulator.

### How the app talks to the emulators

`FirebaseBootstrap.configure()`:
- `Auth.auth().useEmulator(withHost:"127.0.0.1", port: 9099)`
- Firestore `settings.host = "127.0.0.1:8080"`, `isSSLEnabled = false`, and an in-memory cache, so nothing stale survives between runs.
- `Storage.storage().useEmulator(… 9199)`
- `Functions.functions(region: "asia-southeast1").useEmulator(… 5001)`

The API key in that file is a **dummy, correctly-shaped placeholder**. It isn't a credential; Firebase's SDK only checks its format.

### Configuration per service

- **Authentication:** Email/Password. Sign-in by **username** goes through the `signInWithUsername` Cloud Function, which returns a custom token (§5). Google and Facebook are **not configured**; their buttons explain this.
- **Firestore:** default database. Composite indexes are in `firebase/firestore.indexes.json` (games by status/inviteOnly/geohash, games by host, posts by author, chats by member, and others).
- **Storage:** bucket `demo-huddl.appspot.com` locally. Owner-scoped folders (`storage.rules`).
- **Cloud Messaging:** `PushService.swift` requests permission, stores `fcmToken` on `users/{uid}`, and the server sends via `getMessaging().send`. Inactive in emulator mode.
- **Security Rules:** `firebase/firestore.rules` (162 lines) and `firebase/storage.rules`. They load into the emulator automatically and reload when the file changes.

## 2. Seeding, resetting and telling emulator data apart

| Task | Command |
|---|---|
| Start emulators | `./firebase/emulators.sh`. It builds the functions, uses Java 21, and imports/exports `firebase/.emulator-data` so data survives restarts. |
| Seed / reset demo data | `npm --prefix firebase/functions run seed` |
| Full wipe (including extra accounts) | Stop the emulators, delete `firebase/.emulator-data`, start them again, then seed |
| Backend smoke test | `npm --prefix firebase/functions test`. It **changes data**, so re-seed afterwards. |

What the seed (`firebase/functions/src/seed.ts`) does:
1. Creates or updates the **8 Auth accounts**. It reuses the passwords already in `seed-credentials.local.json`, so passwords stay stable.
2. Writes `usernames/{name}` and `users/{uid}`.
3. Writes 6 venues.
4. Deletes games, posts and chats left over from tests.
5. Writes 7 games, plus their team chats and hosting cards.
6. Writes 1 posted result, 2 feed posts, 1 like and 1 comment.
7. Writes 2 pending applications, 1 personal invite, 3 notifications for Edna, and 1 direct message.

**How to tell emulator data from production:**
- Emulator data lives in project `demo-huddl` and is visible only at http://127.0.0.1:4000.
- Emulator emails end in `@huddl.test`.
- Production data would only exist after a `GoogleService-Info.plist` is added and `firebase deploy` is run, which hasn't happened.

## 3. Firestore schema (only what's actually implemented)

Types: `string`, `number` (int/double), `bool`, `timestamp`, `map`, `array`. Swift models are in `HUDDL/Models/Models.swift`.

### 3.1 `users/{uid}`: player profile
- **Document ID:** the Firebase Auth uid.
- **Fields:**
  - `username` (string, lowercase)
  - `displayName` (string)
  - `photoURL` (string, optional)
  - `city` (string)
  - `homeArea` (map: `name`, `latitude`, `longitude`, `geohash`)
  - `sports` (array of maps `{sport, skill}`)
  - `stats` (map: `games`, `wins`, `hosted`, optional `rating`, `reliability`, `lateDrops`)
  - `settings` (map: `notifications{invites, applications, chat, reminders}`, `whoCanInvite`)
  - `profileComplete` (bool)
  - `fcmToken` (string, only when pushes are on)
  - `createdAt` (timestamp)
- **No email field.** Verified: none of the 8 documents contains an email.
- **Access:** any signed-in user can read; the owner can update everything except `username` and `stats`; nobody can delete from the app (account deletion uses a Cloud Function).
- **Example (Edna):** `username: "ednaalas-as"`, `displayName: "Edna Alas-as"`, `sports: [{volleyball, intermediate}]`, `stats: {games: 1, wins: 1, hosted: 2}`.

Subcollections:
- **`swipes/{gameId}`:** `decision` (interested | notInterested), `createdAt`, `removed`. Owner only. Feeds the Interested and Not interested lists.
- **`saved/{gameId}`:** the bookmark on Game Details. Owner only.
- **`hiddenPosts/{postId}`:** posts hidden from the feed. Owner only.
- **`blocked/{otherUid}`:** `name`, `username`, `photoURL`, `createdAt`. The owner can read and write; you can't block yourself.
- **`private/blockedBy`:** `uids[]` of people who blocked you. Written **only by the server** (`onBlockWritten`) and readable only by you. It lets the app hide content in both directions without anyone being able to query who blocked whom.

### 3.2 `usernames/{username}`: uniqueness and username sign-in
- **Fields:** `uid` only. Deliberately **no email**.
- **Access:**
  - `get` is public, so sign-up can check whether a name is free;
  - `list` is denied;
  - `create` only for yourself, with a name matching `^[a-z0-9._-]{3,30}$`;
  - never updated or deleted from the app.
- **Example:** `usernames/ednaalas-as → { uid: "Eozih8Zs…" }`.

### 3.3 `venues/{venueId}`
- **Fields:** `name`, `address`, `latitude`, `longitude`, `geohash`, `photoURL` (null), `sports[]`.
- **Access:** read-only for signed-in users; curated by the seed.
- **The 6 venues:** `inigos` (Iñigo's Sports Center), `tennisclub` (Lucena Tennis Club), `mseuf` (MSEUF Gymnasium), `pacificmall` (Pacific Mall Courts), `convention` (Quezon Convention Gym), `dalahican` (Dalahican Beach).

### 3.4 `games/{gameId}`: the heart of HUDDL
- **Fields:**
  - `host` (map PlayerRef `{id, name, username, photoURL}`)
  - `title`, `sport`
  - venue copy: `venueId`, `venueName`, `venueAddress`, `venuePhotoURL`, `latitude`, `longitude`, `geohash`
  - `startAt` (timestamp), `durationMin`, `notes`
  - `format` `{playersPerTeam 1–6, teams: 2, isCustom}`
  - `playType` (solo | group)
  - `rules` `{fixedTeams: true, noSubs: true}`
  - `inviteOnly`
  - `status` (open | full | started | ended | cancelled)
  - `teams` (array of `{id: "A"|"B", capacity, members[PlayerRef]}`)
  - `memberIds` (array of uids, for "games I'm in" queries)
  - `spotsLeft`, `createdAt`
  - optional `result` `{winnerTeamId, sets[{a,b}], postedBy, postedAt, flagDeadline, flagged}`
- **Access:**
  - any signed-in user can read;
  - **create** is allowed only when you're the host, fixed teams and no subs are true, there are exactly 2 teams, 1–6 players per team, status is `open`, you're the only member, and the title is 1–60 characters;
  - **update and delete are denied to the app.** All later changes go through Cloud Functions.
- **Seeded games:** `sat-6v6-open`, `friday-doubles`, `rapid-chess`, `eight-ball-night`, `beach-volley`, `badminton-clinic`, `morning-rally` (ended, with a result).
- **Example (`beach-volley`):** host Edna, 2v2 volleyball at Dalahican Beach. Team A = [Edna], Team B = [Bea], `spotsLeft: 2`, `status: open`.

Subcollections:
- **`applications/{applicantUid}`:**
  - Fields: `applicant` (PlayerRef), `applicantId`, `teamId`, `joinAs` (solo | group), `groupMembers[]`, `note`, `committed: true`, `status` (pending | accepted | declined | withdrawn | noRoom), `declineReason` (private), `via` (apply | invite), `createdAt`, `gameId`, `gameTitle`.
  - Access: the applicant and the game's host can read; **all writes go through Cloud Functions**.
  - Using the applicant's uid as the document ID means one application per person per game.
  - Example: `games/beach-volley/applications/{Jhon's uid}` → `teamId: "B"`, `note: "First time trying volleyball 🙂"`, `status: "pending"`.
- **`invites/{inviteeUid}`:**
  - Fields: `invitee`, `invitedBy`, `teamId`, `message`, `status` (sent | accepted | declined | cancelled), `createdAt`, `gameId`, `gameTitle`.
  - Access: invitee and host can read; server writes only.

### 3.5 `posts/{postId}`: feed
- **Fields:**
  - `author` (PlayerRef)
  - `type` (postGame | result | hosting | joined)
  - game copy: `gameId`, `gameTitle`, `venueName`, `gameDate`, `gameSport`, `spotsLeft`
  - `includeResult`, `result` (snapshot: sport, title, winner, `scoreLine`, `teamA[]`, `teamB[]`)
  - `media[]` `{url, type, duration}`, `caption`
  - `tagged[]` (players from that game only), `actors[]` (for "X and N others joined")
  - `audience` (everyone | gamePlayers | onlyMe), `visibleTo[]`
  - `likeCount`, `commentCount`, `repostCount`, `createdAt`
- **Access:** readable if `audience == "everyone"` or you're in `visibleTo`; **no app writes** (created by functions; counters maintained by triggers).
- **Seeded post IDs:** `result-morning-rally`, `moments-morning-rally`, and `hosting_<gameId>` for each open public game.

Subcollections:
- **`likes/{uid}`:** `uid`, `createdAt`. You can only create or delete your own. The `onLikeWritten` trigger updates `likeCount` and never lets it go below 0.
- **`comments/{id}`:** `author`, `text` (1–1000 characters), `createdAt`. Create as yourself; delete your own.
- **`reposts/{uid}`:** written by the `repost` function only, so you can repost a post only once.

### 3.6 `chats/{chatId}`: team chats and DMs
- **ID scheme:**
  - `game_<gameId>` for a team chat;
  - `dm_<uidA>_<uidB>` with the two uids sorted, so the same pair always gets the same chat.
- **Fields:** `type` (game | direct), `gameId`, `title`, `memberIds[]`, `members[]`, `readOnly`, `lastMessage`, `lastSenderId`, `updatedAt`, `unread` (map uid → count).
- **Access:**
  - only members can read;
  - members may change only `unread[their uid]`, and only to 0;
  - creation is server-only (`openDirectChat`, `syncGameChat`).
- **`messages/{id}`:** `senderId`, `senderName`, `text`, `imageURL`, `system`, `createdAt`.
  - Members can create messages as themselves; text is at most 2000 characters.
  - **Writes are refused when the chat is `readOnly`** (ended games).
  - System messages are server-only.

### 3.7 `notifications/{uid}/items/{id}`
- **Fields:** `type` (invite | inviteDeclined | accepted | declined | applied | spotLeft | expired | ended | cancelled | full | result | comment | like), `title`, `body`, `actor`, `gameId`, `postId`, `teamId`, `read`, `resolved`, `pref`, `createdAt`.
- **Access:** only you can read, mark read/resolved, or delete; creation is server-only.

### 3.8 Other collections
- **`reviews/{id}`:** `revieweeId`, `reviewer`, `gameId`, `tags[]`, `text`, `helpfulCount`, `createdAt`.
  - Read-only; **creating reviews is denied** because the flow isn't designed.
  - `helpful/{uid}`: a "Helpful" vote, at most one per person.
  - **0 documents seeded.**
- **`reports/{id}`:** `reporterId`, `targetType` (post | user), `targetId`, `reason`, `createdAt`. **Create-only.** Nobody can read reports through the app, which keeps them anonymous.
- **`supportTickets/{id}`:** `uid`, `topic`, `message` (at least 10 characters), `attachmentURL`, `createdAt`. Create-only.

## 4. Relationships (how it fits together)

```
users ─1───────*─ games (host.id)            users ─*────────*─ games (via teams[].members / memberIds)
games ─1───────*─ applications (doc id = applicant uid) ─*──1─ users
games ─1───────*─ invites (doc id = invitee uid)
games ─1───────1─ chats/game_<gameId> ─1──*─ messages
users ─*───────*─ chats/dm_<a>_<b>
games ─1───────*─ posts (gameId)  ─1──*─ likes / comments / reposts
users ─1───────*─ notifications/{uid}/items
users ─1───────*─ swipes, saved, hiddenPosts, blocked
usernames/{name} ─1──1─ users/{uid}
```

**Denormalization:**
- Many documents embed a small `PlayerRef` (`id`, `name`, `username`, `photoURL`), for example a game's host and roster members.
- Embedding means one read shows a whole roster, without fetching 12 user documents.
- The trade-off: if someone renames themselves, old copies keep the old name until updated. That's a standard NoSQL choice.

## 5. Why Firestore, and how it differs from SQL

- **Firebase does include its own databases:** Cloud Firestore (which HUDDL uses) and the older Realtime Database.
- **Firestore is NoSQL:** collections of JSON-like documents, no fixed schema, no SQL joins.
- **Relational SQL equivalent:** separate `users`, `games`, `teams`, `team_members` and `applications` tables, joined with foreign keys.
- **In Firestore:**
  - a game document *contains* its teams and members (embedding);
  - per-game data that grows (applications, invites) goes in **subcollections**;
  - you design around the queries the screens need, for example `memberIds array-contains me`.
- **Why Firestore for HUDDL:**
  1. real-time listeners, which chat, rosters and the feed need;
  2. offline caching built into the iOS SDK;
  3. security rules enforced on the server;
  4. transactions for capacity-safe accepts;
  5. it scales without managing servers;
  6. it was a stated requirement (Firebase only).
- **Why not Realtime Database:** Firestore has richer queries (compound filters, `array-contains`, collection groups), better structure for nested data, and the recommended iOS Codable support.

## 6. Security rules in plain language

| Rule | Why |
|---|---|
| Must be signed in to read almost anything | No anonymous scraping |
| You can only write documents that belong to you (`isMe(uid)`) | Users can't edit each other |
| Games can't be updated by the app at all | Rosters and capacity can't be faked; only server transactions change them |
| Usernames are claimed once, with no email inside | Uniqueness plus email privacy |
| Posts are filtered by `audience`/`visibleTo` *in the rules* | "Only me" posts are truly private (smoke-tested) |
| Chat and messages need `memberIds` membership; read-only chats refuse messages | DM privacy (smoke-tested) |
| Collection-group reads check a stored field equals your uid | Needed so "my applications/likes/invites" queries are allowed safely. Three real bugs were fixed here (see the Testing Report). |
| Reports and support tickets are write-only | Anonymity and staff-only access |

**Known weakness (disclosed):**
- `users/{uid}` is readable by any signed-in user, so the optional `fcmToken` field (device push token) is readable too.
- It isn't a password, but best practice is to move it to the private subcollection before production. Listed in `HUDDL_KNOWN_LIMITATIONS.md`.
