import SwiftUI
import PhotosUI
import AVKit
import FirebaseFirestore

// MARK: - Post card (match updates, photo posts, community activity)

struct PostActions {
    var openPost: (Post) -> Void
    var openProfile: (String) -> Void
    var openGame: (String) -> Void
    var openPhoto: (MediaItem) -> Void
    var menu: (Post) -> Void
    var share: (Post) -> Void
}

struct PostCard: View {
    let post: Post
    let actions: PostActions
    @Environment(SessionStore.self) private var session
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts
    @Environment(Router.self) private var router

    var body: some View {
        switch post.type {
        case .hosting: hostingCard
        case .joined: joinedCard
        default: contentCard
        }
    }

    // "[Player] is hosting a game" — preview + VIEW
    private var hostingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            authorRow(subtitle: "is hosting a game · \(timeAgo)")
            Button { if let g = post.gameId { actions.openGame(g) } } label: {
                HStack(spacing: 12) {
                    VenueCoverView(sport: post.gameSport ?? .volleyball, photoURL: nil, showsCaption: false)
                        .frame(width: 78, height: 78).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.gameSport?.label ?? "").font(HFont.inter(10, .semibold)).tracking(0.8).foregroundStyle(HColor.secondary)
                        Text(post.gameTitle ?? "").font(HFont.inter(15, .bold)).foregroundStyle(HColor.darkText).lineLimit(1)
                        Text([post.gameDate.map { $0.formatted(.dateTime.month(.abbreviated).day().hour()) }, post.venueName].compactMap { $0 }.joined(separator: " · "))
                            .font(HFont.inter(11, .medium)).foregroundStyle(HColor.body).lineLimit(1)
                        if let s = post.spotsLeft, s > 0 { StatusTag(text: "\(s) SPOT\(s == 1 ? "" : "S") LEFT", kind: .accent) }
                    }
                    Spacer(minLength: 0)
                    SmallPillButton(title: "VIEW", kind: .navy) { if let g = post.gameId { actions.openGame(g) } }
                }
                .padding(10).background(HGradient.tint, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain)
        }
        .feedCard()
    }

    // "[Player] and N others joined [game]" — JOIN TOO
    private var joinedCard: some View {
        HStack(spacing: 12) {
            AvatarStack(people: post.actors.prefix(3).map { ($0.name, $0.photoURL) }, size: 40, overlap: 14)
                .onTapGesture { if let a = post.actors.first { actions.openProfile(a.id) } }
            VStack(alignment: .leading, spacing: 3) {
                let others = max(0, post.actors.count - 1)
                Text("\(post.actors.first?.name ?? "")\(others > 0 ? " and \(others) other\(others == 1 ? "" : "s")" : "")")
                    .font(HFont.inter(13, .bold)).foregroundStyle(HColor.darkText).lineLimit(2)
                Text("joined \(post.gameTitle ?? "a game")\(post.spotsLeft.map { $0 > 0 ? " · \($0) spots left" : " · full" } ?? "")")
                    .font(HFont.inter(11, .medium)).foregroundStyle(HColor.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if (post.spotsLeft ?? 0) > 0, let g = post.gameId {
                SmallPillButton(title: "JOIN TOO", kind: .orange) { actions.openGame(g) }
            }
        }
        .feedCard()
    }

    // Match updates (result) and photo/video moments
    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            authorRow(subtitle: subtitle)
            if let r = post.result, post.includeResult { MatchCard(result: r, venue: post.venueName, date: post.gameDate, onProfile: actions.openProfile) { if let g = post.gameId { actions.openGame(g) } } }
            if !post.media.isEmpty { MediaGrid(media: post.media, onTap: actions.openPhoto) }
            if let title = post.gameTitle, !post.includeResult, let g = post.gameId {
                Button { actions.openGame(g) } label: {
                    HStack {
                        Image(systemName: "trophy.fill").foregroundStyle(HColor.accentTag)
                        Text(title).font(HFont.inter(12, .semibold)).foregroundStyle(HColor.darkText)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(HColor.muted)
                    }
                    .padding(.horizontal, 10).frame(height: 40).background(HGradient.tint, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            if !post.caption.isEmpty {
                Text(post.caption).font(HFont.inter(13, .medium)).foregroundStyle(HColor.darkText)
                    .onTapGesture { actions.openPost(post) }
            }
            ActionBar(post: post, onComment: { actions.openPost(post) }, onShare: { actions.share(post) })
        }
        .feedCard()
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if !post.tagged.isEmpty { parts.append("with " + post.tagged.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }.joined(separator: ", ")) }
        if post.type == .result { parts.append("posted a result") }
        else if !post.media.isEmpty { parts.append("shared \(post.media.count) \(post.media.count == 1 ? "moment" : "moments")") }
        parts.append(timeAgo)
        return parts.joined(separator: " · ")
    }

    private var timeAgo: String {
        guard let d = post.createdAt else { return "now" }
        return d.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private func authorRow(subtitle: String) -> some View {
        HStack(spacing: 10) {
            Button { actions.openProfile(post.author.id) } label: {
                AvatarView(name: post.author.name, photoURL: post.author.photoURL, size: 44)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Button(post.author.name) { actions.openProfile(post.author.id) }
                    .font(HFont.rounded(15)).foregroundStyle(HColor.darkText).buttonStyle(.plain)
                Text(subtitle).font(HFont.inter(11, .medium)).foregroundStyle(HColor.secondary).lineLimit(1)
            }
            Spacer()
            Button { actions.menu(post) } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(HColor.secondary).frame(width: 32, height: 32)
            }.accessibilityLabel("More options")
        }
    }
}

extension View {
    func feedCard() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: HRadius.card, style: .continuous))
            .cardShadow(0.08, radius: 12, y: 8)
    }
}

/// "Great Match!" card: sport, COMPLETED, teams, VS, score, WINNER.
struct MatchCard: View {
    let result: ResultSnapshot
    var venue: String?
    var date: Date?
    let onProfile: (String) -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(result.sport.label).font(HFont.inter(11, .semibold)).tracking(0.8).foregroundStyle(HColor.secondary)
                Spacer()
                StatusTag(text: "COMPLETED", kind: .success)
            }
            Text("Great Match!").font(HFont.inter(18, .extraBold)).foregroundStyle(HColor.brandNavy)
            HStack(alignment: .top) {
                side(result.teamA, label: "TEAM A", won: result.winnerTeamId == "A")
                VStack(spacing: 4) {
                    Text("VS").font(HFont.inter(14, .extraBold)).foregroundStyle(HColor.accentTag)
                    Text(result.scoreLine).font(HFont.inter(12, .bold)).foregroundStyle(HColor.darkText).multilineTextAlignment(.center)
                }
                .frame(width: 90).padding(.top, 14)
                side(result.teamB, label: "TEAM B", won: result.winnerTeamId == "B")
            }
            if venue != nil || date != nil {
                Text([venue, date?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                    .font(HFont.inter(11, .medium)).foregroundStyle(HColor.secondary)
            }
        }
        .padding(14)
        .background(HGradient.tint, in: RoundedRectangle(cornerRadius: 20))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func side(_ team: [PlayerRef], label: String, won: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: -10) {
                ForEach(team.prefix(3)) { p in
                    AvatarView(name: p.name, photoURL: p.photoURL, size: 44, ring: true).onTapGesture { onProfile(p.id) }
                }
            }
            Text(label).font(HFont.inter(11, .bold)).foregroundStyle(HColor.brandNavy)
            if won { StatusTag(text: "WINNER", kind: .accent) }
        }
        .frame(maxWidth: .infinity)
    }
}

struct MediaGrid: View {
    let media: [MediaItem]
    let onTap: (MediaItem) -> Void
    var body: some View {
        let first = media[0]
        VStack(spacing: 8) {
            tile(first).frame(height: 196)
            if media.count > 1 {
                HStack(spacing: 8) {
                    ForEach(media.dropFirst().prefix(2)) { m in tile(m).frame(height: 96) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if media.count > 3 {
                        Text("+\(media.count - 3)").font(HFont.inter(12, .bold)).foregroundStyle(.white)
                            .padding(6).background(.black.opacity(0.5), in: Capsule()).padding(8)
                    }
                }
            }
        }
    }
    private func tile(_ m: MediaItem) -> some View {
        Button { onTap(m) } label: {
            // The tile takes exactly the size it's given; the photo fills it and is cropped to it.
            // (A scaled-to-fill image sized the tile by itself and spilled over neighbouring posts.)
            Color.clear
                .overlay {
                    if m.type == "video" {
                        Rectangle().fill(HColor.darkText.opacity(0.85))
                        Image(systemName: "play.circle.fill").font(.system(size: 34)).foregroundStyle(.white)
                    } else {
                        AsyncImage(url: URL(string: m.url)) { $0.resizable().scaledToFill() } placeholder: { HColor.avatarBG }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .bottomLeading) {
                if let d = m.duration { Text(Duration.seconds(d).formatted(.time(pattern: .minuteSecond))).font(HFont.inter(11, .semibold)).foregroundStyle(.white).padding(8) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.type == "video" ? "Video" : "Photo")
    }
}

/// Like · Comment · Repost · Share row with live counts.
struct ActionBar: View {
    let post: Post
    let onComment: () -> Void
    let onShare: () -> Void
    @Environment(SessionStore.self) private var session
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts
    @State private var optimistic: Bool?
    @State private var bump = false

    private var liked: Bool { optimistic ?? data.likes.contains(post.pid) }
    private var likeCount: Int {
        let base = max(0, post.likeCount)
        guard let o = optimistic, o != data.likes.contains(post.pid) else { return base }
        return max(0, base + (o ? 1 : -1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 22) {
                Button(action: toggleLike) {
                    Image(systemName: liked ? "heart.fill" : "heart").font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(liked ? HColor.accentTag : HColor.darkText).scaleEffect(bump ? 1.25 : 1)
                }.accessibilityLabel(liked ? "Unlike" : "Like")
                Button(action: onComment) { Image(systemName: "bubble.left").font(.system(size: 21, weight: .semibold)).foregroundStyle(HColor.darkText) }
                    .accessibilityLabel("Comment")
                Button(action: repost) { Image(systemName: "arrow.2.squarepath").font(.system(size: 20, weight: .semibold)).foregroundStyle(HColor.darkText) }
                    .accessibilityLabel("Repost")
                Spacer()
                Button(action: onShare) { Image(systemName: "paperplane").font(.system(size: 20, weight: .semibold)).foregroundStyle(HColor.darkText) }
                    .accessibilityLabel("Share")
            }
            .buttonStyle(.plain)
            Text(summary).font(HFont.inter(11, .semibold)).foregroundStyle(HColor.secondary)
                .onTapGesture(perform: onComment)
        }
    }

    private var summary: String {
        var parts = ["\(likeCount) like\(likeCount == 1 ? "" : "s")", "\(post.commentCount) comment\(post.commentCount == 1 ? "" : "s")"]
        if post.repostCount > 0 { parts.append("\(post.repostCount) repost\(post.repostCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func toggleLike() {
        guard let uid = session.uid else { return }
        let new = !liked
        optimistic = new
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { bump = true }
        Task {
            try? await Task.sleep(for: .milliseconds(150)); bump = false
            do { try await SocialService.setLike(post.pid, uid: uid, liked: new) }
            catch { optimistic = !new; toasts.error(AppError.message(error)) }
            try? await Task.sleep(for: .seconds(1.5)); optimistic = nil
        }
    }

    private func repost() {
        Task {
            do {
                try await SocialService.repost(post.pid)
                toasts.show("Reposted to your profile")
            } catch { toasts.error(AppError.message(error)) }
        }
    }
}

// MARK: - Shared post interactions (menu / share / report / photo viewer)

struct PostInteractions: ViewModifier {
    @Binding var menuPost: Post?
    @Binding var sharePost: Post?
    @Binding var reportPost: Post?
    @Binding var photo: MediaItem?
    var onHidden: ((Post) -> Void)?
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Post options", isPresented: Binding(get: { menuPost != nil }, set: { if !$0 { menuPost = nil } }), presenting: menuPost) { p in
                Button("Report post", role: .destructive) { reportPost = p }
                if p.author.id != session.uid { Button("Hide post") { hide(p) } }
                Button("Copy link") { copy(p) }
            }
            .sheet(item: $sharePost) { p in
                VStack(alignment: .leading, spacing: 6) {
                    SheetTitle(title: "Share")
                    SheetOptionRow(symbol: "link", title: "Copy link") { copy(p); sharePost = nil }
                    SheetOptionRow(symbol: "bubble.left.and.bubble.right", title: "Send in a HUDDL chat") { sharePost = nil; router.go(.chat) }
                    SheetOptionRow(symbol: "square.and.arrow.up", title: "More options") {
                        sharePost = nil
                        let av = UIActivityViewController(activityItems: [link(p)], applicationActivities: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { UIApplication.shared.topViewController?.present(av, animated: true) }
                    }
                    Spacer()
                }.padding(.horizontal, 24).huddlSheet([.height(300)])
            }
            .sheet(item: $reportPost) { p in ReportSheet(targetType: "post", targetId: p.pid) }
            .fullScreenCover(item: $photo) { m in PhotoViewer(item: m) }
    }

    private func link(_ p: Post) -> String { "https://huddl.app/p/\(p.pid)" }
    private func copy(_ p: Post) { UIPasteboard.general.string = link(p); toasts.show("Link copied") }
    private func hide(_ p: Post) {
        guard let uid = session.uid else { return }
        Task {
            do { try await SocialService.hide(p.pid, uid: uid, hidden: true); onHidden?(p) }
            catch { toasts.error(AppError.message(error)) }
        }
    }
}

struct ReportSheet: View {
    let targetType: String
    let targetId: String
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var sent = false
    @State private var sending = false
    private let reasons = ["Spam or misleading", "Harassment or bullying", "Inappropriate content", "Fake profile or impersonation", "Something else"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if sent {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 44)).foregroundStyle(HColor.success)
                    Text("Thanks for letting us know").font(HFont.inter(18, .bold)).foregroundStyle(HColor.darkText)
                    Text("Our team will review it within 24 hours. Your report is anonymous.").font(HFont.inter(13, .medium))
                        .foregroundStyle(HColor.secondary).multilineTextAlignment(.center)
                    NavyPillButton(title: "DONE") { dismiss() }.padding(.top, 8)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                SheetTitle(title: "Report \(targetType == "post" ? "post" : "player")", subtitle: "Why are you reporting this?")
                ForEach(reasons, id: \.self) { r in
                    SheetOptionRow(symbol: "flag", title: r, isDisabled: sending) { send(r) }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 24).huddlSheet([.medium])
    }

    private func send(_ reason: String) {
        guard let uid = session.uid else { return }
        sending = true
        Task {
            try? await SocialService.report(reporter: uid, targetType: targetType, targetId: targetId, reason: reason)
            withAnimation { sent = true }
            sending = false
        }
    }
}

struct PhotoViewer: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if item.type == "video", let url = URL(string: item.url) {
                VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea()
            } else {
                // Centered in the screen; only the close button sits in the corner.
                AsyncImage(url: URL(string: item.url)) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(scale)
                    .gesture(MagnificationGesture().onChanged { scale = max(1, $0) }.onEnded { _ in withAnimation { scale = 1 } })
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .padding()
            .accessibilityLabel("Close")
        }
        .gesture(DragGesture().onEnded { if $0.translation.height > 120 { dismiss() } })
    }
}


// MARK: - Post detail

struct PostDetailView: View {
    let postId: String
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @State private var post: Post?
    @State private var loaded = false
    @State private var comments: [Comment] = []
    @State private var draft = ""
    @State private var listeners: [ListenerRegistration] = []
    @State private var menuPost: Post?
    @State private var sharePost: Post?
    @State private var reportPost: Post?
    @State private var photo: MediaItem?
    @FocusState private var composing: Bool

    var body: some View {
        ScreenScaffold(title: "POST") {
            if let post {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            PostCard(post: post, actions: actions)
                            Text("Comments").font(HFont.inter(15, .bold)).foregroundStyle(HColor.darkText).padding(.top, 6)
                            if comments.isEmpty {
                                Text("No comments yet. Start the conversation!").font(HFont.inter(13, .medium)).foregroundStyle(HColor.secondary)
                            }
                            ForEach(comments) { c in
                                HStack(alignment: .top, spacing: 10) {
                                    Button { router.push(.player(c.author.id)) } label: { AvatarView(name: c.author.name, photoURL: c.author.photoURL, size: 34) }.buttonStyle(.plain)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(c.author.name).font(HFont.rounded(13)).foregroundStyle(HColor.darkText)
                                        Text(c.text).font(HFont.inter(13, .medium)).foregroundStyle(HColor.body)
                                        if let d = c.createdAt { Text(d.formatted(.relative(presentation: .named))).font(HFont.inter(10, .medium)).foregroundStyle(HColor.muted) }
                                    }
                                }.id(c.id)
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: comments.count) { if let last = comments.last?.id { withAnimation { proxy.scrollTo(last, anchor: .bottom) } } }
                }
                composer
            } else if loaded {
                EmptyStateView(symbol: "eye.slash", title: "Post unavailable", message: "This post was removed or isn’t shared with you.")
                Spacer()
            } else { Spacer(); ProgressView(); Spacer() }
        }
        .modifier(PostInteractions(menuPost: $menuPost, sharePost: $sharePost, reportPost: $reportPost, photo: $photo,
                                   onHidden: { _ in toasts.info("Post hidden — you’ll see fewer posts like this") }))
        .onAppear {
            listeners = [
                SocialService.listenPost(postId) { p in post = p; loaded = true },
                SocialService.listenComments(postId) { comments = $0 },
            ]
        }
        .onDisappear { listeners.forEach { $0.remove() } }
    }

    private var actions: PostActions {
        PostActions(openPost: { _ in composing = true }, openProfile: { router.push(.player($0)) }, openGame: { router.push(.game($0)) },
                    openPhoto: { photo = $0 }, menu: { menuPost = $0 }, share: { sharePost = $0 })
    }

    private var composer: some View {
        HStack(spacing: 10) {
            AvatarView(name: session.user?.displayName ?? "", photoURL: session.user?.photoURL, size: 34)
            TextField("Add a comment…", text: $draft, axis: .vertical).lineLimit(1...4).focused($composing)
                .padding(.horizontal, 14).padding(.vertical, 10).background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(HColor.orange)
            }.accessibilityLabel("Send comment")
        }
        .padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { toasts.error("Type a message first"); return }
        guard let me = session.me else { return }
        draft = ""
        Task {
            do { try await SocialService.addComment(postId, author: me, text: text) }
            catch { draft = text; toasts.error(AppError.message(error)) }
        }
    }
}

