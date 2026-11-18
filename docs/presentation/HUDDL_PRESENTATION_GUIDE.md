# HUDDL — Presentation & Live Demo Guide

> Passwords are **not** in this file. Keep `HUDDL_ACCOUNTS_PRIVATE.md` open on your laptop only, **never on the projector**. Use your Mac's display arrangement or a phone to read passwords.

## 0. Setup (do this 30 minutes before)

1. Open Terminal and start the backend. Leave it running:
   ```bash
   ~/Desktop/HUDDL/firebase/emulators.sh
   ```
   Wait for "All emulators ready".
2. In a second terminal, reset the demo data (passwords stay the same):
   ```bash
   npm --prefix ~/Desktop/HUDDL/firebase/functions run seed
   ```
3. Build and launch the app on the **iPhone 17 Pro** simulator:
   ```bash
   ~/Desktop/HUDDL/run-sim.sh
   ```
4. **To show onboarding from the start**, uninstall the app first, then run `run-sim.sh` again:
   ```bash
   xcrun simctl uninstall booted com.huddl.app
   ```
5. Optional, and impressive: open a **second simulator** (Xcode → Window → Devices; boot "iPhone 17") so you can show two users at once. Install with:
   ```bash
   xcrun simctl install "iPhone 17" ~/Desktop/HUDDL/build/Build/Products/Debug-iphonesimulator/HUDDL.app
   ```
6. Open http://127.0.0.1:4000 (Emulator UI) in a browser tab to show the live database when asked.
7. Close notifications, set the simulator to 100% zoom, and turn on Do Not Disturb.

## 1. Who to sign in as (demo roles)

| Username | Use in demo as | Why |
|---|---|---|
| `thessasurell` | **The applicant** | Isn't on most games, so Discover and Apply work cleanly |
| `ednaalas-as` | **The host and main user** | Hosts *Beach Volley Sunday* (2 pending applicants), has a personal invite from Bea, a DM, an ended game with a result, and a "share moments" notification |
| `beaannebalmes` | Second user for chat | DM partner; hosts *Saturday 6v6 Open* |
| `kyleabandia` | Block/report target | Hosts *Badminton Smash Session* (1v1, 1 spot left) |

## 2. Demo sequence (about 12 minutes)

| Step | Account | Do | What happens | Say to the panel | Evidence it works |
|---|---|---|---|---|---|
| 1 Launch | — | Run the app | Splash (logo + "Match Up. Match On."), then onboarding | "Native SwiftUI app; while the splash shows, Firebase Auth restores the session." | Smooth launch, Figma visuals |
| 2 Onboarding | — | Swipe pages, SKIP, **Get Started** | Dark onboarding, then Sign Up | "Three onboarding screens from our Figma file." | Page dots, SKIP jumps to page 3 |
| 3 Validation | — | On Sign Up tap **SIGN UP** empty, then type `edna alas-as!` | "Fill in all fields…", "Spaces aren't allowed…" | "Validation runs on the device first, and the server checks again." | Red error text |
| 4 Sign in | `thessasurell` | **Sign In** → username + password | Home feed | "You sign in with a **username**. Firebase normally needs an email, so a Cloud Function finds the email privately and returns a login token. Emails are never public." | Feed loads |
| 5 Feed | thessasurell | Scroll; tap ♥ on the Morning Rally post; tap 💬, type a comment, send | Heart fills, count rises; comment appears instantly | "Likes are their own documents, and a server trigger keeps the count. Comments arrive through a real-time listener." | Count +1, comment shown |
| 6 Discover | thessasurell | **HUDDLE** tab | Swipe card: venue cover, sport, host, roster | "Discover shows open games within 10 km of Lucena, using a geohash search. The cover is always the venue, never a person, as the design requires." | Card with "x of y spots filled" |
| 7 Swipe | thessasurell | Tap ♥ (or swipe right) | Toast "Added to Interested", next card | "Swiping right saves the game to my Interested list." | Toast; Interested tab count |
| 8 Game details | thessasurell | Search 🔍 "beach" → **Beach Volley Sunday** | Rosters Team A/B, open spots | "Every roster row opens that player's profile. Teams are fixed with no subs." | Roster list |
| 9 Apply | thessasurell | **APPLY TO JOIN** → Team A → SEND (without the checkbox) → tick the checkbox → SEND | Toast "Tick the commitment box…", then "Application sent · PENDING" | "The server re-checks everything in a transaction: commitment, capacity, duplicates." | Success screen |
| 10 Switch user | — | Profile → ⚙ → Log out → confirm; sign in **`ednaalas-as`** | Home, bell has a dot | "Each of our 8 players has a separate account." | — |
| 11 Host review | ednaalas-as | 🔔 → "Thessalonica… applied" → **REVIEW** | Applicants: Thessalonica, Roselle, Jhon | "Only the host can read these applications; the security rules enforce that." | Pending · 3 |
| 12 Accept | ednaalas-as | **ACCEPT** on Thessalonica → confirm | Dialog → moves to Accepted | "Accepting is a server transaction, so two accepts can't overbook the last spot. She's added to the team chat and notified." | Counts update live |
| 13 Updated roster | ednaalas-as | Back → My game | Team A now Edna + Thessalonica, "HOSTING · 1 SPOT LEFT" | "The screen updated by itself through a Firestore listener." | Roster changed |
| 14 Decline | ednaalas-as | Applicants → **DECLINE** Jhon → "Skill level doesn't match" | "They'll get a friendly notification" | "The reason stays private to the host." | Declined tab |
| 15 Invite | ednaalas-as | 🔔 → Bea's invite → **ACCEPT** → JOIN TEAM B | "You're on Team B!" → OPEN TEAM CHAT | "Personal invites respect each user's 'Who can invite me' setting and blocks." | Success screen, chat opens |
| 16 Chat | ednaalas-as | Type a message → send | Bubble appears | "Only members can read a chat; ended games become read-only." | Message shown |
| 17 DM | ednaalas-as | **CHAT** → Direct → Bea → send "See you Saturday!" | Message appears | If you have the second simulator signed in as Bea, it appears there **instantly**. | Real-time |
| 18 Profiles | ednaalas-as | 🔍 "kyle" → Players → Kyle → ••• → **Block** → confirm → UNBLOCK | Blocked state, then normal | "Blocking is silent. The server writes a private list so content hides both ways." | State toggles |
| 19 Hosting | ednaalas-as | Orange **+** → POST GAME empty → add title, venue → POST GAME | "Add a game title…" → "Your game is live!" | "A new game appears in other players' Discover. A trigger creates its team chat and feed card." | Success → My game |
| 20 Settings | ednaalas-as | Profile → ⚙ → toggle *Game invites* off/on; Who can invite me | Toasts "Notifications off/on" | "Settings are saved straight to the user document." | Toggles persist |
| 21 Database | — | Browser → Emulator UI → Firestore → `games/beach-volley` | Shows teams, memberIds, spotsLeft | "This is the actual NoSQL document behind the screen." | Live data |
| 22 Real project | — | Browser → https://console.firebase.google.com/project/huddl-app-ph → Firestore → Rules | Our deployed rules in the Singapore database | "The production project exists and our security rules are live there. Full deployment only needs the Blaze plan." | Deployed rules |

**Optional extras if there's time:**
- `desireeferrer` → Profile → Saturday 6v6 Open → **LEAVE GAME**, to show the 24 h reliability warning.
- `ednaalas-as` → Profile → Matches → **Morning Rally 2v2** (ended), to show the RESULT & MOMENTS card and SHARE MOMENTS.

## 3. Showing all 8 accounts

The quickest proof: show the UI test result `test13_AllEightAccountsSignIn` (it signs every account in through the real UI), and the Emulator UI → **Authentication** tab listing all 8 `@huddl.test` users.

Differences to explain:

| Account | Sport (skill) | What's special in the data |
|---|---|---|
| ednaalas-as | Volleyball (intermediate) | Hosts Beach Volley Sunday (pending applicants) and Morning Rally 2v2 (ended, won); invited by Bea; DM with Bea |
| beaannebalmes | Volleyball (advanced) | Hosts Saturday 6v6 Open; on Team B of Beach Volley; won Morning Rally |
| roselledeleon | Badminton (intermediate) | Hosts Friday Night Doubles (with Kyle); pending applicant to Beach Volley |
| kyleabandia | Badminton (advanced) | Hosts Badminton Smash Session (1v1); on Friday Night Doubles |
| jhonlloydvalencia | Chess (advanced) | Hosts Rapid Chess Ladder (1v1); pending applicant to Beach Volley |
| thessasurell | Chess (intermediate) | Lost Morning Rally; free to apply anywhere (best applicant) |
| altheaaringo | Billiards (intermediate) | Hosts 8-Ball Night (2v2 group play); on Team B of Saturday 6v6 |
| desireeferrer | Billiards (beginner) | On Team A of Saturday 6v6; lost Morning Rally |

## 4. Fallback plan

| Problem | Quick fix | If that fails |
|---|---|---|
| App shows "You're offline" or keeps loading | Emulators stopped. Run `firebase/emulators.sh`, wait for "ready", pull to refresh | Show the screenshots in `docs/presentation/screenshots/` |
| Sign-in fails | Re-run the seed (passwords unchanged); check the private file | Sign in by **email** instead of username |
| Data looks messy after rehearsal | `npm --prefix firebase/functions run seed` | — |
| Build fails or the simulator is broken | Open `HUDDL.xcodeproj` in Xcode → Run | Use the screenshots + test report (13/13 UI, 33/33 backend) |
| Java/emulator won't start | `brew install openjdk@21`; check port 8080 is free (`lsof -i :8080`) | Present with screenshots and the Emulator UI explanation |
| No internet in the room | **Not needed.** Everything runs locally on the Mac | — |
| Asked about real pushes or Google login | Explain honestly: they need the production project (see Limitations) | — |
| Asked "why not live on Firebase?" | Show `huddl-app-ph` in the console; explain Blaze needs a payment method (Q21–21b in the Defense doc) | — |

## 5. Things NOT to promise in the demo
- Real push notifications, Google/Facebook login, real reset emails (production only).
- Media uploads (implemented, but not tested yet).
- Automatic game start/end (the scheduler doesn't run in the emulator).
