import SwiftUI
import FirebaseFirestore

// MARK: - Applicants (Pending / Accepted / Declined)

struct ApplicantsView: View {
    let gameId: String
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs

    enum Tab: Hashable { case pending, accepted, declined }
    @State private var tab: Tab = .pending
    @State private var apps: [GameApplication] = []
    @State private var game: Game?
    @State private var listeners: [ListenerRegistration] = []
    @State private var declining: GameApplication?
    @State private var busy: String?

    private var pending: [GameApplication] { apps.filter { $0.status == .pending || $0.status == .noRoom } }
    private var accepted: [GameApplication] { apps.filter { $0.status == .accepted } }
    private var declined: [GameApplication] { apps.filter { $0.status == .declined } }

    var body: some View {
        ScreenScaffold(title: "APPLICANTS") {
            VStack(spacing: 0) {
                FrostedSegmented(options: [(Tab.pending, "Pending · \(pending.count)"), (.accepted, "Accepted · \(accepted.count)"), (.declined, "Declined · \(declined.count)")],
                                 selection: $tab).padding(.horizontal, 20).padding(.top, 10)
                if let g = game, g.status == .full {
                    Label("Roster full — the roster is locked and remaining applicants were told.", systemImage: "lock.fill")
                        .font(HFont.inter(12, .semibold)).foregroundStyle(HColor.success)
                        .padding(12).frame(maxWidth: .infinity).background(HColor.successBG, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20).padding(.top, 10)
                }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        let list = tab == .pending ? pending : tab == .accepted ? accepted : declined
                        if list.isEmpty {
                            EmptyStateView(symbol: "tray", title: tab == .pending ? "No pending applicants" : tab == .accepted ? "No one accepted yet" : "No declined applicants",
                                           message: tab == .pending ? "Invite players directly to fill your spots faster." : "Applicants you handle will show here.",
                                           actionTitle: tab == .pending ? "INVITE PLAYERS" : nil,
                                           action: tab == .pending ? { router.push(.invitePlayers(gameId)) } : nil)
                        }
                        ForEach(list) { app in card(app) }
                    }
                    .padding(20)
                }
            }
        }
        .onAppear {
            listeners = [
                GameService.listenApplicants(gameId: gameId) { apps = $0.filter { $0.status != .withdrawn } },
                GameService.listen(gameId) { if case .success(let g) = $0 { game = g } },
            ]
        }
        .onDisappear { listeners.forEach { $0.remove() } }
        .sheet(item: $declining) { app in DeclineSheet(app: app) { reason in decline(app, reason: reason) } }
    }

    private func card(_ app: GameApplication) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { router.push(.player(app.applicant.id)) } label: {
                PlayerLine(player: app.applicant, subtitle: "@\(app.applicant.username) · " + howApplied(app))
            }.buttonStyle(.plain)
            if !app.groupMembers.isEmpty {
                Text("With " + app.groupMembers.map(\.name).joined(separator: ", ")).font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary)
            }
            if !app.note.isEmpty {
                Text("“\(app.note)”").font(HFont.inter(13, .medium)).foregroundStyle(HColor.body)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(HGradient.tint, in: RoundedRectangle(cornerRadius: 12))
            }
            switch app.status {
            case .pending, .noRoom:
                HStack(spacing: 10) {
                    if app.status == .noRoom || noRoom(app) {
                        SmallPillButton(title: "NO ROOM", kind: .outline) { noRoomDialog(app) }
                    }
                    Spacer()
                    SmallPillButton(title: "DECLINE", kind: .destructive) { declining = app }
                    SmallPillButton(title: busy == app.id ? "…" : "ACCEPT", kind: .orange) { confirmAccept(app) }
                }
            case .accepted:
                HStack {
                    StatusTag(text: "ACCEPTED", kind: .success)
                    Spacer()
                    SmallPillButton(title: "MESSAGE", kind: .outline) { openDM(app.applicant.id) }
                }
            default:
                StatusTag(text: "DECLINED", kind: .muted)
            }
        }
        .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 20)).cardShadow(0.07, radius: 10, y: 6)
    }

    private func howApplied(_ app: GameApplication) -> String {
        if app.via == "invite" { return "Invited by you" }
        return app.joinAs == .group ? "Group of \(app.size) · Team \(app.teamId)" : "Solo · Team \(app.teamId)"
    }

    private func noRoom(_ app: GameApplication) -> Bool {
        guard let team = game?.teams.first(where: { $0.id == app.teamId }) else { return false }
        return app.size > team.spotsLeft
    }

    private func noRoomDialog(_ app: GameApplication) {
        dialogs.confirm(ConfirmRequest(symbol: "person.3.sequence", title: "Not enough room",
            message: "\(app.applicant.name)’s group needs \(app.size) spots. Decline, or keep them pending in case a spot opens.",
            confirmTitle: "DECLINE", cancelTitle: "Keep pending", destructive: true) { declining = app })
    }

    private func confirmAccept(_ app: GameApplication) {
        if noRoom(app) { noRoomDialog(app); return }
        let fillsLast = (game?.spotsLeft ?? 0) == app.size
        dialogs.confirm(ConfirmRequest(symbol: "checkmark", title: "Accept \(app.applicant.name)?",
            message: fillsLast ? "This fills the last spot. The roster locks and remaining applicants are told the game is full."
                               : "They’ll join Team \(app.teamId) and get access to the team chat.",
            confirmTitle: "ACCEPT") {
            busy = app.id
            Task {
                do {
                    let res = try await GameService.accept(gameId: gameId, applicantId: app.applicant.id)
                    if res["noRoom"] as? Bool == true { toasts.info("Not enough room for this group — kept pending") }
                    else { toasts.show((res["filledLast"] as? Bool == true) ? "Roster full! Everyone has been notified." : "\(app.applicant.name) is in") }
                } catch { toasts.error(AppError.message(error)) }
                busy = nil
            }
        })
    }

    private func decline(_ app: GameApplication, reason: String?) {
        Task {
            do { try await GameService.decline(gameId: gameId, applicantId: app.applicant.id, reason: reason); toasts.show("Declined. They’ll get a friendly notification.") }
            catch { toasts.error(AppError.message(error)) }
        }
    }

    private func openDM(_ uid: String) {
        Task {
            do { router.push(.chat(try await ChatService.directThread(with: uid))) } catch { toasts.error(AppError.message(error)) }
        }
    }
}

struct DeclineSheet: View {
    let app: GameApplication
    let onDecline: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason: String?
    @State private var other = ""
    private let reasons = ["Roster is already set", "Skill level doesn’t match", "Other reason"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetTitle(title: "Decline \(app.applicant.name)?", subtitle: "They’ll get a friendly notification. Your reason stays private.")
            ForEach(reasons, id: \.self) { r in
                SheetOptionRow(symbol: "text.bubble", title: r, isSelected: reason == r) { reason = r }
            }
            if reason == "Other reason" {
                TextField("Add a private note (optional)", text: $other).padding(12).background(HColor.avatarBG.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
            Button {
                onDecline(reason == "Other reason" ? (other.isEmpty ? reason : other) : reason); dismiss()
            } label: {
                Text("DECLINE").font(HFont.button(15)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 50).background(HColor.destructive, in: Capsule())
            }
            .accessibilityIdentifier("decline.confirm")
        }
        .padding(.horizontal, 24).padding(.bottom, 12).huddlSheet([.medium])
    }
}

// MARK: - Invite players (+ SENT / CANCELLED / CLEARED)

struct InvitePlayersView: View {
    let gameId: String
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs

    @State private var query = ""
    @State private var players: [AppUser] = []
    @State private var invites: [String: GameInvite] = [:]
    @State private var game: Game?
    @State private var listeners: [ListenerRegistration] = []
    @State private var inviting: AppUser?

    var body: some View {
        ScreenScaffold(title: "INVITE PLAYER") {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(HColor.muted)
                    TextField("Search players by name or @username", text: $query).textInputAutocapitalization(.never)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(HColor.muted) } }
                }
                .padding(.horizontal, 16).frame(height: 44).background(Color.white, in: Capsule()).padding(.horizontal, 20).padding(.top, 10)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: query.isEmpty ? "Suggested players" : "Results")
                        if filtered.isEmpty {
                            EmptyStateView(symbol: "person.crop.circle.badge.questionmark", title: "No players found", message: "Try another name or username.")
                        }
                        ForEach(filtered) { u in row(u) }
                    }
                    .padding(20)
                }
            }
        }
        .task { players = (try? await SocialService.allPlayers()) ?? [] }
        .onAppear {
            listeners = [
                GameService.listenInvites(gameId: gameId) { list in
                    invites = Dictionary(uniqueKeysWithValues: list.compactMap { i in i.id.map { ($0, i) } })
                },
                GameService.listen(gameId) { if case .success(let g) = $0 { game = g } },
            ]
        }
        .onDisappear { listeners.forEach { $0.remove() } }
        .sheet(item: $inviting) { u in InviteMessageSheet(player: u, game: game) { team, msg in send(u, team: team, message: msg) } }
    }

    private var filtered: [AppUser] {
        let hidden = data.hiddenUsers()
        let sports = Set(game.map { [$0.sport] } ?? [])
        return players
            .filter { $0.uid != session.uid && !hidden.contains($0.uid) }
            .filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.username.contains(query.lowercased().replacingOccurrences(of: "@", with: "")) }
            .sorted { (($0.sports.contains { sports.contains($0.sport) }) ? 0 : 1, $0.displayName) < (($1.sports.contains { sports.contains($0.sport) }) ? 0 : 1, $1.displayName) }
    }

    @ViewBuilder
    private func row(_ u: AppUser) -> some View {
        let joined = game?.isMember(u.uid) ?? false
        let invite = invites[u.uid]
        Button { router.push(.player(u.uid)) } label: {
            PlayerLine(player: PlayerRef(u), subtitle: [u.handle, u.primarySport.map { "\($0.sport.title) · \($0.skill.title)" }].compactMap { $0 }.joined(separator: " · ")) {
                if joined {
                    SmallPillButton(title: "JOINED", kind: .outline) { toasts.info("\(u.displayName) is already on the roster") }
                } else if invite?.status == .sent {
                    SmallPillButton(title: "INVITED", kind: .outline) { confirmCancel(u) }
                } else {
                    SmallPillButton(title: "INVITE", kind: .orange) {
                        guard let g = game, g.isJoinable else { toasts.info("This game has no open spots"); return }
                        inviting = u
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func send(_ u: AppUser, team: String, message: String) {
        Task {
            do { try await GameService.invite(gameId: gameId, inviteeId: u.uid, teamId: team, message: message); toasts.show("Invite sent") }
            catch { toasts.error(AppError.message(error)) }
        }
    }

    private func confirmCancel(_ u: AppUser) {
        let first = u.displayName.split(separator: " ").first.map(String.init) ?? u.displayName
        dialogs.confirm(ConfirmRequest(symbol: "xmark", title: "Cancel invite?",
            message: "\(first) won’t be able to accept it anymore. You can invite them again later.", confirmTitle: "CANCEL INVITE", cancelTitle: "Keep invite", destructive: true) {
            Task {
                do { try await GameService.cancelInvite(gameId: gameId, inviteeId: u.uid); toasts.show("Invite cancelled") }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }
}

struct InviteMessageSheet: View {
    let player: AppUser
    let game: Game?
    let onSend: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var team = "B"
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetTitle(title: "Invite \(player.displayName)", subtitle: game?.title)
            if let g = game {
                HStack(spacing: 8) {
                    ForEach(g.teams.filter { !$0.isFull }) { t in
                        SelectChip(text: "Team \(t.id) · \(t.spotsLeft) open", isOn: team == t.id) { team = t.id }
                    }
                }
            }
            LabeledField(label: "Message (optional)", placeholder: "Why should they join?", text: $message, axis: .vertical, maxLength: 300)
            Spacer()
            OrangeButton(title: "SEND INVITE") { onSend(team, message); dismiss() }
        }
        .padding(.horizontal, 24).padding(.bottom, 12).huddlSheet([.medium])
        .onAppear { team = game?.teams.first { !$0.isFull && $0.id == "B" }?.id ?? game?.teams.first { !$0.isFull }?.id ?? "A" }
    }
}

// MARK: - Post result (+ TEAM B / SET 3 / POSTING) → RESULT POSTED

struct PostResultView: View {
    let gameId: String
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs
    @Environment(\.dismiss) private var dismiss

    @State private var game: Game?
    @State private var winner = "A"
    @State private var sets: [(a: String, b: String)] = [("", ""), ("", "")]
    @State private var caption = ""
    @State private var photos: [UIImage] = []
    @State private var showPhotos = false
    @State private var posting = false
    @State private var postedId: String?

    var body: some View {
        ZStack {
            if let postedId, let g = game {
                SuccessScreen(symbol: "trophy.fill", title: "Result posted!",
                              message: "\(g.title) is on the Home feed and on both teams’ profiles. Opponents can flag a mistake within 24 hours.",
                              primaryTitle: "VIEW ON HOME", primary: { router.showHomeWithNewPost(); router.go(.home, .post(postedId), root: true) },
                              secondaryTitle: "DONE", secondary: { dismiss() })
            } else {
                ScreenScaffold(title: "POST RESULT") { form }
            }
            if posting { LoadingOverlay(text: "Posting…") }
        }
        .task { game = try? await GameService.fetch(gameId) }
        .sheet(isPresented: $showPhotos) { MediaPickerSheet { items in photos += items.compactMap(\.image) } }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let g = game {
                    Text(g.title).font(HFont.inter(20, .extraBold)).foregroundStyle(HColor.brandNavy)
                    SectionLabel(text: "Who won?")
                    FrostedSegmented(options: g.teams.map { ($0.id, "Team \($0.id)") }, selection: $winner)
                    SectionLabel(text: "Set scores")
                    ForEach(sets.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            Text("Set \(i + 1)").font(HFont.inter(14, .semibold)).frame(width: 52, alignment: .leading)
                            scoreField("A", $sets[i].a)
                            Text("–").font(HFont.inter(16, .bold))
                            scoreField("B", $sets[i].b)
                            if sets.count > 1 {
                                Button { sets.remove(at: i) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(HColor.destructive) }
                                    .accessibilityLabel("Remove set \(i + 1)")
                            }
                        }
                    }
                    if sets.count < 5 {
                        Button("+ Add set") { sets.append(("", "")) }.font(HFont.inter(13, .semibold)).foregroundStyle(HColor.accentTag)
                    }
                    SectionLabel(text: "Photos")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button { showPhotos = true } label: {
                                RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(HColor.muted)
                                    .frame(width: 80, height: 80).overlay(Image(systemName: "plus").foregroundStyle(HColor.brandNavy))
                            }.accessibilityLabel("Add photos")
                            ForEach(photos.indices, id: \.self) { i in
                                Image(uiImage: photos[i]).resizable().scaledToFill().frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(alignment: .topTrailing) {
                                        Button { photos.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.5)) }.padding(4)
                                    }
                            }
                        }
                    }
                    LabeledField(label: "Caption", placeholder: "How did it go?", text: $caption, axis: .vertical, maxLength: 500)
                    OrangeButton(title: "POST RESULT") { confirm(g) }
                } else { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(20)
        }
    }

    private func scoreField(_ label: String, _ text: Binding<String>) -> some View {
        TextField(label, text: text).keyboardType(.numberPad).multilineTextAlignment(.center)
            .font(HFont.inter(18, .bold)).frame(width: 64, height: 44)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(HColor.chipBorder))
            .onChange(of: text.wrappedValue) { _, v in text.wrappedValue = String(v.filter(\.isNumber).prefix(2)) }
    }

    private func confirm(_ g: Game) {
        for (i, s) in sets.enumerated() where s.a.isEmpty || s.b.isEmpty {
            toasts.error("Enter a score for Set \(i + 1) or remove it"); return
        }
        let parsed = sets.map { SetScore(a: Int($0.a) ?? 0, b: Int($0.b) ?? 0) }
        let line = parsed.map { winner == "A" ? "\($0.a)–\($0.b)" : "\($0.b)–\($0.a)" }.joined(separator: ", ")
        dialogs.confirm(ConfirmRequest(symbol: "trophy", title: "Post this result?",
            message: "Team \(winner) won \(line). Both teams will be notified, and it will appear on the Home feed and your profiles.",
            confirmTitle: "POST RESULT") {
            posting = true
            Task {
                do {
                    var urls: [String] = []
                    for p in photos { urls.append(try await StorageService.uploadImage(p, folder: .posts)) }
                    try await GameService.postResult(gameId: g.gid, winnerTeamId: winner, sets: parsed, caption: caption, mediaURLs: urls)
                    let posts = try? await SocialService.posts(forGame: g.gid, viewer: g.host.id)
                    postedId = posts?.first { $0.type == .result }?.pid ?? ""
                } catch { toasts.error(AppError.message(error)) }
                posting = false
            }
        })
    }
}
