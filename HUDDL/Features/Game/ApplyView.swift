import SwiftUI

/// GAME DETAILS · APPLY (+ UNCHECKED / GROUP / SENDING) → APPLICATION SENT.
struct ApplyView: View {
    let gameId: String
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var game: Game?
    @State private var teamId = ""
    @State private var joinAs: JoinAs = .solo
    @State private var group: [PlayerRef] = []
    @State private var note = ""
    @State private var committed = false
    @State private var sending = false
    @State private var sent = false
    @State private var showGroup = false

    private var uid: String { session.uid ?? "" }

    var body: some View {
        ZStack {
            if sent, let game {
                SuccessScreen(symbol: "paperplane.fill", title: "Application sent", message:
                    "\(game.host.name) will review it. We’ll notify you the moment you’re accepted — hosts usually reply within a few hours.",
                    badgeText: "PENDING",
                    primaryTitle: "VIEW MY GAMES", primary: { dismiss(); router.openHuddle(.interested) },
                    secondaryTitle: "BACK TO DISCOVER", secondary: { dismiss(); router.openHuddle(.discover) })
            } else {
                form
            }
            if sending { LoadingOverlay(text: "Sending…") }
        }
        .task {
            game = try? await GameService.fetch(gameId)
            if let g = game { teamId = g.teams.first { !$0.isFull }?.id ?? "" }
        }
        .sheet(isPresented: $showGroup) { chooseGroupSheet }
    }

    private var form: some View {
        VStack(spacing: 0) {
            HuddlHeader(style: .title("APPLY"), onBack: { dismiss() })
            if let g = game {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.title).font(HFont.inter(20, .extraBold)).foregroundStyle(HColor.brandNavy)
                            Text("\(g.sport.title) · \(g.venueName) · \(g.dateLine)").font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary)
                        }
                        SectionLabel(text: "Choose a team")
                        HStack(spacing: 10) {
                            ForEach(g.teams) { t in
                                Button {
                                    if t.isFull { toasts.info("Team \(t.id) is full. Pick Team \(t.id == "A" ? "B" : "A") to apply.") }
                                    else { teamId = t.id }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text("TEAM \(t.id)").font(HFont.inter(14, .bold))
                                        Text(t.isFull ? "Full" : "\(t.spotsLeft) spot\(t.spotsLeft == 1 ? "" : "s") left").font(HFont.inter(11, .medium))
                                    }
                                    .foregroundStyle(teamId == t.id ? .white : (t.isFull ? HColor.muted : HColor.brandNavy))
                                    .frame(maxWidth: .infinity).frame(height: 64)
                                    .background {
                                        if teamId == t.id { RoundedRectangle(cornerRadius: 16).fill(HGradient.navy) }
                                        else { RoundedRectangle(cornerRadius: 16).fill(Color.white).overlay(RoundedRectangle(cornerRadius: 16).stroke(HColor.chipBorder)) }
                                    }
                                    .opacity(t.isFull ? 0.55 : 1)
                                }.buttonStyle(.plain)
                                .accessibilityLabel("Team \(t.id), \(t.isFull ? "full" : "\(t.spotsLeft) spots left")")
                            }
                        }
                        if g.playType == .group {
                            SectionLabel(text: "Join as")
                            FrostedSegmented(options: [(JoinAs.solo, "Solo"), (.group, "With my group")], selection: $joinAs)
                            if joinAs == .group {
                                Text("Your group applies together as one fixed team.").font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary)
                                Button { showGroup = true } label: {
                                    HStack {
                                        Image(systemName: "person.2.fill")
                                        Text(group.isEmpty ? "Choose group" : "Me + " + group.map(\.name).joined(separator: ", "))
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(HFont.inter(14, .semibold)).foregroundStyle(HColor.brandNavy)
                                    .padding(.horizontal, 16).frame(height: 50)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(HColor.chipBorder))
                                }.buttonStyle(.plain)
                                if let team = g.teams.first(where: { $0.id == teamId }), groupSize > team.spotsLeft {
                                    Label("Not enough room for your group on Team \(team.id). Your group needs \(groupSize) spots — this team has \(team.spotsLeft).",
                                          systemImage: "exclamationmark.triangle.fill")
                                        .font(HFont.inter(12, .semibold)).foregroundStyle(HColor.destructive)
                                }
                            }
                        }
                        LabeledField(label: "Note to host", placeholder: "Say hi, share your level or position…", text: $note, axis: .vertical, maxLength: 300)
                        CheckBox(isOn: $committed, label: "I can commit to this game. Teams are fixed and there are no substitutes.")
                    }
                    .padding(20)
                }
                OrangeButton(title: "SEND APPLICATION", isEnabled: committed) { submit(g) }
                    .padding(.horizontal, 20).padding(.vertical, 12)
            } else {
                Spacer(); ProgressView(); Spacer()
            }
        }
        .background(ScreenBackground())
    }

    private var groupSize: Int { joinAs == .group ? 1 + group.count : 1 }

    private var chooseGroupSheet: some View {
        GroupPickerSheet(selected: $group, excluding: Set(game?.memberIds ?? []).union([uid]))
    }

    private func submit(_ g: Game) {
        guard !teamId.isEmpty else { toasts.error("Pick a team to apply"); return }
        guard committed else { toasts.error("Tick the commitment box to send your application"); return }
        if joinAs == .group && group.isEmpty { toasts.error("Choose who’s in your group, or apply solo"); return }
        if let team = g.teams.first(where: { $0.id == teamId }), groupSize > team.spotsLeft {
            toasts.error("Your group needs \(groupSize) spots — this team has \(team.spotsLeft)"); return
        }
        sending = true
        Task {
            do {
                try await GameService.apply(.init(gameId: g.gid, teamId: teamId, joinAs: joinAs, groupMemberIds: group.map(\.id),
                                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines), committed: committed))
                try? await GameService.swipe(g.gid, uid: uid, decision: .interested)
                withAnimation { sent = true }
            } catch { toasts.error(AppError.message(error)) }
            sending = false
        }
    }
}

/// "Choose group": pick teammates from players you know (other HUDDL players).
struct GroupPickerSheet: View {
    @Binding var selected: [PlayerRef]
    let excluding: Set<String>
    @Environment(\.dismiss) private var dismiss
    @Environment(AppData.self) private var data
    @State private var players: [AppUser] = []
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetTitle(title: "Choose group", subtitle: "Your group applies together and plays as one fixed team.")
            TextField("Search players", text: $query).padding(12).background(HColor.avatarBG.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            SheetOptionRow(symbol: "person.fill", title: "Just me (solo)", isSelected: selected.isEmpty) { selected = []; dismiss() }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(filtered) { u in
                        let ref = PlayerRef(u)
                        let on = selected.contains { $0.id == u.uid }
                        SheetOptionRow(symbol: on ? "checkmark.circle.fill" : "person.badge.plus", title: "Me + \(u.displayName)",
                                       subtitle: u.handle, isSelected: on) {
                            if on { selected.removeAll { $0.id == u.uid } } else if selected.count < 5 { selected.append(ref) }
                        }
                    }
                }
            }
            NavyPillButton(title: "DONE") { dismiss() }
        }
        .padding(.horizontal, 24).padding(.bottom, 12)
        .huddlSheet([.large])
        .task { players = (try? await SocialService.allPlayers()) ?? [] }
    }

    private var filtered: [AppUser] {
        players.filter { !excluding.contains($0.uid) && !data.hiddenUsers().contains($0.uid) }
            .filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.username.contains(query.lowercased()) }
    }
}
