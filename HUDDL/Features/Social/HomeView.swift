import SwiftUI
import PhotosUI
import FirebaseFirestore

/// HOME (NAVIGATION PAGE) + NEW POST / REPOSTED / POST HIDDEN states.
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts

    @State private var posts: [Post] = []
    @State private var loading = true
    @State private var error: String?
    @State private var listener: ListenerRegistration?
    @State private var justHidden: Post?
    @State private var menuPost: Post?
    @State private var sharePost: Post?
    @State private var reportPost: Post?
    @State private var photo: MediaItem?

    private var visible: [Post] {
        let hiddenUsers = data.hiddenUsers()
        return posts.filter { !data.hiddenPosts.contains($0.pid) && !hiddenUsers.contains($0.author.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HuddlHeader(style: .logo, onBell: { router.push(.notifications) }, onSearch: { router.push(.search) },
                        hasUnread: data.unreadNotifications > 0)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        Color.clear.frame(height: 0).id("top")
                        if loading && posts.isEmpty {
                            ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: HRadius.card).fill(Color.white).frame(height: 220).redacted(reason: .placeholder) }
                        } else if let error, posts.isEmpty {
                            ErrorStateView(message: error) { subscribe() }
                        } else if visible.isEmpty {
                            EmptyStateView(symbol: "sportscourt", title: "Your feed is quiet",
                                           message: "Join or host a game — results, moments and community activity show up here.",
                                           actionTitle: "FIND A GAME", action: { router.openHuddle(.discover) })
                        } else {
                            ForEach(visible) { post in
                                PostCard(post: post, actions: actions)
                                    .onTapGesture { if post.type == .postGame || post.type == .result { router.push(.post(post.pid)) } }
                            }
                            if let h = justHidden {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Post hidden").font(HFont.inter(14, .bold))
                                        Text("You’ll see fewer match updates like this.").font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary)
                                    }
                                    Spacer()
                                    Button("Undo") { undoHide(h) }.font(HFont.inter(13, .bold)).foregroundStyle(HColor.accentTag)
                                }
                                .feedCard()
                            }
                            VStack(spacing: 6) {
                                Image(systemName: "checkmark.circle").font(.system(size: 26)).foregroundStyle(HColor.success)
                                Text("You’re all caught up").font(HFont.inter(14, .bold)).foregroundStyle(HColor.darkText)
                                Button("Find a game to play next") { router.openHuddle(.discover) }
                                    .font(HFont.inter(12, .semibold)).foregroundStyle(HColor.brandNavy)
                            }
                            .padding(.vertical, 24)
                        }
                    }
                    .padding(.horizontal, 11).padding(.top, 10)
                }
                .refreshable { subscribe(); try? await Task.sleep(for: .milliseconds(600)) }
                .onChange(of: router.homeRefreshToken) { withAnimation { proxy.scrollTo("top") } }
            }
        }
        .background(ScreenBackground())
        .toolbar(.hidden, for: .navigationBar)
        .modifier(PostInteractions(menuPost: $menuPost, sharePost: $sharePost, reportPost: $reportPost, photo: $photo,
                                   onHidden: { p in withAnimation { justHidden = p } }))
        .onAppear { if listener == nil { subscribe() } }
        .onDisappear { listener?.remove(); listener = nil }
    }

    private var actions: PostActions {
        PostActions(openPost: { router.push(.post($0.pid)) }, openProfile: { router.push(.player($0)) },
                    openGame: { router.push(.game($0)) }, openPhoto: { photo = $0 },
                    menu: { menuPost = $0 }, share: { sharePost = $0 })
    }

    private func subscribe() {
        guard let uid = session.uid else { return }
        listener?.remove()
        listener = SocialService.listenFeed(uid: uid) { result in
            loading = false
            switch result {
            case .success(let p): posts = p; error = nil
            case .failure(let e): error = AppError.message(e)
            }
        }
    }

    private func undoHide(_ p: Post) {
        guard let uid = session.uid else { return }
        Task { try? await SocialService.hide(p.pid, uid: uid, hidden: false); withAnimation { justHidden = nil } }
    }
}

// MARK: - POST-GAME · COMPOSE (empty / filled / posting)

struct PickedMedia: Identifiable {
    let id = UUID()
    var image: UIImage?
    var videoURL: URL?
    var duration: Double?
}

struct ComposeMomentsView: View {
    let gameId: String
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs
    @Environment(\.dismiss) private var dismiss

    @State private var game: Game?
    @State private var media: [PickedMedia] = []
    @State private var caption = ""
    @State private var tagged: Set<String> = []
    @State private var includeResult = true
    @State private var audience: PostAudience = .everyone
    @State private var showAdd = false
    @State private var showTags = false
    @State private var showAudience = false
    @State private var posting = false
    @State private var viewing: PickedMedia?

    private var isEmpty: Bool { media.isEmpty && caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HuddlHeader(style: .title("SHARE MOMENTS"), onBack: back)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let g = game {
                            HStack(spacing: 10) {
                                VenueCoverView(sport: g.sport, photoURL: g.venuePhotoURL, showsCaption: false).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.title).font(HFont.inter(14, .bold)).foregroundStyle(HColor.darkText)
                                    Text(["Ended", g.result.map { "Team \($0.winnerTeamId) won \($0.scoreLine)" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(HFont.inter(11, .medium)).foregroundStyle(HColor.secondary)
                                }
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(HGradient.tint, in: RoundedRectangle(cornerRadius: 16))
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button { showAdd = true } label: {
                                    VStack(spacing: 4) { Image(systemName: "plus"); Text("Add").font(HFont.inter(12, .semibold)) }
                                        .foregroundStyle(HColor.brandNavy).frame(width: 96, height: 96)
                                        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(HColor.muted))
                                }.accessibilityLabel("Add photos or videos")
                                ForEach(media) { m in
                                    ZStack(alignment: .topTrailing) {
                                        Group {
                                            if let img = m.image { Image(uiImage: img).resizable().scaledToFill() }
                                            else { ZStack { HColor.darkText; Image(systemName: "play.fill").foregroundStyle(.white) } }
                                        }
                                        .frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(alignment: .bottomLeading) {
                                            if let d = m.duration { Text(Duration.seconds(d).formatted(.time(pattern: .minuteSecond))).font(HFont.inter(10, .bold)).foregroundStyle(.white).padding(6) }
                                        }
                                        .onTapGesture { viewing = m }
                                        Button { media.removeAll { $0.id == m.id } } label: {
                                            Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .black.opacity(0.55))
                                        }.padding(4).accessibilityLabel("Remove")
                                    }
                                }
                            }
                        }
                        TextField("Write a caption…", text: $caption, axis: .vertical).lineLimit(3...8)
                            .font(HFont.inter(15, .medium)).padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HColor.chipBorder))
                        ChevronRow(symbol: "person.crop.circle.badge.plus", title: "Tag players from this game",
                                   value: tagged.isEmpty ? nil : "\(tagged.count) tagged") { showTags = true }
                        ToggleRow(title: "Include match result", subtitle: game?.result == nil ? "No result posted yet" : nil, isOn: $includeResult)
                        ChevronRow(symbol: "eye", title: "Who can see this", value: audience.title) { showAudience = true }
                        Text("Your post appears on the Home feed, your profile and the game’s Moments.")
                            .font(HFont.inter(11, .medium)).foregroundStyle(HColor.secondary)
                    }
                    .padding(20)
                }
                OrangeButton(title: "POST", isEnabled: !isEmpty) { post() }.padding(.horizontal, 20).padding(.vertical, 12)
            }
            .background(ScreenBackground())
            if posting { LoadingOverlay(text: "Posting…") }
        }
        .task { game = try? await GameService.fetch(gameId) }
        .sheet(isPresented: $showAdd) { MediaPickerSheet { media += $0 } }
        .sheet(isPresented: $showTags) { tagSheet }
        .sheet(isPresented: $showAudience) {
            VStack(alignment: .leading, spacing: 4) {
                SheetTitle(title: "Who can see this")
                ForEach(PostAudience.allCases) { a in
                    SheetOptionRow(symbol: a == .everyone ? "globe" : a == .gamePlayers ? "person.3" : "lock", title: a.title, isSelected: audience == a) { audience = a; showAudience = false }
                }
                Spacer()
            }.padding(.horizontal, 24).huddlSheet([.height(300)])
        }
        .fullScreenCover(item: $viewing) { m in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let img = m.image { Image(uiImage: img).resizable().scaledToFit() }
                Button { viewing = nil } label: { Image(systemName: "xmark").foregroundStyle(.white).padding(14) }
            }
        }
    }

    private var tagSheet: some View {
        VStack(alignment: .leading, spacing: 4) {
            SheetTitle(title: "Tag players", subtitle: "Only players from \(game?.title ?? "this game") can be tagged")
            ScrollView {
                ForEach((game?.allMembers ?? []).filter { $0.id != session.uid }) { p in
                    SheetOptionRow(symbol: "person.fill", title: p.name, subtitle: "@\(p.username)", isSelected: tagged.contains(p.id)) {
                        if tagged.contains(p.id) { tagged.remove(p.id) } else { tagged.insert(p.id) }
                    }
                }
            }
            NavyPillButton(title: "DONE") { showTags = false }
        }.padding(.horizontal, 24).padding(.bottom, 12).huddlSheet([.medium, .large])
    }

    private func back() {
        if isEmpty { dismiss(); return }
        dialogs.confirm(ConfirmRequest(symbol: "trash", title: "Discard this post?", message: "Your photos and caption won’t be saved.",
                                       confirmTitle: "DISCARD", cancelTitle: "Keep editing", destructive: true) { dismiss() })
    }

    private func post() {
        if isEmpty { toasts.error("Add a photo, video or caption to post"); return }
        posting = true
        Task {
            do {
                var items: [MediaItem] = []
                for m in media {
                    if let img = m.image { items.append(MediaItem(url: try await StorageService.uploadImage(img, folder: .posts), type: "photo")) }
                    else if let url = m.videoURL { items.append(MediaItem(url: try await StorageService.uploadVideo(at: url), type: "video", duration: m.duration)) }
                }
                _ = try await SocialService.createMomentsPost(gameId: gameId, caption: caption.trimmingCharacters(in: .whitespacesAndNewlines), media: items,
                                                             taggedIds: Array(tagged), includeResult: includeResult && game?.result != nil, audience: audience)
                posting = false
                dismiss()
                router.showHomeWithNewPost()
                toasts.show("Your post is live on the Home feed")
            } catch {
                posting = false
                toasts.error(AppError.message(error))
            }
        }
    }
}

/// "Add media" sheet: Choose photos & videos / Take a photo or video.
struct MediaPickerSheet: View {
    let onPick: ([PickedMedia]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @State private var items: [PhotosPickerItem] = []
    @State private var camera = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetTitle(title: "Add media")
            PhotosPicker(selection: $items, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
                HStack(spacing: 14) {
                    ZStack { Circle().fill(HColor.avatarBG).frame(width: 40, height: 40); Image(systemName: "photo.on.rectangle").foregroundStyle(HColor.brandNavy) }
                    Text("Choose photos & videos").font(HFont.inter(15, .semibold)).foregroundStyle(HColor.darkText)
                    Spacer()
                }.padding(.vertical, 8)
            }
            SheetOptionRow(symbol: "camera.fill", title: "Take a photo or video") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { toasts.info("Camera isn’t available on this device") }
            }
            Spacer()
        }
        .padding(.horizontal, 24).huddlSheet([.height(240)])
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            Task {
                var out: [PickedMedia] = []
                for item in picked {
                    if let movie = try? await item.loadTransferable(type: MovieFile.self) {
                        out.append(PickedMedia(videoURL: movie.url, duration: movie.duration))
                    } else if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        out.append(PickedMedia(image: img))
                    }
                }
                if out.isEmpty { toasts.error("Couldn’t load those files") } else { onPick(out) }
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker(allowsVideo: true, onImage: { onPick([PickedMedia(image: $0)]); dismiss() },
                         onVideo: { onPick([PickedMedia(videoURL: $0)]); dismiss() }).ignoresSafeArea()
        }
    }
}

struct MovieFile: Transferable {
    let url: URL
    var duration: Double?
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return MovieFile(url: dest)
        }
    }
}
