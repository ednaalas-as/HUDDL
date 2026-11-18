import XCTest

/// End-to-end UI tests that drive the real HUDDL app against the local Firebase emulators.
/// Run `firebase/emulators.sh`, then `npm --prefix firebase/functions run seed`, then the tests (see README).
/// Temporary passwords are read at runtime from the git-ignored seed file — never stored in code.
final class HUDDLUITests: XCTestCase {
    var app: XCUIApplication!

    static let credentials: [String: [String: String]] = {
        let path = ProcessInfo.processInfo.environment["HUDDL_CREDS_PATH"]
            ?? "\(NSHomeDirectory().components(separatedBy: "/Library/Developer").first ?? "")/Desktop/HUDDL/firebase/functions/seed-credentials.local.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return [:] }
        return json
    }()
    func password(_ user: String) -> String { Self.credentials[user]?["password"] ?? "" }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestNoAnimations"]
        app.launch()
    }

    /// Attach a screenshot and the visible text whenever an assertion fails, so failures can be diagnosed.
    override func record(_ issue: XCTIssue) {
        if let app {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "FAILURE"; shot.lifetime = .keepAlways; add(shot)
            let labels = app.staticTexts.allElementsBoundByIndex.prefix(80).map(\.label).joined(separator: " | ")
            let t = XCTAttachment(string: labels); t.name = "FAILURE-texts"; t.lifetime = .keepAlways; add(t)
        }
        super.record(issue)
    }

    // MARK: Helpers

    @discardableResult
    func waitFor(_ e: XCUIElement, _ timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "Missing: \(e)", file: file, line: line)
        return e
    }
    func text(_ s: String) -> XCUIElement { app.staticTexts[s].firstMatch }
    func textContaining(_ s: String) -> XCUIElement { app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }
    func button(_ s: String) -> XCUIElement { app.buttons[s].firstMatch }
    func id(_ s: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: s).firstMatch }
    func buttonContaining(_ s: String) -> XCUIElement { app.buttons.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }
    func lastButton(_ s: String) -> XCUIElement { let q = app.buttons.matching(NSPredicate(format: "label == %@", s)); return q.element(boundBy: max(0, q.count - 1)) }
    func snap(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func type(_ field: String, _ value: String) {
        let f = app.descendants(matching: .any).matching(identifier: "field.\(field)").firstMatch
        waitFor(f).tap(); f.typeText(value)
    }
    func dismissKeyboard() { if app.keyboards.count > 0 { app.staticTexts.firstMatch.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.1)).tap() } }

    func goToAuth() {
        waitFor(button("SKIP"), 20).tap()
        waitFor(button("Get Started")).tap()
        waitFor(text("Sign Up"))
    }

    func signIn(_ user: String, pw: String? = nil) {
        goToAuth()
        button("Sign In").tap()
        waitFor(button("SIGN IN"))
        type("username", user)
        type("password", pw ?? password(user))
        dismissKeyboard()
        button("SIGN IN").tap()
    }

    func signInToHome(_ user: String) {
        signIn(user)
        waitFor(button("Home"), 25)
    }

    func logOut() {
        button("Profile").tap()
        waitFor(button("Settings")).tap()
        let logout = button("Log out")
        app.swipeUp()
        waitFor(logout).tap()
        waitFor(button("LOG OUT")).tap()
        waitFor(button("SIGN IN"), 20)
    }

    // MARK: 1. Onboarding & sign-up validation

    func test01_OnboardingAndSignUpValidation() {
        waitFor(button("SKIP"), 20)
        snap("onboarding-1")
        button("Next").tap()
        waitFor(text("Try new things near you."))
        button("SKIP").tap()
        waitFor(text("More than a game."))
        snap("onboarding-3")
        button("Get Started").tap()
        waitFor(text("Sign Up"))
        button("SIGN UP").tap()
        waitFor(text("Fill in all fields to create your account"))
        type("username", "edna alas-as!")
        type("email address", "bademail")
        type("password", "short")
        type("confirm password", "other")
        dismissKeyboard()
        button("SIGN UP").tap()
        waitFor(text("Spaces aren't allowed in usernames"))
        XCTAssertTrue(text("Enter a valid email address").exists)
        XCTAssertTrue(text("Use at least 8 characters").exists)
        XCTAssertTrue(text("Passwords don't match").exists)
        snap("signup-validation")
        // Social buttons respond honestly (provider config not available on the emulator).
        button("Continue with Google").tap()
        waitFor(textContaining("Google sign-in will be available"))
    }

    // MARK: 2. New account → profile setup → welcome → Discover

    func test02_SignUpProfileSetupWelcome() {
        goToAuth()
        let uname = "tester\(Int.random(in: 1000...9999))"
        type("username", uname)
        type("email address", "\(uname)@huddl.test")
        type("password", "Password123")
        type("confirm password", "Password123")
        dismissKeyboard()
        button("SIGN UP").tap()
        waitFor(text("Set up your profile"), 25)
        snap("profile-setup")
        button("CONTINUE").tap()
        waitFor(text("Pick at least one sport you play"))
        button("Volleyball").tap()
        button("CONTINUE").tap()
        waitFor(textContaining("You’re all set"), 25)
        snap("welcome")
        button("FIND A GAME").tap()
        waitFor(button("Discover"), 20)
        snap("discover-new-user")
    }

    // MARK: 3. Sign-in errors & forgot password

    func test03_SignInErrorsAndForgotPassword() {
        signIn("ednaalas-as", pw: "wrong-password-1")
        waitFor(text("Wrong username or password"), 20)
        snap("signin-wrong-password")
        button("Forgot Password?").tap()
        waitFor(button("SEND LINK"))
        button("SEND LINK").tap()
        waitFor(text("Enter your email address"))
        type("email address", "edna@huddl.test")
        dismissKeyboard()
        button("SEND LINK").tap()
        waitFor(text("Check your email"), 20)
        waitFor(buttonContaining("Resend link in"))
        snap("forgot-password-sent")
    }

    // MARK: 4. Home feed: like, comment, menus

    func test04_HomeFeedInteractions() {
        signInToHome("ednaalas-as")
        waitFor(textContaining("Great Match!"), 30)
        snap("home-feed")
        let like = button("Like")
        waitFor(like).tap()
        waitFor(button("Unlike"))
        button("Comment").tap()
        waitFor(text("Comments"))
        let send = button("Send comment")
        send.tap()
        waitFor(text("Type a message first"))
        let field = app.textFields["Add a comment…"]
        waitFor(field).tap(); field.typeText("Great game, team!")
        send.tap()
        waitFor(text("Great game, team!"), 20)
        snap("post-detail-comment")
        app.buttons["Back"].firstMatch.tap()
        waitFor(button("More options")).tap()
        waitFor(button("Copy link")).tap()
        waitFor(text("Link copied"))
    }

    // MARK: 5. HUDDLE: Discover swipe, lists, details, apply

    func test05_DiscoverSwipeListsAndApply() {
        signInToHome("kyleabandia")
        button("Huddle").tap()
        waitFor(text("ROSTER"), 25)
        snap("discover-card")
        id("discover.pass").tap()
        waitFor(text("Moved to Not interested"))
        waitFor(id("discover.like")).tap()
        waitFor(textContaining("Added to Interested"))
        // Interested list
        id("seg.Interested").tap()
        waitFor(buttonContaining("Active ·"))
        snap("interested-list")
        let apply = button("APPLY")
        waitFor(apply, 20).tap()
        waitFor(button("SEND APPLICATION"), 20)
        button("SEND APPLICATION").tap()
        waitFor(text("Tick the commitment box to send your application"))
        button("I can commit to this game. Teams are fixed and there are no substitutes.").tap()
        button("SEND APPLICATION").tap()
        waitFor(text("Application sent"), 25)
        snap("application-sent")
        button("VIEW MY GAMES").tap()
        waitFor(button("APPLIED"), 20)
        // Not interested list + move back
        id("seg.Not interested").tap()
        waitFor(textContaining("You swiped left on these"))
        waitFor(button("INTERESTED")).tap()
        waitFor(text("Moved to Interested"))
    }

    // MARK: 6. Game details states + leave game confirmation

    func test06_GameDetailsJoinedAndLeave() {
        signInToHome("desireeferrer")
        button("Profile").tap()
        waitFor(text("Saturday 6v6 Open"), 25).tap()
        waitFor(text("GAME DETAILS"))
        waitFor(textContaining("Rosters ("))
        waitFor(button("TEAM CHAT"))
        snap("game-details-joined")
        button("LEAVE GAME").tap()
        waitFor(textContaining("lowers your reliability score"))
        button("Cancel").tap()
        // Roster row opens player profile
        app.staticTexts["Bea Anne Balmes"].firstMatch.tap()
        waitFor(text("PLAYER"))
    }

    // MARK: 7. Hosting: validation, post, my game, edit, applicants accept

    func test07_HostGameAndManage() {
        signInToHome("ednaalas-as")
        button("Host a game").tap()
        waitFor(text("HOST A GAME"))
        button("POST GAME").tap()
        waitFor(text("Add a game title to post your game"))
        waitFor(text("Add a title so players know what to expect"))
        app.staticTexts["Fixed teams"].firstMatch.tap()
        waitFor(textContaining("always on in HUDDL"))
        let title = app.textFields["e.g. Saturday 6v6 Open"]
        title.tap(); title.typeText("UI Test Rally")
        dismissKeyboard()
        app.staticTexts["Choose a court or gym"].firstMatch.tap()
        waitFor(text("MSEUF Gymnasium")).tap()
        snap("host-form-ready")
        button("POST GAME").tap()
        waitFor(text("Your game is live!"), 25)
        button("VIEW MY GAME").tap()
        waitFor(text("MY GAME"), 20)
        waitFor(textContaining("HOSTING ·"))
        snap("my-game")
        button("Manage game").tap()
        waitFor(button("Edit game")).tap()
        waitFor(text("EDIT GAME"))
        // No changes → closes without a discard prompt; with changes → asks to discard.
        let title2 = app.textFields.firstMatch
        title2.tap(); title2.typeText(" 2")
        button("Back").tap()
        waitFor(text("Discard your changes?"))
        waitFor(button("DISCARD")).tap()
        waitFor(text("MY GAME"))
    }

    func test08_ApplicantsAccept() {
        signInToHome("ednaalas-as")
        button("Profile").tap()
        button("Hosted").tap()
        waitFor(text("Beach Volley Sunday"), 25).tap()
        waitFor(text("MY GAME"))
        button("APPLICANTS").tap()
        waitFor(id("seg.Pending"))
        waitFor(text("Roselle Jean De Leon"))
        snap("applicants")
        sleep(2) // let the game listener load so capacity checks use live data
        let dump = XCTAttachment(string: app.buttons.allElementsBoundByIndex.map { "\($0.label)|hit=\($0.isHittable)|\($0.frame)" }.joined(separator: "\n")); dump.name = "applicant-buttons"; dump.lifetime = .keepAlways; add(dump)
        button("ACCEPT").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitFor(id("dialog.title"))
        XCTAssertTrue(id("dialog.title").label.contains("Accept Roselle"))
        id("dialog.confirm").tap()
        waitFor(textContaining("is in"), 25)
        snap("applicant-accepted")
        button("DECLINE").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitFor(text("Skill level doesn’t match")).tap()
        id("decline.confirm").tap()
        waitFor(textContaining("friendly notification"), 25)
    }

    // MARK: 9. Notifications: personal invite accept

    func test09_NotificationInviteAccept() {
        signInToHome("ednaalas-as")
        button("Notifications").tap()
        waitFor(text("NOTIFICATION"))
        waitFor(text("Bea Anne Balmes invited you personally"), 20)
        snap("notifications")
        button("ACCEPT").tap()
        waitFor(button("JOIN TEAM B")).tap()
        waitFor(text("You’re on Team B!"), 25)
        snap("youre-in")
        button("OPEN TEAM CHAT").tap()
        waitFor(text("SATURDAY 6V6 OPEN"), 20)
    }

    // MARK: 10. Chat: DM send + empty send validation

    func test10_DirectMessage() {
        signInToHome("ednaalas-as")
        button("Chat").tap()
        waitFor(button("Direct")).tap()
        waitFor(text("Bea Anne Balmes"), 20).tap()
        waitFor(text("BEA ANNE BALMES"))
        snap("dm-open")
        let tree = XCTAttachment(string: app.buttons.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" }.joined(separator: "\n")); tree.name = "dm-buttons"; tree.lifetime = .keepAlways; add(tree)
        button("Send").tap()
        waitFor(text("Type a message first"))
        let f = app.textFields["Message…"]
        f.tap(); f.typeText("See you Saturday!")
        button("Send").tap()
        waitFor(text("See you Saturday!"), 20)
        snap("dm")
    }

    // MARK: 11. Profiles, search, block / unblock, report, settings

    func test11_SearchProfileBlockAndSettings() {
        signInToHome("ednaalas-as")
        button("Search").tap()
        let q = app.textFields["Search games, venues, players"]
        waitFor(q).typeText("kyle")
        waitFor(id("seg.Players")).tap()
        waitFor(text("Kyle Allen Abandia"), 20).tap()
        waitFor(button("INVITE TO GAME"))
        snap("player-profile")
        button("More options").tap()
        waitFor(button("Block")).tap()
        waitFor(button("BLOCK")).tap()
        waitFor(button("UNBLOCK"), 20)
        snap("blocked")
        button("UNBLOCK").tap()
        waitFor(textContaining("Unblock Kyle"))
        id("dialog.confirm").tap()
        waitFor(button("INVITE TO GAME"), 20)
        sleep(3) // let the unblock toast clear
        button("More options").tap()
        waitFor(button("Report")).tap()
        waitFor(text("Spam or misleading")).tap()
        waitFor(text("Thanks for letting us know"))
    }

    func test12_SettingsAndEditProfile() {
        signInToHome("ednaalas-as")
        button("Profile").tap()
        waitFor(text("Edna Alas-as"))
        snap("my-profile")
        button("Settings").tap()
        waitFor(text("SETTINGS"))
        app.switches.firstMatch.tap()
        waitFor(text("Notifications off"))
        app.switches.firstMatch.tap()
        waitFor(text("Notifications on"))
        snap("settings")
        button("Edit profile").tap()
        waitFor(text("EDIT PROFILE"))
        button("SAVE").tap()
        waitFor(text("Profile updated"), 20)
    }

    // MARK: 13. All eight accounts sign in independently

    func test13_AllEightAccountsSignIn() {
        let users = ["ednaalas-as", "beaannebalmes", "roselledeleon", "kyleabandia",
                     "jhonlloydvalencia", "thessasurell", "altheaaringo", "desireeferrer"]
        XCTAssertEqual(Self.credentials.count, 8, "Seed credentials file not found")
        for (i, u) in users.enumerated() {
            if i > 0 { app.terminate(); app.launch() }
            signInToHome(u)
            button("Profile").tap()
            waitFor(textContaining("@\(u)"), 20)
        }
    }
}
