import SwiftUI
import FirebaseFirestore

/// GAME DETAILS (+ UNSAVED / SAVED / JOINED / LEFT / ENDED / MY GAME).
struct GameDetailsView: View {
    let gameId: String
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(AppData.self) private var data
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs
    @Environment(\.dismiss) private var dismiss

    @State private var game: Game?
    @State private var loaded = false
    @State private var saved = false
    @State private var listener: ListenerRegistration?
    @State private var moments: [Post] = []
    @State private var working = false
    @State private var showManage = false
    @State private var showYoureIn: String?

    private var uid: String { session.uid ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            HuddlHeader(style: .title(game.map { $0.host.id == uid ? "MY GAME" : "GAME DETAILS" } ?? "GAME DETAILS"),
                        onBack: { dismiss() }) {
                if let game {
                    if game.host.id == uid && !game.hasEnded && game.status != .cancelled {
                        Button { showManage = true } label: {
                            Image(systemName: "ellipsis").font(.system(size: 20, weight: .bold)).foregroundStyle(.black).frame(width: 44, height: 44)
                        }.accessibilityLabel("Manage game")
                    } else {
                        Button { toggleSave() } label: {
                            Image(systemName: saved ? "bookmark.fill" : "bookmark").font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(saved ? HColor.accentTag : .black).frame(width: 44, height: 44)
                        }.accessibilityLabel(saved ? "Unsave game" : "Save game")
                    }
                }
            }
            if let game {
                ScrollView { content(game).padding(.bottom, 130) }
                    .overlay(alignment: .bottom) { bottomBar(game) }
            } else if loaded {
                EmptyStateView(symbol: "questionmark.circle", title: "Game not found",
                               message: "This game was removed or is no longer available.",
                               actionTitle: "FIND A GAME", action: { router.openHuddle(.discover) })
                Spacer()
            } else {
                Spacer(); ProgressView(); Spacer()
            }
        }
        .background(ScreenBackground())
        .onAppear(perform: subscribe)
        .onDisappear { listener?.remove() }
        .confirmationDialog("Manage game", isPresented: $showManage, titleVisibility: .visible) {
            Button("Edit game") { router.cover = .editGame(gameId) }
            Button("Invite players") { router.push(.invitePlayers(gameId)) }
            Button("Share game") { share() }
            Button("Cancel game", role: .destructive) { confirmCancel() }
        }
        .fullScreenCover(item: $showYoureIn) { team in
            SuccessScreen(symbol: "person.3.fill", title: "You’re on Team \(team)!",
                          message: "See you at \(game?.venueName ?? "the venue") on \(game?.dateLine ?? ""). Say hi to your team.",
                          primaryTitle: "OPEN TEAM CHAT", primary: { showYoureIn = nil; router.push(.chat(ChatService.gameThreadId(gameId))) },
                          secondaryTitle: "VIEW GAME", secondary: { showYoureIn = nil })
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ g: Game) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Cover: the venue photo or a neutral placeholder — never a portrait.
            VenueCoverView(sport: g.sport, photoURL: g.venuePhotoURL)
                .frame(height: 210).clipShape(RoundedRectangle(cornerRadius: HRadius.card, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(g.sport.label).font(HFont.inter(14, .semibold)).foregroundStyle(.black)
                    Spacer()
                    statusTag(g)
                }
                Text(g.title).font(HFont.inter(24, .extraBold)).foregroundStyle(HColor.brandNavy)
                Button { router.push(.player(g.host.id)) } label: {
                    HStack(spacing: 6) {
                        AvatarView(name: g.host.name, photoURL: g.host.photoURL, size: 26)
                        Text("Hosted by").font(HFont.inter(12, .semibold)).foregroundStyle(HColor.greyLabel)
                        Text(g.host.id == uid ? "You" : g.host.name).font(HFont.inter(12, .semibold)).foregroundStyle(.black)
                    }
                }.buttonStyle(.plain)
                MetaLine(symbol: "mappin", text: [g.venueName, g.distanceText(from: session.user?.homeArea)].compactMap { $0 }.joined(separator: " · ")).padding(.top, 4)
                MetaLine(symbol: "calendar", text: g.dateLine + " · \(g.durationMin / 60)h", color: HColor.body, weight: .medium)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(g.formatChips, id: \.self) { InfoChip(text: $0) } }
                }.padding(.top, 6)
                if let notes = g.notes, !notes.isEmpty {
                    Text(notes).font(HFont.inter(13, .medium)).foregroundStyle(HColor.body).padding(.top, 4)
                }
                Label("Teams lock at start. No substitutes — if someone drops, the spot reopens.", systemImage: "lock.fill")
                    .font(HFont.inter(11, .semibold)).foregroundStyle(HColor.secondary).padding(.top, 4)
            }

            if g.hasEnded || g.status == .ended { resultCard(g) }

            if g.host.id == uid && !g.hasEnded && g.status != .cancelled {
                Button { router.push(.applicants(g.gid)) } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                        Text("APPLICANTS").font(HFont.button(14)).tracking(0.5)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(.white).padding(.horizontal, 18).frame(height: 48)
                    .background(HGradient.navy, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            rosters(g)
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }

    @ViewBuilder
    private func statusTag(_ g: Game) -> some View {
        if g.host.id == uid && g.status == .open && !g.hasStarted {
            StatusTag(text: "HOSTING · \(g.spotsLeft) SPOT\(g.spotsLeft == 1 ? "" : "S") LEFT", kind: .accent)
        } else {
            GameStatusTag(game: g, relation: data.relation(to: g, uid: uid))
        }
    }

    private func rosters(_ g: Game) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rosters (\(g.filled) of \(g.capacity))").font(HFont.inter(16, .bold)).foregroundStyle(HColor.darkText)
                Spacer()
                Text("Tap a player to view profile").font(HFont.inter(11, .medium)).foregroundStyle(HColor.secondary)
            }
            ForEach(g.teams) { team in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("TEAM \(team.id)").font(HFont.inter(12, .bold)).tracking(0.8).foregroundStyle(HColor.brandNavy)
                        Spacer()
                        StatusTag(text: team.isFull ? "FULL" : "\(team.spotsLeft) SPOT\(team.spotsLeft == 1 ? "" : "S")", kind: team.isFull ? .muted : .success)
                    }
                    ForEach(team.members) { m in
                        Button { router.push(.player(m.id)) } label: {
                            PlayerLine(player: m, isMe: m.id == uid, badge: m.id == g.host.id ? "HOST" : nil, size: 40)
                        }.buttonStyle(.plain)
                    }
                    ForEach(0..<team.spotsLeft, id: \.self) { _ in
                        Button {
                            if g.host.id == uid { router.push(.invitePlayers(g.gid)) }
                            else if g.isJoinable && data.relation(to: g, uid: uid) == .none { router.cover = .apply(g.gid) }
                        } label: {
                            HStack(spacing: 12) {
                                Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4])).foregroundStyle(HColor.muted).frame(width: 40, height: 40)
                                    .overlay(Image(systemName: "plus").foregroundStyle(HColor.muted))
                                Text(g.host.id == uid ? "Invite a player to Team \(team.id)" : "Open spot").font(HFont.inter(13, .semibold)).foregroundStyle(HColor.secondary)
                                Spacer()
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(HGradient.tint, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    /// RESULT & MOMENTS card (Game details · Ended).
    @ViewBuilder
    private func resultCard(_ g: Game) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Result & moments")
            if let r = g.result {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill").font(.system(size: 22)).foregroundStyle(HColor.accentTag)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Team \(r.winnerTeamId) won · \(r.scoreLine)").font(HFont.inter(15, .bold)).foregroundStyle(HColor.darkText)
                        Text((g.teams.first { $0.id == r.winnerTeamId }?.members.map(\.name) ?? []).joined(separator: ", "))
                            .font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary)
                    }
                }
            } else if g.host.id == uid {
                Button { router.push(.postResult(g.gid)) } label: {
                    Label("Post the result", systemImage: "trophy").font(HFont.inter(14, .semibold)).foregroundStyle(HColor.accentTag)
                }
            } else {
                Text("Waiting for the host to post the result.").font(HFont.inter(13, .medium)).foregroundStyle(HColor.secondary)
            }
            let photos = moments.flatMap(\.media)
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos.prefix(6)) { m in
                            AsyncImage(url: URL(string: m.url)) { $0.resizable().scaledToFill() } placeholder: { HColor.avatarBG }
                                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            HStack {
                Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") · \(moments.count) post\(moments.count == 1 ? "" : "s")")
                    .font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary)
                Spacer()
                if let first = moments.first {
                    Button("See all moments ›") { router.push(.post(first.pid)) }.font(HFont.inter(12, .semibold)).foregroundStyle(HColor.brandNavy)
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .cardShadow(0.07, radius: 10, y: 6)
    }

    // MARK: Bottom bar per state

    @ViewBuilder
    private func bottomBar(_ g: Game) -> some View {
        let rel = data.relation(to: g, uid: uid)
        VStack(spacing: 10) {
            if g.status == .cancelled {
                OrangeButton(title: "FIND SIMILAR") { router.openHuddle(.discover) }
            } else if g.hasEnded || g.status == .ended {
                HStack(spacing: 10) {
                    GhostButton(title: "FIND SIMILAR") { router.openHuddle(.discover) }
                    if g.isMember(uid) { OrangeButton(title: "SHARE MOMENTS") { router.cover = .compose(gameId: g.gid) } }
                }
            } else if rel == .host {
                HStack(spacing: 10) {
                    GhostButton(title: "INVITE PLAYERS") { router.push(.invitePlayers(g.gid)) }
                    OrangeButton(title: "TEAM CHAT") { router.push(.chat(ChatService.gameThreadId(g.gid))) }
                }
            } else if rel == .joined {
                HStack(spacing: 10) {
                    GhostButton(title: "LEAVE GAME", color: HColor.destructive) { confirmLeave(g) }
                    OrangeButton(title: "TEAM CHAT") { router.push(.chat(ChatService.gameThreadId(g.gid))) }
                }
            } else if rel == .invited, let inv = data.invites[g.gid] {
                Text("\(inv.invitedBy.name) invited you to Team \(inv.teamId)").font(HFont.inter(12, .semibold)).foregroundStyle(HColor.accentTag)
                HStack(spacing: 10) {
                    GhostButton(title: "DECLINE") { respond(g, accept: false, team: inv.teamId) }
                    OrangeButton(title: "ACCEPT", isLoading: working) { respond(g, accept: true, team: inv.teamId) }
                }
            } else if rel == .pending {
                GhostButton(title: "WITHDRAW APPLICATION", color: HColor.destructive) { confirmWithdraw(g) }
            } else if g.hasStarted {
                OrangeButton(title: "FIND SIMILAR") { router.openHuddle(.discover) }
            } else if !g.isJoinable {
                OrangeButton(title: "GAME FULL · FIND SIMILAR") { router.openHuddle(.discover) }
            } else {
                OrangeButton(title: "APPLY TO JOIN") { router.cover = .apply(g.gid) }
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: Actions

    private func subscribe() {
        listener?.remove()
        listener = GameService.listen(gameId) { result in
            Task { @MainActor in
                loaded = true
                if case .success(let g) = result {
                    game = g
                    if let g, g.hasEnded || g.status == .ended {
                        moments = (try? await SocialService.posts(forGame: g.gid, viewer: uid)) ?? []
                    }
                } else if case .failure(let e) = result { toasts.error(AppError.message(e)) }
            }
        }
        Task { saved = await GameService.isSaved(gameId, uid: uid) }
    }

    private func toggleSave() {
        saved.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
        let now = saved
        Task {
            do {
                try await GameService.setSaved(gameId, uid: uid, saved: now)
                if now { try? await GameService.swipe(gameId, uid: uid, decision: .interested) }
                toasts.show(now ? "Saved to Interested" : "Removed from saved", now ? .success : .info)
            } catch { saved = !now; toasts.error(AppError.message(error)) }
        }
    }

    private func share() {
        guard let g = game else { return }
        let text = "Join \(g.title) on HUDDL — \(g.sport.title) at \(g.venueName), \(g.dateLine). huddl://game/\(g.gid)"
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.shared.topViewController?.present(av, animated: true)
    }

    private func respond(_ g: Game, accept: Bool, team: String) {
        if accept {
            dialogs.confirm(ConfirmRequest(symbol: "person.badge.plus", title: "Join Team \(team)?",
                message: "Teams are fixed with no substitutes, so please only accept if you can make it.", confirmTitle: "JOIN TEAM \(team)") {
                send(g, accept: true, team: team)
            })
        } else {
            dialogs.confirm(ConfirmRequest(symbol: "xmark", title: "Decline invite?",
                message: "\(data.invites[g.gid]?.invitedBy.name ?? "The host") will be told you can’t make it.", confirmTitle: "DECLINE", destructive: true) {
                send(g, accept: false, team: team)
            })
        }
    }

    private func send(_ g: Game, accept: Bool, team: String) {
        working = true
        Task {
            do {
                try await GameService.respondInvite(gameId: g.gid, accept: accept)
                if accept { showYoureIn = team } else { toasts.info("You declined \(g.title)") }
            } catch { toasts.error(AppError.message(error)) }
            working = false
        }
    }

    private func confirmLeave(_ g: Game) {
        dialogs.confirm(ConfirmRequest(symbol: "rectangle.portrait.and.arrow.right", title: "Leave \(g.title)?",
            message: "Teams are fixed, so your spot reopens to applicants. Leaving within 24 hours of start lowers your reliability score.",
            confirmTitle: "LEAVE GAME", destructive: true) {
            Task {
                do { try await GameService.leave(gameId: g.gid); toasts.show("You left \(g.title)") }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }

    private func confirmWithdraw(_ g: Game) {
        dialogs.confirm(ConfirmRequest(symbol: "arrow.uturn.backward", title: "Withdraw application?",
            message: "You’ll leave the queue for \(g.title). You can apply again while spots are open.", confirmTitle: "WITHDRAW", destructive: true) {
            Task {
                do { try await GameService.withdraw(gameId: g.gid); toasts.show("Application withdrawn") }
                catch { toasts.error(AppError.message(error)) }
            }
        })
    }

    private func confirmCancel() {
        guard let g = game else { return }
        dialogs.confirm(ConfirmRequest(symbol: "xmark.octagon", title: "Cancel \(g.title)?",
            message: "All players and applicants will be notified and the game will be removed from Discover. This can’t be undone.",
            confirmTitle: "CANCEL GAME", cancelTitle: "Keep game", destructive: true) {
            Task {
                do {
                    try await GameService.cancel(g.gid)
                    toasts.show("Game cancelled. Players were notified.")
                } catch { toasts.error(AppError.message(error)) }
            }
        })
    }
}

extension String: @retroactive Identifiable { public var id: String { self } }

extension UIApplication {
    var topViewController: UIViewController? {
        var vc = connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
