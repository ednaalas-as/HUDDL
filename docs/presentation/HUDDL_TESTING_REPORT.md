# HUDDL — Testing Report

All results below are from the **local Firebase Emulator Suite** (project `demo-huddl`) on the **iPhone 17 Pro simulator (iOS 26.0)**, Xcode 26.0.1. **Nothing has been tested against a production Firebase project.**

## 1. Summary (verified against the test files and the latest runs)

| Suite | File | Count | Latest result | When |
|---|---|---|---|---|
| Unit tests (XCTest) | `HUDDLTests/ValidationTests.swift` | **4** | 4 passed, 0 failed | 18 Nov 2026, 11:57 full run |
| End-to-end UI tests (XCUITest) | `HUDDLUITests/HUDDLUITests.swift` | **13** | 13 passed, 0 failed ("TEST SUCCEEDED") | 18 Nov 2026, 11:57 full run |
| Backend + security-rules checks | `firebase/functions/src/smoke-test.ts` | **33** | 33 passed, 0 failed | Re-run 18 Nov 2026, 12:49, after the last seed change |
| Account verification script | (audit script, run during documentation) | 8 accounts | 8/8: email sign-in ✔, username sign-in ✔, uid = username record = profile document ✔, no email leak ✔ | 18 Nov 2026 |

> **Note:** after the final UI run, the *seed script* was changed (it now also creates team chats for seeded games). That only adds data. The app code wasn't changed. The backend suite was re-run afterwards and passed 33/33. The UI suite wasn't re-run after that seed change.

## 2. Types of testing (what each means here)

- **Unit testing:** tests one small piece of code in isolation, with no UI and no network. Here: the validation and geography helper functions.
- **UI testing:** an automated "robot user" (XCUITest) launches the real app, taps buttons, types text and checks what appears on screen. It saves screenshots, and on failure attaches a screenshot plus all visible text.
- **Integration testing:** checking that parts work together (app ↔ Firebase ↔ Cloud Functions). The UI tests are also integration tests, because they run against real emulators, with no mocks.
- **Backend testing:** a Node script signs in as real seeded users and calls Cloud Functions and the Firestore REST API directly. It checks business rules and that **security rules refuse forbidden access**.
- **Manual testing:** a person (or an assistant driving the simulator) taps through screens and compares them with Figma. Used for visual checks and to confirm failures.

## 3. Unit tests (4)

| Test | What / why | Expected → actual |
|---|---|---|
| `testUsernameRules` | Empty name, spaces/symbols ("edna alas-as!"), valid "ednaalas-as". Bad usernames must never reach the server. | Correct Figma error messages; valid name passes → **pass** |
| `testEmailPasswordConfirm` | Invalid email, short password, "8+ incl. a number" rule, mismatched confirmation | Messages match the design → **pass** |
| `testGeoRadius` | MSEUF Gym is under 10 km from Lucena; geohash prefixes cover the home cell. Discover depends on this maths. | → **pass** |
| `testInitials` | "Edna Alas-as" → "EA"; 4-part names → first + last initial. Avatars without photos. | → **pass** |

## 4. End-to-end UI tests (13), all passing in the latest full run

Each test launches the app fresh (`-uiTestReset` signs out; `-uiTestNoAnimations`). Passwords are read at runtime from the git-ignored credentials file, never stored in the code.

| # | Test | Account | What it does | Verifies |
|---|---|---|---|---|
| 1 | `test01_OnboardingAndSignUpValidation` | none | Onboarding Next/SKIP, Get Started; empty Sign up; bad username/email/password/confirm; Google button | Every validation message; honest social-login message |
| 2 | `test02_SignUpProfileSetupWelcome` | new random `testerNNNN` | Full sign-up → Profile setup ("pick a sport" error) → Volleyball → Welcome → FIND A GAME | Account creation, username reservation, profile completion, navigation to Discover |
| 3 | `test03_SignInErrorsAndForgotPassword` | ednaalas-as | Wrong password; Forgot password empty/valid email | "Wrong username or password"; "Check your email"; resend cooldown |
| 4 | `test04_HomeFeedInteractions` | ednaalas-as | Feed loads; like → Unlike; open post; empty comment; post a comment; ••• → Copy link | Real-time feed, likes, comments, menus |
| 5 | `test05_DiscoverSwipeListsAndApply` | kyleabandia | Pass ✕, like ♥, Interested list, APPLY without commitment, with commitment, APPLIED, Not interested → move back | Swipes, lists, apply validation, Application sent, PENDING/APPLIED |
| 6 | `test06_GameDetailsJoinedAndLeave` | desireeferrer | Open joined game from profile; Leave dialog; tap roster player | Joined state, TEAM CHAT button, 24 h reliability copy, roster → profile |
| 7 | `test07_HostGameAndManage` | ednaalas-as | + → POST without title; locked-rules toast; title + venue → POST → Your game is live → My game → Edit → discard changes | Host validation, game creation (rules + trigger), My game, edit discard prompt |
| 8 | `test08_ApplicantsAccept` | ednaalas-as | Beach Volley Sunday → Applicants → ACCEPT Roselle → confirm; DECLINE Jhon with reason | Server transaction, live counts, private decline |
| 9 | `test09_NotificationInviteAccept` | ednaalas-as | Notifications → Bea's invite → ACCEPT → JOIN TEAM B → You're on Team B → OPEN TEAM CHAT | Invite flow end to end, team chat |
| 10 | `test10_DirectMessage` | ednaalas-as | Chat → Direct → Bea → empty send → send text | DM real-time send, empty-message check |
| 11 | `test11_SearchProfileBlockAndSettings` | ednaalas-as | Search "kyle" → Players → profile → Block → Unblock → Report | Search, block/unblock persistence, anonymous report |
| 12 | `test12_SettingsAndEditProfile` | ednaalas-as | Profile; toggle notifications off/on; Edit profile → SAVE | Settings persistence, profile update |
| 13 | `test13_AllEightAccountsSignIn` | all 8 | For each account: launch, sign in via the UI by **username**, open Profile, check `@username` | **Each of the 8 accounts signs in independently** |

## 5. Backend + security checks (33), all passing

1–2 Username sign-in rejects a wrong password · returns a custom token
3 `usernames` document holds no email
4–7 Players can't edit their own stats · can't edit someone else's profile · can't change rosters directly · non-hosts can't read others' applications
8–12 Apply without commitment refused · solo-only game rejects groups · full team refused with "Team A is full. Pick Team B to apply." · valid application → pending · duplicate application refused
13–17 Only the host can accept · host accepts · player is on the roster · player can read the team chat · applicant gets an "accepted" notification
18–21 Host can invite · duplicate invite → "already has an invite" · invitee accepts and joins · player can leave before the start
22–25 Empty post refused ("Add a photo, video or caption to post") · tags limited to that game's players · moments post created · "Only me" posts hidden from others
26–27 DM thread opens · non-members can't read a DM
28–33 Own applications listable · others' applications not listable · own likes listable · own invites listable · own block list readable · others can't read someone's block list

## 6. Bugs found during testing, and their fixes

| # | Found by | Problem | Fix |
|---|---|---|---|
| 1 | Simulator launch | App crashed on launch: a store used Firestore before Firebase was configured | Configure Firebase in `HUDDLApp.init`; Firestore access in `SessionStore` made lazy |
| 2 | Simulator launch | Crash: Firebase Messaging rejected the placeholder API-key format | Correctly-shaped dummy key (not a credential) |
| 3 | Manual visual check | Onboarding background overflowed the screen, was too bright, showed a hard edge; dark status bar | Matched Figma values (30% opacity, rotated, clipped); status bar follows the dark screen |
| 4 | UI test 10 | **Floating tab bar covered pushed screens.** Tapping Send in chat hit "Profile" | Tab bar shown only on root screens (`Router.isAtRoot`) |
| 5 | UI test 4 + new backend checks | Likes, PENDING chips and INVITED YOU chips never appeared: rules couldn't authorize collection-group queries | Rules now check a stored field equals your uid; 4 new backend checks |
| 6 | UI test 11 + data inspection | Block failed for players without a photo (invalid null), and your own block list couldn't be listed | Store `NSNull`; split the read rule; 2 new backend checks |
| 7 | UI test 4 | Feed showed "-1 likes" after re-seeding | Like trigger uses a transaction that never goes below 0; UI clamps too |
| 8 | Home screen | Blank, then black app icon | Rebuilt from the Figma favicon (luminance mask) |
| 9 | Data audit | Seeding reset "Hosted" counts to 0 and later deleted team chats | Seed recounts `stats.hosted` and recreates team chats |
| 10 | Test harness | Coordinate taps in the simulator dropped typed text | Switched to XCUITest; added accessibility identifiers (`field.*`, `seg.*`, `discover.*`, `dialog.*`) |

Several UI-test failures along the way were **test-script mistakes**, not app bugs: wrong element type, ambiguous labels, timing. Each one was diagnosed with failure screenshots and confirmed manually before the test was fixed.

## 7. What has NOT been tested in the running app (honest list)

Implemented in code, but **not exercised by any UI test or manual run**:
- Photo/video upload (profile photo, post-result photos, Share moments media, chat photos). Simulator file picking wasn't automated.
- Share moments composer end to end in the app (the backend `createPost` is tested).
- Post result screen in the app (the backend `postResult` isn't covered by the smoke test).
- Game lifecycle: started/ended transitions, Expired moves, read-only chat after a game ends, the "game ended" prompt. The scheduler doesn't run in the emulator.
- Cancel game, withdraw application, cancel invite, decline-invite UI, group applications in the app.
- Delete account (code exists; not run, because it would delete a demo account).
- Home-area GPS location (needs location permission).
- Password change; Contact support submission; Help article feedback.
- Real push notifications, real reset emails, Google/Facebook sign-in (need production config).
- Dark mode (the app forces light mode), Dynamic Type at large sizes, VoiceOver walkthrough, and other iPhone sizes.

**Coverage claim:** the tests cover the main happy paths and the key validation/security rules for the core flows. They do **not** cover every screen state or edge case.
