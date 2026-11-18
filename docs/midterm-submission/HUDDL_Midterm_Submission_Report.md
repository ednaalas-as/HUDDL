# HUDDL — Midterm Submission (full written content)

Student: Edna Alas-as · Manuel S. Enverga University Foundation · Course: [COURSE] · Instructor: [INSTRUCTOR]


## 1. Application Overview


### What HUDDL is

HUDDL is a native iOS app for finding people to play sports with. A player who needs an opponent or teammates posts a game, and players nearby can find it and ask to join. The main idea is borrowed from dating apps, except that you swipe on **games**, not people: swipe right if you are interested, swipe left if you are not.

The tagline from my design is *“Match Up. Match On.”* Besides matchmaking, HUDDL has a small community side. After a game, players can post the result and photos, and the Home feed shows who is hosting or joining games nearby.


### The problem it addresses

Pickup games are usually organized through group chats and word of mouth. It is hard to find people at your level who are free at the same time, and games often fall apart because someone backs out at the last minute. HUDDL tries to fix both parts: discovery (games within 10 km of your area) and reliability (you must apply, tick a commitment box, and teams are fixed with no substitutes).


### Purpose and objectives

- Help players discover open games near their home area and save the ones they like.
- Let hosts create games with fixed teams and decide who joins.
- Keep games fair: capacity checks happen on the server, so a team cannot be overbooked.
- Give each game a team chat and let players message each other directly.
- Build a community through results, photos, likes and comments.
- Protect privacy: emails are never shown, blocking is silent and reports are anonymous.


### Target users

Recreational players and students who want to play more often but do not always have a complete group. The sample community is in Lucena City, Quezon. The project uses eight test players, each with their own account: two each for volleyball, badminton, chess and billiards.


### How it works, from a user's point of view

A new user signs up with a username, email and password, then picks the sports they play, their skill level and their home area. The HUDDLE tab shows one game card at a time from within 10 km. Tapping the heart saves the game to the Interested list, where the user can apply by choosing a team, adding a note to the host and confirming they can commit.

The host gets a notification, opens the Applicants screen and accepts or declines. Once accepted, the player is added to the roster and to the game's team chat. Hosts can also invite players directly from their profiles. After the game, the host posts the score, and players can share photos and moments that appear on the Home feed.


### Main features

| Category | What the user can do | Status |
|---|---|---|
| Registration and sign-in | Sign up with validation, sign in with a username, reset a password, set up a profile | Completed |
| Home feed and social | See results and community activity; like, comment, repost, share, hide or report posts | Completed (some actions not yet tested) |
| Discover and search | Swipe on nearby games; Interested / Not interested lists; search games and players | Completed |
| Game details and joining | View rosters and rules; apply as solo or as a group; withdraw; leave a game | Completed (group apply not yet tested in the app) |
| Hosting | Create games with 1v1–6v6 or custom formats; edit, cancel, invite players | Completed (edit save, cancel and invite UI not yet tested) |
| Managing applicants | Accept or decline (with a private reason); last-spot handling | Completed |
| Messaging | Team chat per game, direct messages, photo messages, read-only chats after a game | Completed (photo messages not yet tested) |
| Notifications | Invites, applications, acceptances and game-ended prompts with quick actions | In-app list completed; push notifications partial |
| Profiles and safety | My profile, other players' profiles, block/unblock, report | Completed |
| Settings and account | Edit profile, sports, password, notification toggles, privacy, help, support, delete account | Implemented; several screens not yet tested |
| Post-game | Post a result, share photos and moments | Implemented, not yet tested in the app |
| Social login | Continue with Google / Facebook | Planned (buttons only) |


### Technologies and tools

| Area | Used in HUDDL |
|---|---|
| App | Swift, SwiftUI, iOS 17+, Xcode 26.0.1 |
| Backend | Firebase Authentication, Cloud Firestore, Cloud Storage, Cloud Functions (TypeScript), Firebase Cloud Messaging, Security Rules |
| Firebase iOS SDK | 12.19.3 through Swift Package Manager |
| Local backend | Firebase Emulator Suite (project `demo-huddl`) |
| Cloud project | `huddl-app-ph` on the free Spark plan (Firestore in Singapore with rules deployed, Authentication enabled) |
| Design | Figma |
| Testing | XCTest (unit), XCUITest (end-to-end UI), a Node.js backend smoke test |
| Version control | Git and GitHub |
| Development help | An AI coding assistant (Claude Code), used under my direction |

> **Where the app runs right now.** HUDDL runs on the Firebase Emulator Suite, which is Google's official local version of Firebase. The real project `huddl-app-ph` exists, and its database and security rules are deployed. Running the whole app in the cloud needs Firebase's paid Blaze plan, because HUDDL's Cloud Functions and photo storage are not available on the free plan. I don't have a payment method for it yet.


## 2. Figma Prototype

**HUDDL prototype (Figma):** [https://www.figma.com/design/kqWMa2AGXpp267HtbmbXY8/HUDDL](https://www.figma.com/design/kqWMa2AGXpp267HtbmbXY8/HUDDL)  
**Clickable prototype, starting at the Splash screen:** [https://www.figma.com/proto/kqWMa2AGXpp267HtbmbXY8/HUDDL?node-id=2-2](https://www.figma.com/proto/kqWMa2AGXpp267HtbmbXY8/HUDDL?node-id=2-2)

This is my original HUDDL design file in the ENVERGA EDUCATION team. It is the design the SwiftUI app was built from. The prototype starts at the Splash screen and goes through onboarding, sign up, profile setup, the main tabs (Home, HUDDLE, Chat, Profile) and the orange “+” button for hosting a game.


### What the prototype contains

- **Launch and sign-in:** splash, three onboarding pages, sign up, sign in, forgot password, profile setup, welcome.
- **Home and social:** home feed, post detail, comments, share and report sheets, photo viewer, search, notifications.
- **HUDDLE:** discover deck, Interested and Not interested lists with Active/Expired tabs, sort sheet.
- **Game lifecycle:** game details in every state, apply sheet, application sent, host a game, game posted, my game, edit, cancel, applicants, invite player, post result, share moments, you're in.
- **Chat:** chat list, team chats (including a read-only ended game), direct messages with sent and failed states.
- **Profile and settings:** my profile, other players, block and report, settings, edit profile, sports and skill, password, blocked players, help, contact support, terms, delete account.


### Prototype audit (measured in the Figma file)

I counted the frames and prototype connections directly from the file instead of estimating:

| Measure | Result |
|---|---|
| Frames on the SCREENS page (screens plus their states, sheets and dialogs) | 220 |
| Screen-to-screen prototype connections | 1,644 (including 292 overlays such as sheets and dialogs, and 287 back actions) |
| Component state changes (toggles, chips, checkboxes), counted separately | 305 |
| Prototype flows | 4 (Flow 1–4, starting at the Splash screen) |
| Frames with no way forward (dead ends) | 0 |
| Frames that no link points to | 1: the Splash screen, which is the starting point of the flows |
| Planned screens and functions represented in Figma | 50 of 50 (see the coverage table in section 4) |

Every planned screen is in the file, every frame has at least one way forward, and every frame except the starting Splash screen can be reached through the prototype. That includes error states, loading states and confirmation dialogs. **The prototype covers 100% of the planned screens and is fully connected.**

> **About screenshots of the Figma frames:** Figma's export service returned blank images for this file, so this section uses the clickable link instead of frame images. The screens can be opened directly from the link above.

> **About a second Figma file:** I also have a simplified redesign called “HUDDL – Full App” ([link](https://www.figma.com/design/x42EaUZK7lkrMEEa8EeseC/HUDDL---Full-App)). I didn't use it as the prototype, because the working app follows the original design above.


## 3. Screenshots of the Running App

All 24 screenshots below come from the real SwiftUI app running on the iPhone 17 Pro simulator (iOS 26), connected to the local Firebase emulators. Most were captured automatically by the UI tests while they used the app. The rest were captured the same way for this report. None of them are Figma mockups. The demo data uses the eight seeded test players.

1. `assets/app/onboarding-1.png`: Onboarding, page 1. The illustration and copy come from the Figma onboarding frames.
2. `assets/app/signup-validation.png`: Sign up with invalid input. Each field shows the error message from the design.
3. `assets/app/profile-setup.png`: Profile setup (step 2 of 2): photo, sports, skill level and home area.
4. `assets/app/welcome.png`: Welcome screen after a new account finishes setup (account created by an automated test).
5. `assets/app/forgot-password-sent.png`: Forgot password after the reset link is sent, with the resend cooldown.
6. `assets/app/cap-home-top.png`: Home feed with community activity: players hosting games, each with a VIEW button.
7. `assets/app/post-detail-comment.png`: Post detail. A new comment appears right away through a real-time listener.
8. `assets/app/discover-card.png`: Discover deck: one game card at a time, with venue cover, host, format chips and roster.
9. `assets/app/interested-list.png`: Interested list after a right swipe, with the Active/Expired tabs and sorting.
10. `assets/app/game-details-joined.png`: Game details for a player on the roster: teams, LEAVE GAME and TEAM CHAT.
11. `assets/app/application-sent.png`: Application sent. The request is PENDING until the host reviews it.
12. `assets/app/host-form-ready.png`: Host a game: sport, title, venue, date, time, format, play type and locked rules.
13. `assets/app/my-game.png`: My game (host view) right after posting, with the APPLICANTS button and open spots.
14. `assets/app/applicants.png`: Applicants screen: notes, team choice and ACCEPT/DECLINE for each request.
15. `assets/app/notifications.png`: Notifications: a personal invite (ACCEPT/DECLINE), a new applicant and a share prompt.
16. `assets/app/youre-in.png`: Accepting a personal invite places the player on the team.
17. `assets/app/cap-chat-list.png`: Chat list with All / Game chats / Direct tabs and an unread badge.
18. `assets/app/dm.png`: Direct message between two players, sent in real time.
19. `assets/app/cap-chat-readonly.png`: A team chat after the game ended. Sending is closed and the chat is read-only.
20. `assets/app/cap-game-ended.png`: An ended game showing the Result & Moments card (Team A won 25–21, 25–19).
21. `assets/app/player-profile.png`: Another player's profile with INVITE TO GAME and MESSAGE.
22. `assets/app/blocked.png`: The same profile after blocking. Unblocking needs a confirmation.
23. `assets/app/my-profile.png`: My profile: stats, sports, and the Matches / Hosted / Reviews tabs.
24. `assets/app/settings.png`: Settings: account, notification toggles, privacy and support options.


## 4. Implementation Coverage Assessment


### How I measured it

The denominator is a list of **50 planned screens and functions**. It comes from the screen list in my Figma file, with the state variants of one screen merged into a single row (for example, “Sign in” covers sign in, its error state and its loading state). I added two cross-cutting functions that the design shows but that are not single screens: social sign-in and push notifications. File counts and lines of code were not used.

- **Figma status:** Completed = the screen, its states and its prototype connections exist in the file.
- **SwiftUI status:** Completed = the screen exists in the app's code and is reachable. Partially Implemented = part of it is placeholder or only visual.
- **Functionality status:** Completed = the feature worked during an automated UI test or a recorded capture. Not Verified = it is implemented but has not been tested in the running app yet. Partially Implemented and Planned are as written.
- **Scoring:** Completed = 1, Partially Implemented = 0.5, everything else = 0, divided by the number of rows.

| Assessment | Result |
|---|---|
| Figma prototype completeness | 50 Completed of 50 → **100%** (all screens represented and connected) |
| SwiftUI interface implementation | 47 Completed, 3 Partially Implemented → **97%** |
| Functionality verified in the running app | 30 of 50 → **60%** |
| Functionality implemented (verified + not yet verified + half of partial) | **96%** |

The midterm requires at least 50% of the planned interface and functionality. Counting **only features I have actually seen working**, HUDDL is at **60%**, which meets the requirement. The interface is close to complete. The main remaining work is testing the screens marked Not Verified and the features that need the paid Firebase plan.


### Coverage table

| # | Planned screen or function | Figma | SwiftUI | Functionality | Evidence |
|---|---|---|---|---|---|
| 1 | Splash screen | Completed | Completed | Completed | Seen on every launch |
| 2 | Onboarding (3 pages) | Completed | Completed | Completed | UI test 01 |
| 3 | Sign up with validation | Completed | Completed | Completed | UI tests 01, 02 |
| 4 | Sign in by username | Completed | Completed | Completed | UI tests 03, 13 |
| 5 | Forgot password | Completed | Completed | Completed | UI test 03 (emulator email) |
| 6 | Profile setup | Completed | Completed | Completed | UI test 02 (photo upload not tested) |
| 7 | Welcome | Completed | Completed | Completed | UI test 02 |
| 8 | Home feed | Completed | Completed | Completed | UI test 04 |
| 9 | Post detail and comments | Completed | Completed | Completed | UI test 04 |
| 10 | Post menu (report, hide, copy link) | Completed | Completed | Not Verified | Only Copy link tested |
| 11 | Share sheet | Completed | Completed | Not Verified | Not tested |
| 12 | Full-screen photo viewer | Completed | Completed | Not Verified | No photos in demo data |
| 13 | Search (games and players) | Completed | Completed | Completed | UI test 11 |
| 14 | Notifications list | Completed | Completed | Completed | UI test 09 |
| 15 | Discover swipe deck | Completed | Completed | Completed | UI test 05 |
| 16 | Interested list (Active/Expired) | Completed | Completed | Completed | UI test 05 |
| 17 | Not interested list | Completed | Completed | Completed | UI test 05 |
| 18 | Sort sheet | Completed | Completed | Not Verified | Not tested |
| 19 | Game details (default, joined, left) | Completed | Completed | Completed | UI test 06 |
| 20 | Game details, ended (result and moments) | Completed | Completed | Completed | Captured for this report |
| 21 | Apply sheet (team, solo/group, commitment) | Completed | Completed | Completed | UI test 05 (solo); group apply backend-only |
| 22 | Application sent | Completed | Completed | Completed | UI test 05 |
| 23 | Host a game (sport, venue, date, format) | Completed | Completed | Completed | UI test 07 |
| 24 | Game posted | Completed | Completed | Completed | UI test 07 |
| 25 | My game (host view and manage menu) | Completed | Completed | Completed | UI test 07 |
| 26 | Edit game | Completed | Completed | Not Verified | Opened in UI test 07; saving not tested |
| 27 | Cancel game and Game cancelled | Completed | Completed | Not Verified | Not tested |
| 28 | Applicants (accept, decline, no room) | Completed | Completed | Completed | UI test 08 |
| 29 | Invite player | Completed | Completed | Not Verified | Backend checks only |
| 30 | Post result | Completed | Completed | Not Verified | Not tested |
| 31 | Result posted | Completed | Completed | Not Verified | Not tested |
| 32 | Share moments (post-game compose) | Completed | Completed | Not Verified | Backend checks only |
| 33 | Personal invite accepted (You're in) | Completed | Completed | Completed | UI test 09 |
| 34 | Chat list | Completed | Completed | Completed | UI test 10 |
| 35 | Team chat (read-only after a game ends) | Completed | Completed | Completed | UI test 09; read-only state captured |
| 36 | Direct message | Completed | Completed | Completed | UI test 10 |
| 37 | My profile (matches, hosted, reviews) | Completed | Completed | Completed | UI test 12 |
| 38 | Player profile (invite, message, block, report) | Completed | Completed | Completed | UI test 11 |
| 39 | Settings | Completed | Completed | Completed | UI test 12 |
| 40 | Edit profile | Completed | Completed | Completed | UI test 12 |
| 41 | Sports and skill | Completed | Completed | Not Verified | Not tested |
| 42 | Password and security | Completed | Completed | Not Verified | Not tested |
| 43 | Blocked players list | Completed | Completed | Not Verified | Blocking tested; list screen not |
| 44 | Help center and articles | Completed | Completed | Not Verified | Not tested |
| 45 | Contact support | Completed | Completed | Not Verified | Not tested |
| 46 | Terms and privacy | Completed | Partially Implemented | Partially Implemented | Placeholder legal text |
| 47 | Delete account | Completed | Completed | Not Verified | Not run, to protect demo accounts |
| 48 | Log out | Completed | Completed | Not Verified | Not tested by a UI test |
| 49 | Google and Facebook sign-in | Completed | Partially Implemented | Planned | Buttons only; needs provider setup |
| 50 | Push notifications | Completed | Partially Implemented | Partially Implemented | Code exists; needs paid Firebase plan and APNs key |


### Testing evidence

| Test suite | Count | Latest result |
|---|---|---|
| Unit tests (validation, distance, initials) | 4 | 4 passed |
| End-to-end UI tests (drive the real app against the emulators) | 13 | 13 passed |
| Backend and security-rule checks (Cloud Functions + Firestore) | 33 | 33 passed |
| Seeded player accounts signing in through the app | 8 | 8 of 8 |

The tests found real bugs that were then fixed. Among them: two crashes on launch; the floating tab bar covering the chat Send button; security rules that hid likes and “pending” labels; blocking that failed to save; and a like counter that could show “-1 likes”.


## 5. Source Code Repository

| Item | Details |
|---|---|
| Repository | **ednaalas-as/HUDDL** (public)  
[https://github.com/ednaalas-as/HUDDL](https://github.com/ednaalas-as/HUDDL) |
| Main branch | `main` |
| Contents | The SwiftUI app, unit and UI tests, Firebase rules and Cloud Functions, the seed script, and documentation |
| Excluded on purpose | Test passwords, the Firebase config file, private notes, build output and logs (listed in `.gitignore`) |


### Project structure

| Folder | What is inside |
|---|---|
| `HUDDL/App` | App entry point, navigation router and shared live data |
| `HUDDL/DesignSystem` | My Figma components rebuilt in SwiftUI: colors, fonts, header, floating tab bar, buttons, chips, toast, dialogs |
| `HUDDL/Models` | Data models that match the Firestore documents (users, games, applications, posts, chats…) |
| `HUDDL/Services` | Code that talks to Firebase: sign-in, games, social, chat, notifications, storage, validation |
| `HUDDL/Features` | The screens, grouped by feature: Auth, Huddle, Game, Host, Social, Chat, Profile, Settings |
| `HUDDLTests`, `HUDDLUITests` | Unit tests and end-to-end UI tests |
| `firebase/` | Security rules, indexes, Cloud Functions, the seed script and the backend smoke test |
| `docs/` | Presentation guide, architecture and database notes, and this midterm submission |

The design keeps a simple rule: the app handles the screens and quick checks, and anything that has to be trusted runs on the server. Examples are accepting a player without overbooking a team, joining from an invite, and posting a result. Firestore security rules decide who can read or write each piece of data.


## 6. Midterm Learning Reflection

I started HUDDL as a design project. Before there was any code, I spent a lot of time in Figma building the screens and wiring the prototype so every button went somewhere. When I first tried to have the design redone by an AI tool, I didn't like the result, so I asked for it to be done my way and kept my original components and layout. That decision carried into development: the rule for the app was to match my Figma file, not to redesign it.

For the development, I worked with an AI coding assistant (Claude Code). I want to be honest about this: most of the Swift and Firebase code was written by the assistant, based on my Figma design and the instructions I wrote for it. My part was deciding what HUDDL should do and checking that the results matched what I wanted. I chose iOS 17 as the minimum version, decided to build and test on Firebase's local emulator first, and replaced the placeholder athletes in the design with eight real people I chose, each with their own account. Working this way taught me that the assistant can be confidently wrong. At different points it built against the wrong Figma file, created three Firebase projects when I needed one, and first put my database in the US instead of Singapore. I learned to check its work instead of just accepting it.

I learned a lot about how a SwiftUI app fits together by going through what was built. I now understand that the screens are small views that read from shared state, that one router object controls navigation for each tab, and that the same components (the header, the toast, the confirmation dialog) are reused everywhere instead of being redrawn on each screen. I also understand that what looks finished is not the same as what works. The first build had zero errors, but the app crashed the moment it opened because Firebase was used before it was set up.

Firebase was the biggest learning area for me. Before this project I thought of Firebase as one thing. Now I know the difference between Authentication, Firestore, Storage and Cloud Functions, and why some actions have to run on the server. For example, two hosts must not be able to accept the last spot at the same time. I also learned that security rules are where privacy actually happens. Emails are never stored in public profiles, and one test checks that other players cannot read your direct messages. Testing found that some of these rules were blocking the app's own legitimate queries, which is why likes and “pending” labels were not showing. That bug would have been easy to miss without the tests.

The practical challenges were real too. My Mac ran out of disk space during the first build, so I had to free up space before testing could continue. When I tried to move HUDDL to the real Firebase cloud, I found that Cloud Functions and photo storage need the paid Blaze plan, and I don't have a card. Instead of rewriting the app to fit the free plan and weakening its security, I kept the design. I created the real project with its database and rules in Singapore, enabled real Authentication with my own account, and run the full app on the emulator for now.

Testing changed how I think about “done.” Tapping through the simulator by hand was unreliable, so the project switched to automated UI tests. The tests sign in through the real screens and check what appears. Seeing 13 UI tests, 33 backend checks and all eight accounts pass gives me something concrete to show, instead of just saying that it works.


### What I plan to complete for the final project

I want to test everything that is still marked Not Verified, especially photo uploads, posting results and sharing moments. I also want to deploy the full backend if I can get access to the Blaze plan. Writing more of the remaining work myself, with the assistant explaining instead of writing, is also a goal for the final.


## 7. Final Project Development Plan


### High priority

- Test the implemented but unverified flows in the running app: photo and video upload, Post result, Share moments, Edit and Cancel game, Invite player, Delete account, Log out.
- Deploy Cloud Functions and Storage to `huddl-app-ph` once Blaze billing is available (for example, school credits), then run the tests against the cloud.


### Medium priority

- Turn on real push notifications (needs the Blaze plan and an Apple push key).
- Decide the reliability score and rating formulas, which are still open in the design.
- Move the device push token out of the public profile document into a private one.
- Compare the remaining screens side by side with Figma and fix any visual differences.


### Low priority

- Google and Facebook sign-in.
- Writing reviews and flagging a wrong result (these need design work first).
- Accessibility pass with VoiceOver and large text; venue photos.

---

## Evidence inventory (how each claim was checked, 18 Nov 2026)

| Claim | Evidence |
|---|---|
| Figma prototype: 220 frames, 1,644 screen links (292 overlays, 287 back), 305 component state changes, 4 flows, 0 dead ends, only the Splash start frame without an incoming link | Read directly from the Figma file with the Plugin API (read-only), page SCREENS. A first count (201 frames, 13 unlinked) missed 19 frames nested in groups and subsections and was corrected |
| "HUDDL – Full App" file is a different, simplified design | Same audit on that file; you chose the original file for the submission |
| 24 screenshots are from the real app | Captured by XCUITest runs on the iPhone 17 Pro simulator (iOS 26) against the emulators; stored in `assets/app/` |
| 4 unit tests, 13 UI tests passing | Latest full test run (Xcode result bundle), "TEST SUCCEEDED" |
| 33 backend checks passing | `npm --prefix firebase/functions test`, 33 passed / 0 failed |
| 8 accounts sign in independently | UI test 13 plus a live sign-in audit script |
| Ended-game result card and read-only team chat work | Extra screenshot capture run for this report (passed) |
| Public repository with no secrets | `gh repo view` → PUBLIC; anonymous HTTP 200; repository file list checked for credential files (none); staged-file scan before commit |
| Real Firebase project status | `firebase firestore:databases:get` → asia-southeast1; Auth export shows 1 user |
| No passwords/private emails in the PDF | PDF text scanned with PDFKit for password patterns and personal emails (none found) |

## Coverage numbers

- Figma prototype completeness: **100%** (50 of 50 Completed; every planned screen represented and connected)
- SwiftUI interface implementation: **97%** (47 Completed + 3 Partially Implemented of 50)
- Functionality verified in the running app: **60%** (30 of 50)
- Functionality implemented (verified + not yet verified + half of partial): **96%**

## Outstanding requirements

- Course and instructor are placeholders on the cover page.
- The reflection must be reviewed and personalized by the student before submission.
- Figma frame images couldn't be exported automatically (Figma returned blank renders), so the PDF relies on the link.
