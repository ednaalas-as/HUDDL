import SwiftUI
import FirebaseFirestore

/// Shared profile layout for PROFILE (mine) and PLAYER PROFILE (others).
struct ProfileContent: View {
    let user: AppUser
    let isMe: Bool
    @Binding var tab: ProfileTab
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts

    @State private var matches: [Game] = []
    @State private var hosted: [Game] = []
    @State private var reviews: [Review] = []
    @State private var helpful: Set<String> = []
    @State private var loading = true

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                AvatarView(name: user.displayName, photoURL: user.photoURL, size: 96, ring: true).cardShadow(0.12, radius: 10, y: 6)
                Text(user.displayName).font(HFont.inter(22, .extraBold)).foregroundStyle(HColor.brandNavy)
                Text([user.handle, user.city].compactMap { $0 }.joined(separator: " · ")).font(HFont.inter(13, .medium)).foregroundStyle(HColor.secondary)
                if !user.sports.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(user.sports, id: \.self) { s in InfoChip(text: "\(s.sport.title) · \(s.skill.title)") }
                    }.padding(.horizontal, 30)
                }
            }
            HStack(spacing: 0) {
                stat("\(user.stats.games)", "Games")
                stat("\(user.stats.wins)", "Wins")
                // Rating formula is OPEN in the design — show a dash until it is defined.
                stat(user.stats.rating.map { String(format: "%.1f", $0) } ?? "—", "Rating")
                stat("\(user.stats.hosted)", "Hosted")
            }
            .padding(.vertical, 14).background(Color.white, in: RoundedRectangle(cornerRadius: 20)).cardShadow(0.06, radius: 8, y: 4)

            TextTabs(options: [(ProfileTab.matches, "Matches"), (.hosted, "Hosted"), (.reviews, "Reviews · \(reviews.count)")], selection: $tab)

            if loading { ProgressView().padding(30) } else {
                switch tab {
                case .matches: gameList(matches, empty: isMe ? "Games you join show up here." : "No matches yet.")
                case .hosted: gameList(hosted, empty: isMe ? "Host your first game with the + button." : "No hosted games yet.", hostedTab: true)
                case .reviews: reviewList
                }
            }
        }
        .task(id: user.uid) { await load() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(HFont.inter(18, .extraBold)).foregroundStyle(HColor.darkText)
            Text(label).font(HFont.inter(11, .semibold)).foregroundStyle(HColor.secondary)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func gameList(_ games: [Game], empty: String, hostedTab: Bool = false) -> some View {
        if games.isEmpty {
            EmptyStateView(symbol: hostedTab ? "flag" : "sportscourt", title: "Nothing here yet", message: empty,
                           actionTitle: isMe ? (hostedTab ? "HOST A GAME" : "FIND A GAME") : nil,
                           action: isMe ? { if hostedTab { router.cover = .host } else { router.openHuddle(.discover) } } : nil)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(games) { g in
                    GameRow(game: g, area: session.user?.homeArea, relation: data.relation(to: g, uid: session.uid ?? "")) {
                        if isMe && hostedTab && g.host.id == session.uid && g.hasStarted && g.result == nil && g.status != .cancelled {
                            RowButton(title: "POST RESULT") { router.push(.postResult(g.gid)) }
                        } else if let r = g.result {
                            let won = g.team(of: user.uid)?.id == r.winnerTeamId
                            StatusTag(text: won ? "WON" : "LOST", kind: won ? .success : .muted)
                        }
                    }
                    .onTapGesture { router.push(.game(g.gid)) }
                }
            }
        }
    }

    @ViewBuilder private var reviewList: some View {
        if reviews.isEmpty {
            EmptyStateView(symbol: "star", title: "No reviews yet", message: "Reviews from teammates and opponents will show here.")
        } else {
            let tags = Dictionary(grouping: reviews.flatMap(\.tags), by: { $0 }).mapValues(\.count).sorted { $0.value > $1.value }
            FlowLayout(spacing: 6) { ForEach(tags.prefix(4), id: \.key) { InfoChip(text: "\($0.key) · \($0.value)") } }
            ForEach(reviews) { r in
                VStack(alignment: .leading, spacing: 8) {
                    Button { router.push(.player(r.reviewer.id)) } label: {
                        PlayerLine(player: r.reviewer, subtitle: [r.gameTitle, r.createdAt?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "), size: 36)
                    }.buttonStyle(.plain)
                    Text(r.text).font(HFont.inter(13, .medium)).foregroundStyle(HColor.body)
                    Button {
                        guard let id = r.id, let uid = session.uid, !helpful.contains(id) else { return }
                        helpful.insert(id)
                        Task { try? await SocialService.markHelpful(id, uid: uid); toasts.show("Thanks for your feedback!") }
                    } label: {
                        Label("Helpful · \(r.helpfulCount + (helpful.contains(r.id ?? "") ? 1 : 0))", systemImage: helpful.contains(r.id ?? "") ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(HFont.inter(11, .semibold)).foregroundStyle(HColor.brandNavy)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func load() async {
        loading = true
        async let j = (try? GameService.joined(by: user.uid)) ?? []
        async let h = (try? GameService.hosted(by: user.uid)) ?? []
        async let r = (try? SocialService.reviews(for: user.uid)) ?? []
        let (joined, host, revs) = await (j, h, r)
        matches = joined.filter { $0.host.id != user.uid || $0.hasStarted }
        hosted = isMe ? host : host.filter { !$0.inviteOnly }
        reviews = revs
        loading = false
    }
}

// MARK: - PROFILE (+ HOSTED / REVIEWS / UPDATED)

struct ProfileView: View {
    var initialTab: ProfileTab = .matches
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    @State private var tab: ProfileTab = .matches

    var body: some View {
        VStack(spacing: 0) {
            HuddlHeader(style: .title("PROFILE")) {
                Button { router.push(.settings) } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 20)).foregroundStyle(.black).frame(width: 44, height: 44)
                }.accessibilityLabel("Settings")
            }
            if let user = session.user {
                ScrollView {
                    VStack(spacing: 14) {
                        ProfileContent(user: user, isMe: true, tab: $tab)
                        HStack(spacing: 10) {
                            GhostButton(title: "EDIT PROFILE", height: 44) { router.push(.editProfile) }
                            GhostButton(title: "SPORTS & SKILL", height: 44) { router.push(.sportsSkill) }
                        }
                    }
                    .padding(20)
                }
            } else { Spacer(); ProgressView(); Spacer() }
        }
        .background(ScreenBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { tab = router.profileTabRequest ?? initialTab; router.profileTabRequest = nil }
    }
}

// MARK: - PLAYER PROFILE (+ INVITED / BLOCKED / UNBLOCKED)

struct PlayerProfileView: View {
    let uid: String
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs
    @Environment(\.dismiss) private var dismiss
    @State private var user: AppUser?
    @State private var loaded = false
    @State private var tab: ProfileTab = .matches
    @State private var showMenu = false
    @State private var showInvite = false
    @State private var report = false

    private var isBlocked: Bool { data.blocked.contains(uid) }

    var body: some View {
        VStack(spacing: 0) {
            HuddlHeader(style: .title("PLAYER"), onBack: { dismiss() }) {
                if uid != session.uid {
                    Button { showMenu = true } label: { Image(systemName: "ellipsis").font(.system(size: 20, weight: .bold)).foregroundStyle(.black).frame(width: 44, height: 44) }
                        .accessibilityLabel("More options")
                }
            }
            if let user {
                ScrollView {
                    VStack(spacing: 14) {
                        if isBlocked {
                            VStack(spacing: 10) {
                                AvatarView(name: user.displayName, size: 80)
                                Text(user.displayName).font(HFont.inter(20, .bold))
                                Text("You blocked this player. They can’t see your games, invite you or message you.").font(HFont.inter(13, .medium))
                                    .foregroundStyle(HColor.secondary).multilineTextAlignment(.center)
                                GhostButton(title: "UNBLOCK") { confirmUnblock(user) }.padding(.horizontal, 40)
                            }.padding(.top, 30)
                        } else if data.blockedBy.contains(uid) {
                            EmptyStateView(symbol: "person.crop.circle.badge.xmark", title: "Profile unavailable", message: "You can’t view this player’s profile.")
                        } else {
                            if uid != session.uid {
                                HStack(spacing: 10) {
                                    OrangeButton(title: "INVITE TO GAME", height: 46) { showInvite = true }
                                    GhostButton(title: "MESSAGE", height: 46) { message() }
                                }
                            }
                            ProfileContent(user: user, isMe: uid == session.uid, tab: $tab)
                        }
                    }
                    .padding(20)
                }
            } else if loaded {
                EmptyStateView(symbol: "person.crop.circle.badge.questionmark", title: "Player not found", message: "This account may have been deleted.")
                Spacer()
            } else { Spacer(); ProgressView(); Spacer() }
        }
        .background(ScreenBackground())
        .task { user = try? await SocialService.user(uid); loaded = true }
        .confirmationDialog("Player options", isPresented: $showMenu) {
            Button("Share profile") { share() }
            Button("Report", role: .destructive) { report = true }
            if isBlocked { Button("Unblock") { if let user { confirmUnblock(user) } } }
            else { Button("Block", role: .destructive) { if let user { confirmBlock(user) } } }
        }
        .sheet(isPresented: $report) { ReportSheet(targetType: "user", targetId: uid) }
        .sheet(isPresented: $showInvite) { if let user { InviteToGameSheet(player: user) } }
    }

    private func message() {
        Task {
            do { router.push(.chat(try await ChatService.directThread(with: uid))) } catch { toasts.error(AppError.message(error)) }
        }
    }

    private func share() {
        guard let u = user else { return }
        let av = UIActivityViewController(activityItems: ["Play with \(u.displayName) (\(u.handle)) on HUDDL — https://huddl.app/u/\(u.username)"], applicationActivities: nil)
        UIApplication.shared.topViewController?.present(av, animated: true)
    }

    private func confirmBlock(_ u: AppUser) {
        dialogs.confirm(ConfirmRequest(symbol: "hand.raised.fill", title: "Block \(u.displayName)?",
            message: "They won’t be able to see your games, invite you or message you. They won’t be notified.", confirmTitle: "BLOCK", destructive: true) {
            Task {
                do { try await SocialService.setBlocked(PlayerRef(u), by: session.uid ?? "", blocked: true); toasts.show("\(u.displayName) is blocked") }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }

    private func confirmUnblock(_ u: AppUser) {
        dialogs.confirm(ConfirmRequest(symbol: "hand.raised.slash", title: "Unblock \(u.displayName)?",
            message: "They’ll be able to see your games, invite you and message you again.", confirmTitle: "UNBLOCK") {
            Task {
                do { try await SocialService.setBlocked(PlayerRef(u), by: session.uid ?? "", blocked: false); toasts.show("\(u.displayName) is unblocked") }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }
}

/// "Invite [name] to…" — only the host's games with open spots.
struct InviteToGameSheet: View {
    let player: AppUser
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @State private var games: [Game] = []
    @State private var loading = true
    @State private var picked: Game?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SheetTitle(title: "Invite \(player.displayName.split(separator: " ").first.map(String.init) ?? player.displayName) to…",
                       subtitle: "Your games with open spots")
            if loading { ProgressView().frame(maxWidth: .infinity).padding(30) }
            else if games.isEmpty {
                EmptyStateView(symbol: "flag", title: "No open games", message: "Host a game first, then invite players to it.",
                               actionTitle: "HOST A GAME", action: { dismiss(); router.cover = .host })
            }
            ScrollView {
                ForEach(games) { g in
                    SheetOptionRow(symbol: g.sport.symbol, title: g.title, subtitle: "\(g.dateLine) · \(g.spotsLeft) spots left") { picked = g }
                }
            }
        }
        .padding(.horizontal, 24).huddlSheet([.medium, .large])
        .task {
            let all = (try? await GameService.hosted(by: session.uid ?? "")) ?? []
            games = all.filter { $0.isJoinable && !$0.isMember(player.uid) }
            loading = false
        }
        .sheet(item: $picked) { g in
            InviteMessageSheet(player: player, game: g) { team, msg in
                Task {
                    do { try await GameService.invite(gameId: g.gid, inviteeId: player.uid, teamId: team, message: msg); toasts.show("Invite sent"); dismiss() }
                    catch { toasts.error(AppError.message(error)) }
                }
            }
        }
    }
}
