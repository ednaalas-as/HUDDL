import SwiftUI
import FirebaseFirestore

// MARK: - SETTINGS (+ SAVED / PASSWORD UPDATED)

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs
    @State private var prefs = NotificationPrefs()
    @State private var showArea = false
    @State private var showPrivacy = false

    var body: some View {
        ScreenScaffold(title: "SETTINGS") {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group("Account") {
                        ChevronRow(symbol: "person.crop.circle", title: "Edit profile") { router.push(.editProfile) }
                        ChevronRow(symbol: "figure.run", title: "Sports & skill level") { router.push(.sportsSkill) }
                        ChevronRow(symbol: "mappin.and.ellipse", title: "Home area", value: session.user?.homeArea?.name) { showArea = true }
                        ChevronRow(symbol: "lock", title: "Password & security") { router.push(.password) }
                    }
                    group("Notifications") {
                        ToggleRow(title: "Game invites", isOn: binding(\.invites))
                        ToggleRow(title: "Application updates", isOn: binding(\.applications))
                        ToggleRow(title: "Chat messages", isOn: binding(\.chat))
                        ToggleRow(title: "Game reminders", isOn: binding(\.reminders))
                    }
                    group("Privacy & safety") {
                        ChevronRow(symbol: "envelope.badge", title: "Who can invite me", value: session.user?.settings.whoCanInvite.title) { showPrivacy = true }
                        ChevronRow(symbol: "hand.raised", title: "Blocked players") { router.push(.blockedPlayers) }
                    }
                    group("Support") {
                        ChevronRow(symbol: "questionmark.circle", title: "Help center") { router.push(.helpCenter) }
                        ChevronRow(symbol: "bubble.left", title: "Contact support") { router.push(.contactSupport) }
                        ChevronRow(symbol: "doc.text", title: "Terms & privacy") { router.push(.terms) }
                    }
                    group(nil) {
                        ChevronRow(symbol: "rectangle.portrait.and.arrow.right", title: "Log out") { confirmLogout() }
                        ChevronRow(symbol: "trash", title: "Delete account", tint: HColor.destructive) { router.push(.deleteAccount) }
                    }
                    Text("HUDDL \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "42"))")
                        .font(HFont.inter(11, .medium)).foregroundStyle(HColor.muted).frame(maxWidth: .infinity)
                }
                .padding(20)
            }
        }
        .onAppear { prefs = session.user?.settings.notifications ?? NotificationPrefs() }
        .sheet(isPresented: $showArea) {
            HomeAreaSheet(current: session.user?.homeArea) { a in
                save(["homeArea": ["name": a.name, "latitude": a.latitude, "longitude": a.longitude, "geohash": a.geohash], "city": a.name], toast: "Home area updated")
            }
        }
        .sheet(isPresented: $showPrivacy) {
            VStack(alignment: .leading, spacing: 4) {
                SheetTitle(title: "Who can invite me")
                ForEach(InvitePrivacy.allCases) { p in
                    SheetOptionRow(symbol: p == .everyone ? "globe" : p == .played ? "person.2" : "nosign", title: p.title,
                                   isSelected: session.user?.settings.whoCanInvite == p) {
                        save(["settings.whoCanInvite": p.rawValue], toast: "Saved", dotted: true); showPrivacy = false
                    }
                }
                Spacer()
            }.padding(.horizontal, 24).huddlSheet([.height(300)])
        }
    }

    private func group<C: View>(_ title: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { SectionLabel(text: title) }
            VStack(spacing: 4) { content() }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20)).cardShadow(0.05, radius: 8, y: 4)
        }
    }

    private func binding(_ kp: WritableKeyPath<NotificationPrefs, Bool>) -> Binding<Bool> {
        Binding(get: { prefs[keyPath: kp] }, set: { v in
            prefs[keyPath: kp] = v
            let key: String = switch kp { case \.invites: "invites"; case \.applications: "applications"; case \.chat: "chat"; default: "reminders" }
            save(["settings.notifications.\(key)": v], toast: v ? "Notifications on" : "Notifications off", dotted: true)
        })
    }

    private func save(_ fields: [String: Any], toast: String, dotted: Bool = false) {
        Task {
            do {
                if dotted, let uid = session.uid {
                    try await Firestore.firestore().collection("users").document(uid).updateData(fields)
                } else { try await session.updateProfile(fields) }
                toasts.show(toast)
            } catch { toasts.error(AppError.message(error)) }
        }
    }

    private func confirmLogout() {
        dialogs.confirm(ConfirmRequest(symbol: "rectangle.portrait.and.arrow.right", title: "Log out?", message: "You can sign back in anytime with your username.",
                                       confirmTitle: "LOG OUT", destructive: true) { session.signOut() })
    }
}

// MARK: - EDIT PROFILE (+ ERROR / SAVING)

struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var photo: UIImage?
    @State private var removePhoto = false
    @State private var area: HomeArea?
    @State private var showPhoto = false
    @State private var showArea = false
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        ScreenScaffold(title: "EDIT PROFILE") {
            ScrollView {
                VStack(spacing: 18) {
                    Button { showPhoto = true } label: {
                        ZStack(alignment: .bottomTrailing) {
                            if let photo { Image(uiImage: photo).resizable().scaledToFill().frame(width: 100, height: 100).clipShape(Circle()) }
                            else { AvatarView(name: name, photoURL: removePhoto ? nil : session.user?.photoURL, size: 100) }
                            Image(systemName: "camera.circle.fill").font(.system(size: 30)).foregroundStyle(.white, HColor.orange)
                        }
                    }.accessibilityLabel("Change profile photo")
                    LabeledField(label: "Name", placeholder: "Your name", text: $name, error: error, maxLength: 40)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Username")
                        Text(session.user?.handle ?? "").font(HFont.inter(15, .medium)).foregroundStyle(HColor.secondary)
                            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .background(HColor.avatarBG.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Home area")
                        Button { showArea = true } label: {
                            HStack { Text(area?.name ?? "Choose").font(HFont.inter(15, .medium)).foregroundStyle(HColor.darkText); Spacer(); Image(systemName: "mappin.circle.fill").foregroundStyle(HColor.brandNavy) }
                                .padding(.horizontal, 16).frame(height: 50).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HColor.chipBorder))
                        }.buttonStyle(.plain)
                    }
                    OrangeButton(title: "SAVE", isLoading: saving, action: save).padding(.top, 8)
                }
                .padding(20)
            }
        }
        .overlay { if saving { LoadingOverlay(text: "Saving…") } }
        .onAppear { name = session.user?.displayName ?? ""; area = session.user?.homeArea }
        .onChange(of: name) { error = nil }
        .sheet(isPresented: $showPhoto) {
            PhotoSourceSheet(allowsRemove: session.user?.photoURL != nil || photo != nil,
                             onImage: { photo = $0; removePhoto = false }, onRemove: { photo = nil; removePhoto = true })
        }
        .sheet(isPresented: $showArea) { HomeAreaSheet(current: area) { area = $0 } }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard n.count >= 2 else { error = "Enter your name"; return }
        saving = true
        Task {
            do {
                var fields: [String: Any] = ["displayName": n]
                if let photo { fields["photoURL"] = try await StorageService.uploadImage(photo, folder: .avatars, maxDimension: 800) }
                else if removePhoto { fields["photoURL"] = FieldValue.delete() }
                if let a = area { fields["homeArea"] = ["name": a.name, "latitude": a.latitude, "longitude": a.longitude, "geohash": a.geohash]; fields["city"] = a.name }
                try await session.updateProfile(fields)
                toasts.show("Profile updated")
                dismiss()
            } catch { toasts.error(AppError.message(error)) }
            saving = false
        }
    }
}

// MARK: - SPORTS & SKILL

struct SportsSkillView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var skills: [Sport: SkillLevel] = [:]

    var body: some View {
        ScreenScaffold(title: "SPORTS & SKILL") {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pick the sports you play and your level for each.").font(HFont.inter(13, .medium)).foregroundStyle(HColor.secondary)
                    ForEach(Sport.allCases) { s in
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: Binding(get: { skills[s] != nil }, set: { skills[s] = $0 ? .intermediate : nil })) {
                                Label(s.title, systemImage: s.symbol).font(HFont.inter(15, .semibold)).foregroundStyle(HColor.darkText)
                            }.tint(HColor.orange)
                            if let level = skills[s] {
                                HStack(spacing: 8) {
                                    ForEach(SkillLevel.allCases) { l in SelectChip(text: l.title, isOn: level == l) { skills[s] = l } }
                                }
                            }
                        }
                        .padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                    OrangeButton(title: "SAVE") { save() }.padding(.top, 6)
                }
                .padding(20)
            }
        }
        .onAppear { for s in session.user?.sports ?? [] { skills[s.sport] = s.skill } }
    }

    private func save() {
        guard !skills.isEmpty else { toasts.error("Pick at least one sport you play"); return }
        let list = Sport.allCases.compactMap { s in skills[s].map { ["sport": s.rawValue, "skill": $0.rawValue] } }
        Task {
            do { try await session.updateProfile(["sports": list]); toasts.show("Saved"); dismiss() }
            catch { toasts.error(AppError.message(error)) }
        }
    }
}

// MARK: - PASSWORD & SECURITY (+ ERROR / FILLED)

struct PasswordSecurityView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var errors: [String: String] = [:]
    @State private var saving = false

    var body: some View {
        ScreenScaffold(title: "PASSWORD") {
            ScrollView {
                VStack(spacing: 18) {
                    AuthField(placeholder: "current password", text: $current, isSecure: true, contentType: .password, error: errors["current"])
                    AuthField(placeholder: "new password", text: $new, isSecure: true, contentType: .newPassword, error: errors["new"])
                    AuthField(placeholder: "confirm new password", text: $confirm, isSecure: true, contentType: .newPassword, error: errors["confirm"])
                    Text("Use at least 8 characters, including a number.").font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary)
                    OrangeButton(title: "UPDATE PASSWORD", isLoading: saving, action: save)
                    Button("Forgot your current password?") {
                        guard let email = session.email else { return }
                        Task {
                            do { try await session.sendPasswordReset(email: email); toasts.show("Reset link sent to your email. It expires in 30 minutes.") }
                            catch { toasts.error(AppError.message(error)) }
                        }
                    }
                    .font(HFont.inter(12, .semibold)).foregroundStyle(HColor.orange)
                }
                .padding(20)
            }
        }
    }

    private func save() {
        var e: [String: String] = [:]
        if current.isEmpty { e["current"] = "Enter your current password" }
        e["new"] = Validation.password(new, requireNumber: true)
        e["confirm"] = Validation.confirm(new, confirm)
        errors = e.compactMapValues { $0 }
        guard errors.isEmpty else { return }
        saving = true
        Task {
            do { try await session.updatePassword(current: current, new: new); toasts.show("Password updated"); dismiss() }
            catch { errors["current"] = AppError.message(error) }
            saving = false
        }
    }
}

// MARK: - BLOCKED PLAYERS (+ EMPTY)

struct BlockedPlayersView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs
    @State private var players: [PlayerRef] = []

    var body: some View {
        ScreenScaffold(title: "BLOCKED") {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if players.isEmpty {
                        EmptyStateView(symbol: "hand.raised", title: "No blocked players", message: "Players you block show up here. You can unblock them anytime.")
                    }
                    ForEach(players) { p in
                        PlayerLine(player: p) {
                            SmallPillButton(title: "UNBLOCK", kind: .outline) { confirm(p) }
                        }
                        .padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(20)
            }
        }
        .task(id: data.blocked) { players = (try? await SocialService.blockedPlayers(uid: session.uid ?? "")) ?? [] }
    }

    private func confirm(_ p: PlayerRef) {
        dialogs.confirm(ConfirmRequest(symbol: "hand.raised.slash", title: "Unblock \(p.name)?", message: "They’ll be able to see your games, invite you and message you again.",
                                       confirmTitle: "UNBLOCK") {
            Task {
                do { try await SocialService.setBlocked(p, by: session.uid ?? "", blocked: false); toasts.show("\(p.name) is unblocked") }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }
}

// MARK: - HELP CENTER → HELP ARTICLE, CONTACT SUPPORT → SUPPORT SENT, TERMS & PRIVACY

enum HelpArticle: String, CaseIterable, Hashable, Identifiable {
    case swiping, applying, hosting, fixedTeams, reliability, invites, results, safety
    var id: String { rawValue }
    var title: String {
        switch self {
        case .swiping: "How does swiping work?"
        case .applying: "How do I apply to a game?"
        case .hosting: "How do I host a game?"
        case .fixedTeams: "Why are teams fixed with no substitutes?"
        case .reliability: "What is my reliability score?"
        case .invites: "How do personal invites work?"
        case .results: "How are results posted?"
        case .safety: "Blocking and reporting"
        }
    }
    var body: String {
        switch self {
        case .swiping: "Discover shows one game at a time. Swipe right (Interested) to save it to your Interested list, or left (Not interested). You can move games back anytime. Games that start or fill up move to Expired and are kept for 30 days."
        case .applying: "Apply from your Interested list or from Game Details. Pick a team, join solo or with your group, add a note to the host and tick the commitment box. The host reviews your application and you’ll be notified when you’re accepted."
        case .hosting: "Tap + to host. Choose the sport, title, venue, date and time, format (1v1 to 6v6, or custom up to 6 per team), and whether solo players or groups can apply. Turn on Invite only to hide it from Discover."
        case .fixedTeams: "To keep games fair, every HUDDL game has fixed teams and no substitutes. Rosters lock when the game starts. If someone drops before the start, their spot reopens to applicants."
        case .reliability: "Your reliability score reflects whether you show up for games you join. Leaving a game within 24 hours of its start lowers it. HUDDL is still finalising how the score is calculated."
        case .invites: "Hosts can invite you directly. You’ll get a notification you can accept or decline. You control who can invite you in Settings → Who can invite me."
        case .results: "After the game, the host posts the winner and set scores. The result appears on the Home feed and both teams’ profiles. Opponents can flag a mistake within 24 hours."
        case .safety: "Block a player from their profile’s ••• menu — they won’t be notified. Report posts or players and our team reviews reports within 24 hours. Reports are anonymous."
        }
    }
}

struct HelpCenterView: View {
    @Environment(Router.self) private var router
    var body: some View {
        ScreenScaffold(title: "HELP CENTER") {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(HelpArticle.allCases) { a in ChevronRow(symbol: "doc.text", title: a.title) { router.push(.helpArticle(a)) } }
                    GhostButton(title: "CONTACT SUPPORT") { router.push(.contactSupport) }.padding(.top, 16)
                }
                .padding(.horizontal, 16).padding(.vertical, 10).background(Color.white, in: RoundedRectangle(cornerRadius: 20)).padding(20)
            }
        }
    }
}

struct HelpArticleView: View {
    let article: HelpArticle
    @Environment(ToastCenter.self) private var toasts
    @State private var voted = false
    var body: some View {
        ScreenScaffold(title: "HELP") {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(article.title).font(HFont.inter(22, .extraBold)).foregroundStyle(HColor.brandNavy)
                    Text(article.body).font(HFont.inter(15, .medium)).foregroundStyle(HColor.body).lineSpacing(4)
                    Divider().padding(.vertical, 8)
                    Text("Was this helpful?").font(HFont.inter(13, .semibold))
                    HStack {
                        SmallPillButton(title: "YES", kind: .outline) { feedback() }
                        SmallPillButton(title: "NO", kind: .outline) { feedback() }
                    }.disabled(voted).opacity(voted ? 0.5 : 1)
                }
                .padding(20)
            }
        }
    }
    private func feedback() { voted = true; toasts.show("Thanks for your feedback!") }
}

struct ContactSupportView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @State private var topic: String?
    @State private var message = ""
    @State private var photo: UIImage?
    @State private var showTopics = false
    @State private var showPhoto = false
    @State private var errors: [String: String] = [:]
    @State private var sending = false
    @State private var sent = false
    private let topics = ["Account & sign in", "Games & hosting", "Applications & invites", "Chat & notifications", "Safety & reporting", "Something else"]

    var body: some View {
        ZStack {
            if sent {
                SuccessScreen(symbol: "envelope.open.fill", title: "Message sent", message: "Thanks! Our support team will reply to your account email within 1–2 days.",
                              primaryTitle: "DONE", primary: { dismiss() })
            } else {
                ScreenScaffold(title: "CONTACT SUPPORT") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(text: "Topic")
                                Button { showTopics = true } label: {
                                    HStack { Text(topic ?? "Choose a topic").foregroundStyle(topic == nil ? HColor.placeholder : HColor.darkText); Spacer(); Image(systemName: "chevron.down") }
                                        .font(HFont.inter(15, .medium)).padding(.horizontal, 16).frame(height: 50)
                                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(errors["topic"] != nil ? HColor.destructive : HColor.chipBorder))
                                }.buttonStyle(.plain)
                                if let e = errors["topic"] { Text(e).font(HFont.inter(11, .semibold)).foregroundStyle(HColor.destructive) }
                            }
                            LabeledField(label: "Message", placeholder: "Tell us what happened (at least 10 characters)", text: $message, axis: .vertical, error: errors["message"], maxLength: 2000)
                            Button { showPhoto = true } label: {
                                Label(photo == nil ? "Add a screenshot (optional)" : "Screenshot added · Change", systemImage: "photo")
                                    .font(HFont.inter(13, .semibold)).foregroundStyle(HColor.brandNavy)
                            }
                            OrangeButton(title: "SEND", isLoading: sending, action: send)
                        }
                        .padding(20)
                    }
                }
            }
        }
        .onChange(of: message) { errors["message"] = nil }
        .sheet(isPresented: $showTopics) {
            VStack(alignment: .leading, spacing: 4) {
                SheetTitle(title: "Topic")
                ForEach(topics, id: \.self) { t in SheetOptionRow(symbol: "tag", title: t, isSelected: topic == t) { topic = t; errors["topic"] = nil; showTopics = false } }
                Spacer()
            }.padding(.horizontal, 24).huddlSheet([.medium])
        }
        .sheet(isPresented: $showPhoto) { PhotoSourceSheet(allowsRemove: photo != nil, onImage: { photo = $0 }, onRemove: { photo = nil }) }
    }

    private func send() {
        var e: [String: String] = [:]
        if topic == nil { e["topic"] = "Choose a topic" }
        if message.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 { e["message"] = "Tell us a bit more (at least 10 characters)" }
        errors = e
        guard e.isEmpty, let uid = session.uid else { return }
        sending = true
        Task {
            do {
                var url: String?
                if let photo { url = try await StorageService.uploadImage(photo, folder: .support) }
                try await SocialService.submitTicket(SupportTicket(uid: uid, topic: topic!, message: message, attachmentURL: url))
                withAnimation { sent = true }
            } catch { toasts.error(AppError.message(error)) }
            sending = false
        }
    }
}

struct TermsView: View {
    @State private var privacy = false
    var body: some View {
        ScreenScaffold(title: "TERMS & PRIVACY") {
            VStack(spacing: 0) {
                FrostedSegmented(options: [(false, "Terms"), (true, "Privacy")], selection: $privacy).padding(.horizontal, 20).padding(.top, 10)
                ScrollView {
                    Text(privacy ? Self.privacyText : Self.termsText).font(HFont.inter(14, .medium)).foregroundStyle(HColor.body).lineSpacing(4).padding(20)
                }
            }
        }
    }
    // HUDDL is a student project (CSSE105). These terms describe how the app actually works; they are not reviewed legal advice.
    static let termsText = """
    Terms of Use · Last updated November 2026

    1. About HUDDL
    HUDDL helps people find others to play sports with: volleyball, badminton, basketball, football, lawn tennis, pickleball, chess and billiards. HUDDL is a student project built for CSSE105: Mobile Application Development at Manuel S. Enverga University Foundation. It is not a commercial service.

    2. Your account
    You need an account to use HUDDL. Keep your password private and use a username that does not impersonate anyone. You are responsible for what happens under your account. You must be at least 13 years old to create one.

    3. Joining games
    When you apply to or join a game, you agree to show up. Every HUDDL game has fixed teams and no substitutes, and rosters lock when the game starts. Leaving a game within 24 hours of its start lowers your reliability score.

    4. Hosting games
    Hosts must give accurate details: sport, venue, date, time and format. Hosts decide who joins their game and must treat every applicant fairly. If you cancel a game, every player and applicant is notified.

    5. Posts, results and messages
    Only post photos, videos and captions that you have the right to share. Results must reflect what actually happened; opponents can flag a result within 24 hours. Do not post or send spam, harassment, hateful content or anything illegal.

    6. Safety
    Meet in public venues and play within your ability. HUDDL does not run venues or supervise games, and is not responsible for injuries, lost items or disputes at games. You can block or report any player or post at any time.

    7. Breaking these terms
    Accounts and posts that break these terms may be removed.

    8. Changes
    These terms may change as the project develops. The date at the top shows the latest version.
    """
    static let privacyText = """
    Privacy Policy · Last updated November 2026

    What we store
    • Your profile: name, username, photo, sports and skill levels, and your home area.
    • Your activity: games you host, apply to and join; swipes; posts, likes and comments; messages; notifications; reports and blocks.
    • Your email address, used only to sign in and to recover your account.

    Who can see it
    • Other players see your name, username, photo, sports and the games you play.
    • Your email address is never shown to other players.
    • Direct messages are visible only to the two people in the conversation. Team chats are visible only to that game's players.
    • Reports are anonymous, and the player you block is not notified.

    Where it is stored
    HUDDL uses Google Firebase (Authentication, Cloud Firestore, Cloud Storage and Cloud Functions). Access to your data is controlled by Firebase security rules.

    Location
    HUDDL uses the home area you choose to show games near you. It does not track your live location.

    Your choices
    • Edit your profile, sports and home area at any time in Settings.
    • Turn notifications on or off for each type.
    • Choose who can invite you to games.
    • Delete your account in Settings → Delete account. This removes your profile, history and reviews, cancels games you host and removes you from games you joined.

    Contact
    Use Settings → Contact support to ask a question about your data.
    """
}

// MARK: - DELETE ACCOUNT (+ READY) → ACCOUNT DELETED

struct DeleteAccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DialogCenter.self) private var dialogs
    @Environment(ToastCenter.self) private var toasts
    @State private var confirmText = ""
    @State private var deleting = false

    private var ready: Bool { confirmText == "DELETE" }

    var body: some View {
        ScreenScaffold(title: "DELETE ACCOUNT") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This permanently deletes your HUDDL account.").font(HFont.inter(18, .bold)).foregroundStyle(HColor.destructive)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Your profile, history and reviews are deleted.", systemImage: "person.crop.circle.badge.xmark")
                        Label("Games you host are cancelled and players are notified.", systemImage: "calendar.badge.minus")
                        Label("You’re removed from games you joined.", systemImage: "person.3")
                    }
                    .font(HFont.inter(13, .medium)).foregroundStyle(HColor.body)
                    LabeledField(label: "Type DELETE to confirm", placeholder: "DELETE", text: $confirmText)
                        .textInputAutocapitalization(.characters)
                    Button {
                        dialogs.confirm(ConfirmRequest(symbol: "trash.fill", title: "Delete your account?", message: "This can’t be undone.",
                                                       confirmTitle: "DELETE ACCOUNT", destructive: true) { delete() })
                    } label: {
                        Text("DELETE ACCOUNT").font(HFont.button(15)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
                            .background(HColor.destructive.opacity(ready ? 1 : 0.35), in: Capsule())
                    }.disabled(!ready)
                }
                .padding(20)
            }
        }
        .overlay { if deleting { LoadingOverlay(text: "Deleting your account…") } }
    }

    private func delete() {
        deleting = true
        Task {
            do { try await session.deleteAccount(); toasts.show("Your account was deleted") }
            catch { toasts.error(AppError.message(error)) }
            deleting = false
        }
    }
}
