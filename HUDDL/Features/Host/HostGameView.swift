import SwiftUI

/// HOST A GAME (+ ERROR / READY / POSTING) → GAME POSTED, and EDIT GAME (→ My game · Saved).
struct HostGameView: View {
    let editingId: String?
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(DialogCenter.self) private var dialogs
    @Environment(\.dismiss) private var dismiss

    @State private var sport: Sport = .volleyball
    @State private var title = ""
    @State private var venue: Venue?
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now)!.rounded(minutes: 30)
    @State private var playersPerTeam = 2
    @State private var custom = false
    @State private var playType: PlayType = .solo
    @State private var inviteOnly = false
    @State private var notes = ""
    @State private var titleError: String?
    @State private var posting = false
    @State private var postedId: String?
    @State private var original: Snapshot?
    @State private var lockedFormat = false

    @State private var sheet: HostSheet?
    enum HostSheet: String, Identifiable { case sport, venue, date, custom; var id: String { rawValue } }

    struct Snapshot: Equatable { var sport: Sport; var title: String; var venueId: String?; var date: Date; var ppt: Int; var playType: PlayType; var inviteOnly: Bool; var notes: String }
    private var current: Snapshot { .init(sport: sport, title: title, venueId: venue?.id, date: date, ppt: playersPerTeam, playType: playType, inviteOnly: inviteOnly, notes: notes) }
    private var isDirty: Bool { original.map { $0 != current } ?? (!title.isEmpty || venue != nil || !notes.isEmpty) }

    var body: some View {
        ZStack {
            if let postedId {
                SuccessScreen(symbol: "flag.checkered", title: "Your game is live!",
                              message: "\(title) is now \(inviteOnly ? "ready — it's invite only, so invite your players" : "on Discover"). We’ll notify you when players apply — you decide who joins.",
                              primaryTitle: "VIEW MY GAME", primary: { dismiss(); router.go(router.tab, .game(postedId), root: false) },
                              secondaryTitle: "INVITE PLAYERS", secondary: { dismiss(); router.go(router.tab, .invitePlayers(postedId), root: false) })
            } else {
                form
            }
            if posting { LoadingOverlay(text: editingId == nil ? "Posting…" : "Saving…") }
        }
        .task { await loadForEdit() }
        .sheet(item: $sheet) { s in sheetView(s) }
        .interactiveDismissDisabled(isDirty)
    }

    private var form: some View {
        VStack(spacing: 0) {
            HuddlHeader(style: .title(editingId == nil ? "HOST A GAME" : "EDIT GAME"), onBack: close)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pickerRow("Sport", value: sport.title, symbol: sport.symbol) { sheet = .sport }
                    LabeledField(label: "Game title", placeholder: "e.g. Saturday 6v6 Open", text: $title, error: titleError, maxLength: 60)
                        .onChange(of: title) { titleError = nil }
                    pickerRow("Venue", value: venue?.name ?? "Choose a court or gym", symbol: "mappin.and.ellipse", placeholder: venue == nil) { sheet = .venue }
                    HStack(spacing: 10) {
                        pickerRow("Date", value: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), symbol: "calendar") { sheet = .date }
                        pickerRow("Time", value: date.formatted(date: .omitted, time: .shortened), symbol: "clock") { sheet = .date }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Format")
                        FlowLayout(spacing: 8) {
                            ForEach(GameFormat.presets, id: \.self) { n in
                                SelectChip(text: "\(n)v\(n)", isOn: !custom && playersPerTeam == n) { setFormat(n, custom: false) }
                            }
                            SelectChip(text: custom ? "Custom · \(playersPerTeam)v\(playersPerTeam)" : "Custom", isOn: custom) {
                                if lockedFormat { toasts.info("Format can’t change once players have joined") } else { sheet = .custom }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Play type")
                        FrostedSegmented(options: [(PlayType.solo, "Solo players"), (.group, "Group play")], selection: $playType)
                        Text(playType == .group ? "Groups apply together and play as one team." : "Players apply one by one.")
                            .font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "Rules")
                        ToggleRow(title: "Fixed teams", subtitle: "Rosters lock when the game starts", isOn: .constant(true), locked: true, onLockedTap: lockedRulesToast)
                        ToggleRow(title: "No substitutes", subtitle: "Dropped spots reopen to applicants", isOn: .constant(true), locked: true, onLockedTap: lockedRulesToast)
                        ToggleRow(title: "Invite only", subtitle: "Hide from Discover, invite players directly", isOn: $inviteOnly)
                    }
                    .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 20)).cardShadow(0.06, radius: 8, y: 4)
                    LabeledField(label: "Notes (optional)", placeholder: "Anything players should know?", text: $notes, axis: .vertical, maxLength: 300)
                }
                .padding(20)
            }
            HStack(spacing: 10) {
                if editingId == nil {
                    GhostButton(title: "INVITE PLAYERS") { submit(thenInvite: true) }
                }
                OrangeButton(title: editingId == nil ? "POST GAME" : "SAVE CHANGES") { submit(thenInvite: false) }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(ScreenBackground())
    }

    private func pickerRow(_ label: String, value: String, symbol: String, placeholder: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: label)
            Button(action: action) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(HColor.brandNavy)
                    Text(value).font(HFont.inter(15, .medium)).foregroundStyle(placeholder ? HColor.placeholder : HColor.darkText).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(HColor.muted)
                }
                .padding(.horizontal, 16).frame(height: 50)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HColor.chipBorder))
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func sheetView(_ s: HostSheet) -> some View {
        switch s {
        case .sport:
            VStack(alignment: .leading, spacing: 4) {
                SheetTitle(title: "Sport")
                ScrollView {
                    ForEach(Sport.hostable) { sp in
                        SheetOptionRow(symbol: sp.symbol, title: sp.title, isSelected: sport == sp) { sport = sp; sheet = nil }
                    }
                }
            }.padding(.horizontal, 24).huddlSheet([.medium])
        case .venue:
            VenuePickerSheet(sport: sport, selected: venue) { venue = $0; sheet = nil }
        case .date:
            VStack(spacing: 12) {
                SheetTitle(title: "Date & time")
                DatePicker("", selection: $date, in: Date().addingTimeInterval(1800)..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical).tint(HColor.orange)
                NavyPillButton(title: "DONE") { sheet = nil }
            }.padding(.horizontal, 24).huddlSheet([.large])
        case .custom:
            CustomFormatSheet(playersPerTeam: playersPerTeam) { n in setFormat(n, custom: true); sheet = nil }
        }
    }

    private func setFormat(_ n: Int, custom c: Bool) {
        if lockedFormat { toasts.info("Format can’t change once players have joined"); return }
        playersPerTeam = n; custom = c
    }

    private func lockedRulesToast() { toasts.info("Fixed teams and no substitutes are always on in HUDDL to keep games fair") }

    private func close() {
        if isDirty {
            dialogs.confirm(ConfirmRequest(symbol: "trash", title: editingId == nil ? "Discard this game?" : "Discard your changes?",
                message: editingId == nil ? "Your game details won’t be saved." : "Your edits won’t be saved.",
                confirmTitle: "DISCARD", cancelTitle: "Keep editing", destructive: true) { dismiss() })
        } else { dismiss() }
    }

    private func loadForEdit() async {
        guard let editingId, let g = try? await GameService.fetch(editingId) else {
            original = nil; return
        }
        sport = g.sport; title = g.title; date = g.startAt; playersPerTeam = g.format.playersPerTeam; custom = g.format.isCustom
        playType = g.playType; inviteOnly = g.inviteOnly; notes = g.notes ?? ""
        venue = Venue(id: g.venueId, name: g.venueName, address: g.venueAddress ?? "", latitude: g.latitude, longitude: g.longitude,
                      geohash: g.geohash, photoURL: g.venuePhotoURL)
        lockedFormat = g.filled > 1
        original = current
    }

    private func submit(thenInvite: Bool) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            titleError = "Add a title so players know what to expect"
            toasts.error("Add a game title to post your game"); return
        }
        guard let venue, let venueId = venue.id else { toasts.error("Choose a venue for your game"); return }
        guard date > Date() else { toasts.error("Pick a time in the future"); return }
        guard let me = session.me else { return }
        posting = true
        Task {
            do {
                if let editingId {
                    var fields: [String: Any] = [
                        "title": t, "sport": sport.rawValue, "venueId": venueId, "venueName": venue.name, "venueAddress": venue.address,
                        "latitude": venue.latitude, "longitude": venue.longitude, "geohash": venue.geohash,
                        "startAt": date.timeIntervalSince1970 * 1000, "notes": notes, "inviteOnly": inviteOnly, "playType": playType.rawValue,
                    ]
                    if !lockedFormat { fields["format"] = ["playersPerTeam": playersPerTeam, "teams": 2, "isCustom": custom] }
                    try await GameService.update(editingId, fields: fields)
                    posting = false
                    toasts.show("My game · Saved")
                    dismiss()
                } else {
                    let game = Game(host: me, title: t, sport: sport, venueId: venueId, venueName: venue.name, venueAddress: venue.address,
                                    venuePhotoURL: venue.photoURL, latitude: venue.latitude, longitude: venue.longitude, geohash: venue.geohash,
                                    startAt: date, notes: notes.isEmpty ? nil : notes,
                                    format: GameFormat(playersPerTeam: playersPerTeam, isCustom: custom), playType: playType,
                                    inviteOnly: inviteOnly, teams: [Team(id: "A", capacity: playersPerTeam, members: [me]), Team(id: "B", capacity: playersPerTeam)],
                                    memberIds: [me.id], spotsLeft: playersPerTeam * 2 - 1, createdAt: Date())
                    let id = try await GameService.create(game)
                    posting = false
                    if thenInvite { dismiss(); router.go(router.tab, .invitePlayers(id), root: false) }
                    else { withAnimation { postedId = id } }
                }
            } catch {
                posting = false
                toasts.error(AppError.message(error))
            }
        }
    }
}

/// Custom format sheet: players per team (stepper, max 6) and fixed 2 teams.
struct CustomFormatSheet: View {
    @State var playersPerTeam: Int
    let onDone: (Int) -> Void
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetTitle(title: "Custom format")
            HStack {
                Text("Players per team").font(HFont.inter(15, .semibold))
                Spacer()
                Button { if playersPerTeam > 1 { playersPerTeam -= 1 } } label: { Image(systemName: "minus.circle.fill").font(.system(size: 28)) }
                Text("\(playersPerTeam)").font(HFont.inter(20, .bold)).frame(width: 34)
                Button {
                    if playersPerTeam < GameFormat.maxPlayersPerTeam { playersPerTeam += 1 } else { toasts.info("Teams can have up to 6 players") }
                } label: { Image(systemName: "plus.circle.fill").font(.system(size: 28)) }
            }
            .foregroundStyle(HColor.brandNavy)
            Button { toasts.info("Custom games use 2 teams") } label: {
                HStack {
                    Text("Number of teams").font(HFont.inter(15, .semibold)).foregroundStyle(HColor.darkText)
                    Spacer()
                    Text("2").font(HFont.inter(20, .bold)).foregroundStyle(HColor.muted)
                    Image(systemName: "lock.fill").foregroundStyle(HColor.muted)
                }
            }.buttonStyle(.plain)
            Text("\(playersPerTeam * 2) players total · \(playersPerTeam)v\(playersPerTeam)")
                .font(HFont.inter(13, .semibold)).foregroundStyle(HColor.accentTag)
            NavyPillButton(title: "USE THIS FORMAT") { onDone(playersPerTeam) }
        }
        .padding(.horizontal, 24).huddlSheet([.height(360)])
    }
}

/// Venue sheet: nearby courts and gyms (curated venues collection).
struct VenuePickerSheet: View {
    let sport: Sport
    let selected: Venue?
    let onPick: (Venue) -> Void
    @Environment(SessionStore.self) private var session
    @State private var venues: [Venue] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SheetTitle(title: "Venue", subtitle: "Courts and gyms near \(session.user?.homeArea?.name ?? "you")")
            if loading { ProgressView().frame(maxWidth: .infinity).padding(30) }
            else if venues.isEmpty {
                EmptyStateView(symbol: "mappin.slash", title: "No venues yet", message: "We couldn’t load venues. Pull to try again later.")
            }
            ScrollView {
                ForEach(sortedVenues) { v in
                    SheetOptionRow(symbol: v.sports.contains(sport) ? "sportscourt.fill" : "mappin", title: v.name,
                                   subtitle: [v.address, distance(v)].compactMap { $0 }.joined(separator: " · "),
                                   isSelected: selected?.id == v.id) { onPick(v) }
                }
            }
        }
        .padding(.horizontal, 24).huddlSheet([.medium, .large])
        .task { venues = (try? await GameService.venues()) ?? []; loading = false }
    }

    private var sortedVenues: [Venue] {
        venues.sorted { ($0.sports.contains(sport) ? 0 : 1, $0.name) < ($1.sports.contains(sport) ? 0 : 1, $1.name) }
    }
    private func distance(_ v: Venue) -> String? {
        guard let a = session.user?.homeArea else { return nil }
        return Geo.format(km: Geo.distanceKm(a.latitude, a.longitude, v.latitude, v.longitude))
    }
}

extension Date {
    func rounded(minutes: Int) -> Date {
        let s = Double(minutes * 60)
        return Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / s).rounded(.up) * s)
    }
}
