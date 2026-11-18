import SwiftUI

/// HUDDLE tab: Discover | Interested | Not interested.
struct HuddleView: View {
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            HuddlHeader(style: .logo, onBell: { router.push(.notifications) }, onSearch: { router.push(.search) },
                        hasUnread: data.unreadNotifications > 0)
            FrostedSegmented(options: [(HuddleSegment.discover, "Discover"), (.interested, "Interested"), (.notInterested, "Not interested")],
                             selection: $router.huddleSegment)
                .padding(.horizontal, 20).padding(.top, 7)
            switch router.huddleSegment {
            case .discover: DiscoverView()
            case .interested: SwipeListView(decision: .interested)
            case .notInterested: SwipeListView(decision: .notInterested)
            }
        }
        .background(ScreenBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Discover

@MainActor
@Observable
final class DiscoverModel {
    var deck: [Game] = []
    var loading = true
    var error: String?
    var lastAction: SwipeDecision?

    func load(area: HomeArea, uid: String, data: AppData) async {
        loading = deck.isEmpty
        error = nil
        do {
            let hidden = data.hiddenUsers()
            let games = try await GameService.discover(near: area)
            deck = games
                .filter { $0.host.id != uid && !$0.isMember(uid) && data.swipes[$0.gid] == nil && !hidden.contains($0.host.id) }
                .sorted { $0.startAt < $1.startAt }
        } catch {
            self.error = AppError.message(error)
        }
        loading = false
    }
}

struct DiscoverView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts
    @State private var model = DiscoverModel()
    @State private var drag: CGSize = .zero
    @State private var showArea = false

    private var area: HomeArea { session.user?.homeArea ?? Geo.lucena }

    var body: some View {
        Group {
            if model.loading {
                VStack { Spacer(); ProgressView("Finding games near you…").tint(HColor.brandNavy).font(HFont.inter(13, .semibold)); Spacer() }
            } else if let error = model.error {
                ErrorStateView(message: error) { Task { await reload() } }
            } else if let top = model.deck.first {
                deck(top)
            } else {
                // DISCOVER · EMPTY
                EmptyStateView(symbol: "sparkle.magnifyingglass", title: "You’re all caught up",
                               message: "No more games within 10 km of \(area.name). Try another home area or host your own game.",
                               actionTitle: "HOST A GAME", action: { router.cover = .host },
                               secondaryTitle: "Change home area", secondaryAction: { showArea = true })
                Spacer()
            }
        }
        .task(id: session.user?.homeArea?.geohash) { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showArea) {
            HomeAreaSheet(current: area) { new in
                Task { try? await session.updateProfile(["homeArea": ["name": new.name, "latitude": new.latitude, "longitude": new.longitude, "geohash": new.geohash], "city": new.name]) }
            }
        }
    }

    private func reload() async {
        guard let uid = session.uid else { return }
        await model.load(area: area, uid: uid, data: data)
    }

    @ViewBuilder
    private func deck(_ top: Game) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if model.deck.count > 2 {
                    RoundedRectangle(cornerRadius: HRadius.card).fill(Color.white).opacity(0.45)
                        .padding(.horizontal, 32).offset(y: -26).cardShadow(0.07, radius: 12, y: 8)
                }
                if model.deck.count > 1 {
                    RoundedRectangle(cornerRadius: HRadius.card).fill(Color.white).opacity(0.75)
                        .padding(.horizontal, 16).offset(y: -14).cardShadow(0.07, radius: 12, y: 8)
                }
                SwipeCard(game: top, area: area)
                    .overlay(alignment: .topLeading) { swipeStamp }
                    .offset(drag)
                    .rotationEffect(.degrees(Double(drag.width / 22)))
                    .gesture(DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { v in
                            if v.translation.width > 110 { decide(.interested, top) }
                            else if v.translation.width < -110 { decide(.notInterested, top) }
                            else { withAnimation(.spring) { drag = .zero } }
                        })
                    .onTapGesture { router.push(.game(top.gid)) }
                    .accessibilityAction(named: "Interested") { decide(.interested, top) }
                    .accessibilityAction(named: "Not interested") { decide(.notInterested, top) }
            }
            .padding(.horizontal, 20).padding(.top, 30)

            HStack {
                Text("←  Not interested").foregroundStyle(HColor.secondary)
                Spacer()
                Text("Interested  →").foregroundStyle(HColor.accentTag)
            }
            .font(HFont.inter(11, .semibold)).padding(.horizontal, 28).padding(.top, 14)

            HStack(spacing: 20) {
                Button { decide(.notInterested, top) } label: {
                    Image(systemName: "xmark").font(.system(size: 24, weight: .bold)).foregroundStyle(HColor.secondary)
                        .frame(width: 64, height: 64).background(Circle().fill(.white)).shadow(color: HColor.shadow.opacity(0.14), radius: 5, y: 6)
                }.accessibilityLabel("Not interested").accessibilityIdentifier("discover.pass")
                Button { router.push(.game(top.gid)) } label: {
                    Image(systemName: "info").font(.system(size: 20, weight: .bold)).foregroundStyle(HColor.brandNavy)
                        .frame(width: 48, height: 48).background(Circle().fill(Color.white.opacity(0.85))).shadow(color: HColor.shadow.opacity(0.1), radius: 3, y: 4)
                }.accessibilityLabel("Game details").accessibilityIdentifier("discover.info")
                Button { decide(.interested, top) } label: {
                    Image(systemName: "heart.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 64, height: 64).background(Circle().fill(HGradient.orange))
                        .overlay(Circle().stroke(Color.white.opacity(0.65), lineWidth: 1.5)).shadow(color: HColor.shadow.opacity(0.3), radius: 5, y: 6)
                }.accessibilityLabel("Interested").accessibilityIdentifier("discover.like")
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var swipeStamp: some View {
        if drag.width > 30 {
            StatusTag(text: "INTERESTED", kind: .accent).scaleEffect(1.4).padding(24).opacity(Double(min(1, drag.width / 110)))
        } else if drag.width < -30 {
            StatusTag(text: "NOT INTERESTED", kind: .muted).scaleEffect(1.4).padding(24).opacity(Double(min(1, -drag.width / 110)))
        }
    }

    private func decide(_ decision: SwipeDecision, _ game: Game) {
        guard let uid = session.uid else { return }
        UIImpactFeedbackGenerator(style: decision == .interested ? .medium : .light).impactOccurred()
        withAnimation(.easeIn(duration: 0.22)) { drag = CGSize(width: decision == .interested ? 600 : -600, height: 40) }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            model.deck.removeAll { $0.gid == game.gid }
            drag = .zero
            do {
                try await GameService.swipe(game.gid, uid: uid, decision: decision)
                // DISCOVER · LIKED / PASSED confirmation
                toasts.show(decision == .interested ? "Added to Interested — apply when you’re ready" : "Moved to Not interested", decision == .interested ? .success : .info)
            } catch {
                model.deck.insert(game, at: 0)
                toasts.error(AppError.message(error))
            }
        }
    }
}

/// "Swipe card · …" (634:2127): venue cover, distance, sport, status, title, host, venue, date, chips, roster.
struct SwipeCard: View {
    let game: Game
    let area: HomeArea?
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VenueCoverView(sport: game.sport, photoURL: game.venuePhotoURL).frame(height: 200)
                if let d = game.distanceText(from: area) {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin").font(.system(size: 11, weight: .bold))
                        Text(d).font(HFont.inter(12, .semibold))
                    }
                    .foregroundStyle(HColor.brandNavy).padding(.horizontal, 10).frame(height: 28)
                    .background(.ultraThinMaterial, in: Capsule()).background(Color.white.opacity(0.75), in: Capsule())
                    .padding(14)
                }
            }
            .clipped()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(game.sport.label).font(HFont.inter(15, .semibold)).foregroundStyle(.black)
                    Spacer()
                    StatusTag(text: game.status == .full ? "FULL" : "OPEN", kind: game.status == .full ? .muted : .success)
                }
                Text(game.title).font(HFont.inter(22, .extraBold)).foregroundStyle(HColor.brandNavy).lineLimit(1).minimumScaleFactor(0.8).padding(.top, 6)
                Button { router.push(.player(game.host.id)) } label: {
                    HStack(spacing: 6) {
                        AvatarView(name: game.host.name, photoURL: game.host.photoURL, size: 24)
                        Text("Hosted by").font(HFont.inter(12, .semibold)).foregroundStyle(HColor.greyLabel)
                        Text(game.host.name).font(HFont.inter(12, .semibold)).foregroundStyle(.black)
                    }
                }
                .buttonStyle(.plain).padding(.top, 10)
                MetaLine(symbol: "mappin", text: game.venueName).padding(.top, 12)
                MetaLine(symbol: "calendar", text: game.dateLine, color: HColor.body, weight: .medium).padding(.top, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(game.formatChips, id: \.self) { InfoChip(text: $0) } }
                }
                .padding(.top, 14)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ROSTER").font(HFont.inter(12, .semibold)).tracking(0.8).foregroundStyle(HColor.secondary)
                        Spacer()
                        Text("\(game.filled) of \(game.capacity) spots filled").font(HFont.inter(12, .semibold)).foregroundStyle(HColor.brandNavy)
                    }
                    HStack(spacing: 14) {
                        AvatarStack(people: game.allMembers.prefix(4).map { ($0.name, $0.photoURL) }, size: 40, overlap: 10,
                                    emptySlots: min(1, game.spotsLeft))
                        Text("Tap to see full rosters").font(HFont.inter(11, .semibold)).foregroundStyle(HColor.greyLabel)
                    }
                }
                .padding(14)
                .background(HGradient.tint, in: RoundedRectangle(cornerRadius: 15))
                .padding(.top, 14)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 18)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: HRadius.card, style: .continuous))
        .cardShadow(0.12, radius: 15, y: 12)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe right if interested, left if not. Double tap for details.")
    }
}

// MARK: - Interested / Not interested lists

enum GameSort: String, CaseIterable, Identifiable {
    case soonest = "Soonest", nearest = "Nearest", newest = "Newest", mostSpots = "Most spots left"
    var id: String { rawValue }
}

struct SwipeListView: View {
    let decision: SwipeDecision
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs

    @State private var expired = false
    @State private var sort: GameSort = .soonest
    @State private var games: [Game] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showSort = false

    private var area: HomeArea? { session.user?.homeArea }
    private var uid: String { session.uid ?? "" }

    private var ids: [String] { data.swipes.values.filter { $0.decision == decision && !$0.removed }.compactMap(\.id) }

    private func isExpired(_ g: Game) -> Bool {
        g.hasStarted || g.status == .ended || g.status == .cancelled || g.status == .started ||
        (g.status == .full && !g.isMember(uid))
    }
    private var active: [Game] { sorted(games.filter { !isExpired($0) && !data.hiddenUsers().contains($0.host.id) }) }
    private var expiredGames: [Game] { games.filter { isExpired($0) }.sorted { $0.startAt > $1.startAt } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MiniSegmented(left: "Active · \(active.count)", right: "Expired · \(expiredGames.count)", rightSelected: $expired)
                Spacer()
                if !expired {
                    Button { showSort = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 13, weight: .semibold))
                            Text(sort.rawValue).font(HFont.inter(12, .semibold))
                        }.foregroundStyle(HColor.brandNavy)
                    }
                    .accessibilityLabel("Sort by \(sort.rawValue)")
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)

            if decision == .notInterested && !expired {
                Text("You swiped left on these. Changed your mind? Move one back.")
                    .font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 10)
            }
            if expired {
                Text("Games you \(decision == .interested ? "liked" : "passed on") that started or filled up. Kept for 30 days.")
                    .font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 10)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    if loading && games.isEmpty {
                        ProgressView().padding(.top, 60)
                    } else if let error {
                        ErrorStateView(message: error) { Task { await load() } }
                    } else if (expired ? expiredGames : active).isEmpty {
                        emptyState
                    } else {
                        ForEach(expired ? expiredGames : active) { game in
                            row(game)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
            }
            .refreshable { await load() }
        }
        .task(id: ids.sorted().joined()) { await load() }
        .sheet(isPresented: $showSort) {
            VStack(alignment: .leading, spacing: 4) {
                SheetTitle(title: "Sort by")
                ForEach(GameSort.allCases) { s in
                    SheetOptionRow(symbol: symbol(s), title: s.rawValue, isSelected: sort == s) { sort = s; showSort = false }
                }
                Spacer()
            }
            .padding(.horizontal, 24).huddlSheet([.height(340)])
        }
    }

    @ViewBuilder private var emptyState: some View {
        if expired {
            EmptyStateView(symbol: "clock.arrow.circlepath", title: "Nothing expired",
                           message: "Games that start or fill up will show here for 30 days.")
        } else if decision == .interested {
            EmptyStateView(symbol: "heart", title: "No games yet",
                           message: "Swipe right on games you like and they’ll wait for you here.",
                           actionTitle: "DISCOVER GAMES", action: { router.huddleSegment = .discover })
        } else {
            EmptyStateView(symbol: "hand.thumbsdown", title: "Nothing here",
                           message: "Games you swipe left on land here, in case you change your mind.",
                           actionTitle: "DISCOVER GAMES", action: { router.huddleSegment = .discover })
        }
    }

    @ViewBuilder
    private func row(_ game: Game) -> some View {
        let rel = data.relation(to: game, uid: uid)
        GameRow(game: game, area: area, relation: rel) {
            if expired {
                RowButton(title: "REMOVE", outline: true) { confirmRemove(game) }
            } else if decision == .notInterested {
                RowButton(title: "INTERESTED") { moveBack(game) }
            } else {
                switch rel {
                case .pending: RowButton(title: "APPLIED", outline: true) { confirmWithdraw(game) }
                case .joined, .host: RowButton(title: "VIEW", outline: true) { router.push(.game(game.gid)) }
                case .invited: RowButton(title: "RESPOND") { router.push(.game(game.gid)) }
                default:
                    if game.isJoinable { RowButton(title: "APPLY") { router.cover = .apply(game.gid) } }
                    else { RowButton(title: "FULL", outline: true) { toasts.info("This game is full. We’ll move it to Expired.") } }
                }
            }
        }
        .onTapGesture { router.push(.game(game.gid)) }
        .contextMenu {
            Button("View details", systemImage: "info.circle") { router.push(.game(game.gid)) }
            if decision == .interested && !expired {
                Button("Move to Not interested", systemImage: "hand.thumbsdown") { Task { try? await GameService.swipe(game.gid, uid: uid, decision: .notInterested) } }
            }
        }
    }

    private func symbol(_ s: GameSort) -> String {
        switch s { case .soonest: "clock"; case .nearest: "location"; case .newest: "sparkles"; case .mostSpots: "person.3" }
    }

    private func sorted(_ list: [Game]) -> [Game] {
        switch sort {
        case .soonest: return list.sorted { $0.startAt < $1.startAt }
        case .nearest:
            guard let a = area else { return list }
            return list.sorted { Geo.distanceKm(a.latitude, a.longitude, $0.latitude, $0.longitude) < Geo.distanceKm(a.latitude, a.longitude, $1.latitude, $1.longitude) }
        case .newest:
            return list.sorted { (data.swipes[$0.gid]?.createdAt ?? .distantPast) > (data.swipes[$1.gid]?.createdAt ?? .distantPast) }
        case .mostSpots: return list.sorted { $0.spotsLeft > $1.spotsLeft }
        }
    }

    private func load() async {
        loading = true
        do { games = try await GameService.fetch(ids: ids); error = nil }
        catch { self.error = AppError.message(error) }
        loading = false
    }

    private func moveBack(_ game: Game) {
        Task {
            do {
                try await GameService.swipe(game.gid, uid: uid, decision: .interested)
                toasts.show("Moved to Interested")
            } catch { toasts.error(AppError.message(error)) }
        }
    }

    private func confirmWithdraw(_ game: Game) {
        dialogs.confirm(ConfirmRequest(symbol: "arrow.uturn.backward", title: "Withdraw application?",
            message: "You’ll leave the queue for \(game.title). You can apply again while spots are open.",
            confirmTitle: "WITHDRAW", destructive: true) {
            Task {
                do { try await GameService.withdraw(gameId: game.gid); toasts.show("Application withdrawn") }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }

    private func confirmRemove(_ game: Game) {
        dialogs.confirm(ConfirmRequest(symbol: "trash", title: "Remove from Expired?",
            message: "\(game.title) will be removed from this list.", confirmTitle: "REMOVE", destructive: true) {
            Task {
                do { try await GameService.removeSwipe(game.gid, uid: uid); toasts.show("Removed") }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }
}

/// Frosted two-option sub tabs ("Active · 4 | Expired · 2").
struct MiniSegmented: View {
    let left: String
    let right: String
    @Binding var rightSelected: Bool
    var body: some View {
        HStack(spacing: 0) {
            seg(left, selected: !rightSelected) { rightSelected = false }
            seg(right, selected: rightSelected) { rightSelected = true }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.9)))
    }
    private func seg(_ t: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.spring(response: 0.3)) { action() } } label: {
            Text(t).font(HFont.inter(12, .semibold)).foregroundStyle(selected ? HColor.brandNavy : HColor.secondary)
                .padding(.horizontal, 18).frame(height: 28)
                .background { if selected { Capsule().fill(.white).shadow(color: HColor.shadow.opacity(0.12), radius: 5, y: 3) } }
        }
        .buttonStyle(.plain)
    }
}
