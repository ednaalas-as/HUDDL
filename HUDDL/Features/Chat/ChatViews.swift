import SwiftUI
import PhotosUI
import FirebaseFirestore

// MARK: - CHAT (+ GAME CHATS / DIRECT)

struct ChatListView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    enum Filter: Hashable { case all, game, direct }
    @State private var filter: Filter = .all
    @State private var query = ""

    private var uid: String { session.uid ?? "" }
    private var threads: [ChatThread] {
        data.threads
            .filter { filter == .all || (filter == .game ? $0.type == .game : $0.type == .direct) }
            .filter { t in t.type == .game || !(t.other(than: uid).map { data.hiddenUsers().contains($0.id) } ?? false) }
            .filter { query.isEmpty || title($0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HuddlHeader(style: .logo, onBell: { router.push(.notifications) }, onSearch: { router.push(.search) }, hasUnread: data.unreadNotifications > 0)
            FrostedSegmented(options: [(Filter.all, "All"), (.game, "Game chats"), (.direct, "Direct")], selection: $filter)
                .padding(.horizontal, 20).padding(.top, 7)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(HColor.muted)
                TextField("Search chats", text: $query)
            }
            .padding(.horizontal, 16).frame(height: 40).background(Color.white, in: Capsule()).padding(.horizontal, 20).padding(.top, 10)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if threads.isEmpty {
                        EmptyStateView(symbol: "bubble.left.and.bubble.right", title: "No chats yet",
                                       message: filter == .direct ? "Message a player from their profile to start a conversation." : "Join a game and its team chat appears here.",
                                       actionTitle: "FIND A GAME", action: { router.openHuddle(.discover) })
                    }
                    ForEach(threads) { t in
                        Button { router.push(.chat(t.cid)) } label: { row(t) }.buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .background(ScreenBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func title(_ t: ChatThread) -> String { t.type == .game ? t.title : (t.other(than: uid)?.name ?? "Chat") }

    private func row(_ t: ChatThread) -> some View {
        let unread = t.unread[uid] ?? 0
        return HStack(spacing: 12) {
            if t.type == .game {
                ZStack { Circle().fill(HGradient.tint).frame(width: 50, height: 50); Image(systemName: "person.3.fill").foregroundStyle(HColor.brandNavy) }
            } else if let o = t.other(than: uid) {
                AvatarView(name: o.name, photoURL: o.photoURL, size: 50)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title(t)).font(HFont.rounded(15)).foregroundStyle(HColor.darkText).lineLimit(1)
                    if t.readOnly { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(HColor.muted) }
                    Spacer()
                    if let d = t.updatedAt { Text(d.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))).font(HFont.inter(10, .medium)).foregroundStyle(HColor.muted) }
                }
                if t.type == .game {
                    Text("TEAM A + B · \(t.memberIds.count) players").font(HFont.inter(10, .semibold)).tracking(0.5).foregroundStyle(HColor.secondary)
                }
                HStack {
                    Text(t.lastMessage ?? "Say hi 👋").font(HFont.inter(12, unread > 0 ? .bold : .medium))
                        .foregroundStyle(unread > 0 ? HColor.darkText : HColor.secondary).lineLimit(1)
                    Spacer()
                    if unread > 0 {
                        Text("\(unread)").font(HFont.inter(10, .bold)).foregroundStyle(.white).padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                            .background(HColor.accentTag, in: Capsule())
                    }
                }
            }
        }
        .padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 20)).cardShadow(0.06, radius: 8, y: 4)
    }
}

// MARK: - CHAT · [GAME] / DM · [PLAYER] (+ TYPED / SENT / PHOTO / FAILED)

struct ChatThreadView: View {
    let chatId: String
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    struct Outgoing: Identifiable, Equatable { let id = UUID(); var text: String?; var image: UIImage?; var failed = false }

    @State private var thread: ChatThread?
    @State private var loaded = false
    @State private var messages: [ChatMessage] = []
    @State private var pending: [Outgoing] = []
    @State private var draft = ""
    @State private var listeners: [ListenerRegistration] = []
    @State private var showAttach = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var showCamera = false

    private var uid: String { session.uid ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            HuddlHeader(style: .title(headerTitle), onBack: { dismiss() }) {
                if let t = thread {
                    Button {
                        if t.type == .game, let g = t.gameId { router.push(.game(g)) }
                        else if let o = t.other(than: uid) { router.push(.player(o.id)) }
                    } label: { Image(systemName: t.type == .game ? "info.circle" : "person.crop.circle").font(.system(size: 20)).foregroundStyle(.black).frame(width: 44, height: 44) }
                    .accessibilityLabel(t.type == .game ? "Game details" : "View profile")
                }
            }
            if loaded && thread == nil {
                EmptyStateView(symbol: "lock", title: "Chat unavailable", message: "You’re not a member of this chat anymore.")
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(messages) { m in bubble(m).id(m.id) }
                            ForEach(pending) { p in pendingBubble(p).id(p.id) }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count + pending.count) { withAnimation { proxy.scrollTo("bottom") } }
                    .onAppear { proxy.scrollTo("bottom") }
                }
                if thread?.readOnly == true {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("Game ended · chat is read-only")
                        if let g = thread?.gameId { Spacer(); Button("View game") { router.push(.game(g)) }.font(HFont.inter(12, .bold)) }
                    }
                    .font(HFont.inter(12, .semibold)).foregroundStyle(HColor.secondary)
                    .padding(16).frame(maxWidth: .infinity).background(.ultraThinMaterial)
                } else {
                    composer
                }
            }
        }
        .background(ScreenBackground())
        .onAppear {
            listeners = [
                ChatService.listenThread(chatId) { t in thread = t; loaded = true },
                ChatService.listenMessages(chatId) { m in messages = m; Task { await ChatService.markRead(chatId: chatId, uid: uid) } },
            ]
        }
        .onDisappear { listeners.forEach { $0.remove() } }
        .confirmationDialog("Attach", isPresented: $showAttach) {
            Button("Choose photo") { showLibrary = true }
            Button("Take a photo") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true } else { toasts.info("Camera isn’t available on this device") }
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { send(Outgoing(image: img)) }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { send(Outgoing(image: $0)) }.ignoresSafeArea() }
    }

    private var headerTitle: String {
        guard let t = thread else { return "CHAT" }
        return t.type == .game ? t.title.uppercased() : (t.other(than: uid)?.name.uppercased() ?? "CHAT")
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        if m.system {
            Text(m.text ?? "").font(HFont.inter(11, .semibold)).foregroundStyle(HColor.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.8), in: Capsule())
                .frame(maxWidth: .infinity)
        } else {
            let mine = m.senderId == uid
            HStack(alignment: .bottom, spacing: 8) {
                if mine { Spacer(minLength: 50) }
                if !mine, thread?.type == .game {
                    Button { router.push(.player(m.senderId)) } label: { AvatarView(name: m.senderName, size: 28) }.buttonStyle(.plain)
                }
                VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                    if !mine, thread?.type == .game { Text(m.senderName).font(HFont.inter(10, .semibold)).foregroundStyle(HColor.secondary) }
                    content(text: m.text, imageURL: m.imageURL, image: nil, mine: mine)
                    if let d = m.createdAt { Text(d.formatted(date: .omitted, time: .shortened)).font(HFont.inter(9, .medium)).foregroundStyle(HColor.muted) }
                }
                if !mine { Spacer(minLength: 50) }
            }
        }
    }

    private func pendingBubble(_ p: Outgoing) -> some View {
        HStack {
            Spacer(minLength: 50)
            VStack(alignment: .trailing, spacing: 3) {
                content(text: p.text, imageURL: nil, image: p.image, mine: true).opacity(p.failed ? 0.6 : 0.8)
                if p.failed {
                    Button { retry(p) } label: { Label("Not sent · Tap to retry", systemImage: "exclamationmark.circle.fill").font(HFont.inter(10, .semibold)).foregroundStyle(HColor.destructive) }
                } else {
                    Text("Sending…").font(HFont.inter(9, .medium)).foregroundStyle(HColor.muted)
                }
            }
        }
    }

    @ViewBuilder
    private func content(text: String?, imageURL: String?, image: UIImage?, mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: 200, height: 200).clipShape(RoundedRectangle(cornerRadius: 14)) }
            if let imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { HColor.avatarBG }
                    .frame(width: 200, height: 200).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if let text, !text.isEmpty {
                Text(text).font(HFont.inter(14, .medium)).foregroundStyle(mine ? .white : HColor.darkText)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background {
                        if mine { RoundedRectangle(cornerRadius: 18).fill(HGradient.navy) } else { RoundedRectangle(cornerRadius: 18).fill(Color.white) }
                    }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Button { showAttach = true } label: { Image(systemName: "plus.circle.fill").font(.system(size: 28)).foregroundStyle(HColor.brandNavy) }
                .accessibilityLabel("Attach photo")
            TextField("Message…", text: $draft, axis: .vertical).lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 10).background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { toasts.error("Type a message first"); return }
                draft = ""
                send(Outgoing(text: text))
            } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(HColor.orange) }
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial)
    }

    private func send(_ o: Outgoing) {
        pending.append(o)
        deliver(o)
    }

    private func retry(_ o: Outgoing) {
        if let i = pending.firstIndex(of: o) { pending[i].failed = false; deliver(pending[i]) }
    }

    private func deliver(_ o: Outgoing) {
        guard let me = session.me else { return }
        Task {
            do {
                var url: String?
                if let img = o.image { url = try await StorageService.uploadImage(img, folder: .chats, maxDimension: 1200) }
                try await ChatService.send(chatId: chatId, sender: me, text: o.text, imageURL: url)
                pending.removeAll { $0.id == o.id }
            } catch {
                if let i = pending.firstIndex(where: { $0.id == o.id }) { pending[i].failed = true }
            }
        }
    }
}

// MARK: - NOTIFICATION (+ DECLINED / EMPTY)

struct NotificationsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs
    @State private var youreIn: (team: String, gameId: String)?

    private var uid: String { session.uid ?? "" }

    var body: some View {
        ScreenScaffold(title: "NOTIFICATION", trailing: {
            if !data.notifications.isEmpty {
                Button("Clear all") { confirmClear() }.font(HFont.inter(12, .semibold)).foregroundStyle(HColor.brandNavy).padding(.trailing, 6)
            }
        }) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if data.notifications.isEmpty {
                        EmptyStateView(symbol: "bell.slash", title: "You’re all caught up", message: "Invites, applications and game updates will show here.",
                                       actionTitle: "FIND A GAME", action: { router.openHuddle(.discover) })
                    }
                    ForEach(data.notifications) { n in row(n) }
                }
                .padding(20)
            }
        }
        .onAppear {
            let unread = data.notifications.filter { !$0.read && $0.type != .invite }.compactMap(\.id)
            if !unread.isEmpty { Task { await NotificationService.markRead(uid: uid, ids: unread) } }
        }
        .fullScreenCover(isPresented: Binding(get: { youreIn != nil }, set: { if !$0 { youreIn = nil } })) {
            if let y = youreIn {
                SuccessScreen(symbol: "person.3.fill", title: "You’re on Team \(y.team)!", message: "Your spot is locked in. Say hi to your team.",
                              primaryTitle: "OPEN TEAM CHAT", primary: { youreIn = nil; router.push(.chat(ChatService.gameThreadId(y.gameId))) },
                              secondaryTitle: "VIEW GAME", secondary: { youreIn = nil; router.push(.game(y.gameId)) })
            }
        }
    }

    @ViewBuilder
    private func row(_ n: AppNotification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let a = n.actor {
                    Button { router.push(.player(a.id)) } label: { AvatarView(name: a.name, photoURL: a.photoURL, size: 44) }.buttonStyle(.plain)
                } else {
                    ZStack { Circle().fill(HGradient.tint).frame(width: 44, height: 44); Image(systemName: icon(n.type)).foregroundStyle(HColor.brandNavy) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.title).font(HFont.inter(13, .bold)).foregroundStyle(HColor.darkText)
                    Text(n.body).font(HFont.inter(12, .medium)).foregroundStyle(HColor.body)
                    if let d = n.createdAt { Text(d.formatted(.relative(presentation: .named))).font(HFont.inter(10, .medium)).foregroundStyle(HColor.muted) }
                }
                Spacer(minLength: 0)
                if !n.read { Circle().fill(HColor.accentTag).frame(width: 8, height: 8) }
            }
            actions(n)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20)).cardShadow(0.06, radius: 8, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { open(n) }
    }

    @ViewBuilder
    private func actions(_ n: AppNotification) -> some View {
        switch n.type {
        case .invite where !n.resolved:
            HStack { Spacer(); SmallPillButton(title: "DECLINE", kind: .outline) { decline(n) }; SmallPillButton(title: "ACCEPT", kind: .orange) { accept(n) } }
        case .inviteDeclined:
            Text("You declined this invite").font(HFont.inter(11, .semibold)).foregroundStyle(HColor.secondary)
        case .applied:
            HStack { Spacer(); SmallPillButton(title: "REVIEW", kind: .navy) { if let g = n.gameId { router.push(.applicants(g)) } } }
        case .ended:
            HStack { Spacer(); SmallPillButton(title: "SHARE", kind: .orange) { if let g = n.gameId { router.cover = .compose(gameId: g) } } }
        default: EmptyView()
        }
    }

    private func icon(_ t: NotificationKind) -> String {
        switch t {
        case .expired: "clock.arrow.circlepath"; case .ended: "camera.fill"; case .cancelled: "xmark.octagon"; case .full: "person.3.fill"
        case .spotLeft: "flame.fill"; case .result: "trophy.fill"; default: "bell.fill"
        }
    }

    private func open(_ n: AppNotification) {
        if let id = n.id, !n.read { Task { await NotificationService.markRead(uid: uid, ids: [id]) } }
        if let p = n.postId { router.push(.post(p)); return }
        guard let g = n.gameId else { return }
        if n.type == .expired { router.openHuddle(.interested) } else { router.push(.game(g)) }
    }

    private func accept(_ n: AppNotification) {
        guard let g = n.gameId else { return }
        let team = n.teamId ?? "B"
        dialogs.confirm(ConfirmRequest(symbol: "person.badge.plus", title: "Join Team \(team)?",
            message: "Teams are fixed with no substitutes, so please only accept if you can make it.", confirmTitle: "JOIN TEAM \(team)") {
            Task {
                do { try await GameService.respondInvite(gameId: g, accept: true); youreIn = (team, g) }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }

    private func decline(_ n: AppNotification) {
        guard let g = n.gameId else { return }
        dialogs.confirm(ConfirmRequest(symbol: "xmark", title: "Decline invite?", message: "\(n.actor?.name ?? "The host") will be told you can’t make it.",
                                       confirmTitle: "DECLINE", destructive: true) {
            Task {
                do { try await GameService.respondInvite(gameId: g, accept: false); toasts.info("Invite declined") }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }

    private func confirmClear() {
        dialogs.confirm(ConfirmRequest(symbol: "trash", title: "Clear all notifications?",
            message: "Pending invites will still be available in each game’s details.", confirmTitle: "CLEAR ALL", destructive: true) {
            let keep = data.notifications.filter { $0.type == .invite && !$0.resolved }.compactMap(\.id)
            Task {
                do { try await NotificationService.clearAll(uid: uid, keepPendingInvites: keep); toasts.show("Notifications cleared") }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }
}

// MARK: - SEARCH (+ PLAYERS / EMPTY / NO RESULTS)

struct SearchView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    @Environment(\.dismiss) private var dismiss
    enum Tab: Hashable { case games, players }
    @State private var tab: Tab = .games
    @State private var query = ""
    @State private var games: [Game] = []
    @State private var players: [AppUser] = []
    @State private var searching = false
    @AppStorage("huddl.recentSearches") private var recentRaw = ""
    @FocusState private var focused: Bool

    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(.black).frame(width: 40, height: 44) }
                    .accessibilityLabel("Back")
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(HColor.muted)
                    TextField("Search games, venues, players", text: $query).focused($focused).submitLabel(.search)
                        .textInputAutocapitalization(.never).onSubmit { saveRecent() }
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(HColor.muted) }.accessibilityLabel("Clear") }
                }
                .padding(.horizontal, 14).frame(height: 40).background(Color.white, in: RoundedRectangle(cornerRadius: 25))
            }
            .padding(.horizontal, 12).padding(.vertical, 8).background(.ultraThinMaterial)
            if !query.isEmpty {
                FrostedSegmented(options: [(Tab.games, "Games · \(games.count)"), (.players, "Players · \(players.count)")], selection: $tab)
                    .padding(.horizontal, 20).padding(.top, 8)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if query.isEmpty { recentList }
                    else if searching { ProgressView().frame(maxWidth: .infinity).padding(40) }
                    else if tab == .games {
                        if games.isEmpty {
                            EmptyStateView(symbol: "magnifyingglass", title: "No results for “\(query)”", message: "Can’t find the game you want? Host it and let players come to you.",
                                           actionTitle: "HOST A GAME", action: { router.cover = .host })
                        }
                        ForEach(games) { g in
                            GameRow(game: g, area: session.user?.homeArea, relation: data.relation(to: g, uid: session.uid ?? "")) {
                                RowButton(title: "VIEW", outline: true) { router.push(.game(g.gid)) }
                            }
                            .onTapGesture { saveRecent(); router.push(.game(g.gid)) }
                        }
                    } else {
                        if players.isEmpty { EmptyStateView(symbol: "person.crop.circle.badge.questionmark", title: "No players found", message: "Try a different name or @username.") }
                        ForEach(players) { u in
                            Button { saveRecent(); router.push(.player(u.uid)) } label: {
                                PlayerLine(player: PlayerRef(u), subtitle: [u.handle, u.primarySport?.sport.title, u.city].compactMap { $0 }.joined(separator: " · "))
                                    .padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(ScreenBackground())
        .onAppear { focused = true }
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { games = []; players = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            searching = true
            let hidden = data.hiddenUsers()
            async let g = (try? GameService.search(query)) ?? []
            async let p = (try? SocialService.searchPlayers(query)) ?? []
            games = await g.filter { !hidden.contains($0.host.id) }
            players = await p.filter { !hidden.contains($0.uid) && $0.uid != session.uid }
            searching = false
        }
    }

    @ViewBuilder private var recentList: some View {
        if recent.isEmpty {
            EmptyStateView(symbol: "magnifyingglass", title: "Search HUDDL", message: "Find games by title, sport or venue, or look up players by name.")
        } else {
            HStack {
                SectionLabel(text: "Recent searches")
                Button("Clear") { recentRaw = "" }.font(HFont.inter(12, .semibold)).foregroundStyle(HColor.brandNavy)
            }
            ForEach(recent, id: \.self) { r in
                Button { query = r } label: {
                    HStack { Image(systemName: "clock.arrow.circlepath").foregroundStyle(HColor.muted); Text(r).font(HFont.inter(14, .medium)).foregroundStyle(HColor.darkText); Spacer() }
                        .padding(.vertical, 8)
                }.buttonStyle(.plain)
            }
        }
    }

    private func saveRecent() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        recentRaw = ([q] + recent.filter { $0 != q }).prefix(8).joined(separator: "\n")
    }
}
