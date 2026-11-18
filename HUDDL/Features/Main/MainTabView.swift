import SwiftUI

/// Root tab container: 4 tabs + the floating "+" that presents Host a game.
struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @State private var data = AppData()

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            Group {
                switch router.tab {
                case .home: NavigationStack(path: $router.homePath) { HomeView().huddlRoutes() }
                case .huddle: NavigationStack(path: $router.huddlePath) { HuddleView().huddlRoutes() }
                case .chat: NavigationStack(path: $router.chatPath) { ChatListView().huddlRoutes() }
                case .profile: NavigationStack(path: $router.profilePath) { ProfileView().huddlRoutes() }
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: router.isAtRoot ? 70 : 0) }

            // Main screens show the floating bar; pushed detail screens use their own bottom bars (as in Figma).
            if router.isAtRoot {
                HuddlTabBar(selection: $router.tab, chatBadge: data.unreadChats,
                            onHost: { router.cover = .host },
                            onReselect: { router.popToRoot($0) })
                    .padding(.bottom, -14)
                    .ignoresSafeArea(.keyboard)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: router.isAtRoot)
        .environment(data)
        .fullScreenCover(item: $router.cover) { flow in
            Group {
                switch flow {
                case .host: HostGameView(editingId: nil)
                case .editGame(let id): HostGameView(editingId: id)
                case .compose(let gameId): ComposeMomentsView(gameId: gameId)
                case .apply(let gameId): ApplyView(gameId: gameId)
                }
            }
            .environment(data)
        }
        .task(id: session.uid) {
            if let uid = session.uid { data.start(uid: uid) }
        }
        .onAppear {
            PushService.shared.onOpen = { gameId, postId, _ in router.open(gameId: gameId, postId: postId) }
            Task { _ = await PushService.shared.requestPermission() }
        }
        .onDisappear { data.stop() }
    }
}

// MARK: - Shared game presentation

extension Game {
    var dateLine: String { startAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " · " + startAt.formatted(date: .omitted, time: .shortened) }
    func distanceText(from area: HomeArea?) -> String? {
        guard let area else { return nil }
        return Geo.format(km: Geo.distanceKm(area.latitude, area.longitude, latitude, longitude))
    }
    var shortFormatLine: String {
        [format.label, playType == .group ? "Group play" : "Solo", "Fixed teams"].joined(separator: " · ")
    }
    var allMembers: [PlayerRef] { teams.flatMap(\.members) }
}

/// Status tag shown on cards for the viewer's relation to a game.
struct GameStatusTag: View {
    let game: Game
    let relation: AppData.Relation
    var body: some View {
        switch (game.status, relation) {
        case (.cancelled, _): StatusTag(text: "CANCELLED", kind: .destructive)
        case (.ended, _): StatusTag(text: "ENDED", kind: .muted)
        case (.started, _): StatusTag(text: "STARTED", kind: .muted)
        case (_, .host): StatusTag(text: "HOSTING", kind: .accent)
        case (_, .joined): StatusTag(text: "JOINED", kind: .success)
        case (_, .invited): StatusTag(text: "INVITED YOU", kind: .accent)
        case (_, .pending): StatusTag(text: "PENDING", kind: .navy)
        case (.full, _): StatusTag(text: "FULL", kind: .muted)
        default: StatusTag(text: "OPEN", kind: .success)
        }
    }
}

/// List row (Interested / Not interested / Search / Profile lists) — "Game row" in Figma.
struct GameRow<Action: View>: View {
    let game: Game
    var area: HomeArea?
    let relation: AppData.Relation
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VenueCoverView(sport: game.sport, photoURL: game.venuePhotoURL, showsCaption: false)
                .frame(width: 96, height: 124).clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(game.sport.label).font(HFont.inter(11, .semibold)).tracking(0.8).foregroundStyle(HColor.secondary).padding(.top, 4)
                    Spacer()
                    GameStatusTag(game: game, relation: relation)
                }
                Text(game.title).font(HFont.inter(16, .bold)).foregroundStyle(HColor.darkText).lineLimit(1).padding(.top, 2)
                HStack(spacing: 5) {
                    Image(systemName: "mappin").font(.system(size: 10, weight: .bold)).foregroundStyle(HColor.brandNavy)
                    Text([game.venueName, game.distanceText(from: area)].compactMap { $0 }.joined(separator: " · "))
                        .font(HFont.inter(11, .semibold)).foregroundStyle(.black).lineLimit(1)
                }.padding(.top, 8)
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.system(size: 10, weight: .bold)).foregroundStyle(HColor.brandNavy)
                    Text(game.dateLine).font(HFont.inter(11, .medium)).foregroundStyle(HColor.body)
                }.padding(.top, 5)
                Text(game.shortFormatLine).font(HFont.inter(11, .semibold)).foregroundStyle(HColor.brandNavy).padding(.top, 6)
                HStack(spacing: 6) {
                    AvatarStack(people: game.allMembers.prefix(3).map { ($0.name, $0.photoURL) }, size: 22, overlap: 6)
                    Text("\(game.filled) of \(game.capacity)").font(HFont.inter(11, .semibold)).foregroundStyle(HColor.greyLabel)
                    Spacer()
                    action()
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: HColor.shadow.opacity(0.07), radius: 12, y: 8)
        .contentShape(Rectangle())
    }
}

/// Small navy rectangle button used in rows (APPLY) and its outline variant (APPLIED).
struct RowButton: View {
    let title: String
    var outline = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(HFont.button(13)).tracking(0.5)
                .foregroundStyle(outline ? HColor.brandNavy : .white)
                .padding(.horizontal, 16).frame(minWidth: 88).frame(height: 30)
                .background {
                    if outline { RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.7)).overlay(RoundedRectangle(cornerRadius: 5).stroke(HColor.outline)) }
                    else { RoundedRectangle(cornerRadius: 5).fill(HGradient.navy).shadow(color: HColor.shadow.opacity(0.15), radius: 4, y: 4) }
                }
        }
        .buttonStyle(.plain)
    }
}

/// A one-line player row used in rosters, applicants, search, invite lists.
struct PlayerLine<Trailing: View>: View {
    let player: PlayerRef
    var subtitle: String?
    var isMe = false
    var badge: String?
    var size: CGFloat = 44
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: player.name, photoURL: player.photoURL, size: size)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.name + (isMe ? " (You)" : "")).font(HFont.rounded(15)).foregroundStyle(HColor.darkText).lineLimit(1)
                    if let badge { StatusTag(text: badge, kind: .accent) }
                }
                Text(subtitle ?? "@\(player.username)").font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            trailing()
        }
        .contentShape(Rectangle())
    }
}

extension PlayerLine where Trailing == EmptyView {
    init(player: PlayerRef, subtitle: String? = nil, isMe: Bool = false, badge: String? = nil, size: CGFloat = 44) {
        self.init(player: player, subtitle: subtitle, isMe: isMe, badge: badge, size: size) { EmptyView() }
    }
}

/// Header + scrolling content used by most pushed screens.
struct ScreenScaffold<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HuddlHeader(style: .title(title), onBack: { dismiss() }, trailing: trailing)
            content().frame(maxHeight: .infinity)
        }
        .background(ScreenBackground())
    }
}

extension ScreenScaffold where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}
