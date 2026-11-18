import SwiftUI

// MARK: - Backgrounds

/// White → peach glow background used on auth screens (SIGN UP / SIGN IN).
struct GlowBackground: View {
    var showsAccent = true
    var body: some View {
        ZStack {
            HColor.peachBG
            RadialGradient(colors: [Color(hex: 0xFFC59F, alpha: 0.4), Color(hex: 0xFFC59F, alpha: 0)],
                           center: UnitPoint(x: 0.12, y: 0.06), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(hex: 0xEAF2FF, alpha: 0.55), Color(hex: 0xEAF2FF, alpha: 0)],
                           center: UnitPoint(x: 0.24, y: 0.88), startRadius: 0, endRadius: 500)
            RadialGradient(colors: [Color(hex: 0xFFD9C5, alpha: 0.5), Color(hex: 0xFFD9C5, alpha: 0)],
                           center: UnitPoint(x: 0.77, y: 0.85), startRadius: 0, endRadius: 260)
            if showsAccent {
                GeometryReader { geo in
                    Image("DesignAccent")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width * 2.58, height: geo.size.height * 0.79)
                        .offset(x: -geo.size.width * 0.39, y: geo.size.height * 0.426)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Standard main-screen background (white → light blue).
struct ScreenBackground: View {
    var body: some View { HGradient.screen.ignoresSafeArea() }
}

// MARK: - Brand marks

struct Wordmark: View {
    var height: CGFloat = 51
    var body: some View {
        Image("Wordmark").resizable().scaledToFit().frame(height: height)
            .accessibilityLabel("HUDDL")
    }
}

/// App mark: navy gradient tile with the interlinked "DD".
struct FaviconMark: View {
    var size: CGFloat = 100
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(HGradient.favicon)
            .overlay(Image("DDMark").resizable().scaledToFit()
                .mask(Image("DDMark").resizable().scaledToFit().luminanceToAlpha().brightness(0.4)))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Header

enum HeaderStyle {
    case logo
    case title(String)
}

/// Frosted header used across the app (HEADER component: Default / Variant2 / Variant3).
struct HuddlHeader<Trailing: View>: View {
    let style: HeaderStyle
    var onBack: (() -> Void)?
    var onBell: (() -> Void)?
    var onSearch: (() -> Void)?
    var hasUnread = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            switch style {
            case .logo:
                HStack(spacing: 0) {
                    Wordmark(height: 44).padding(.leading, 14)
                    Spacer()
                    if let onBell {
                        Button(action: onBell) {
                            Image(systemName: hasUnread ? "bell.badge.fill" : "bell.fill")
                                .symbolRenderingMode(hasUnread ? .palette : .monochrome)
                                .foregroundStyle(hasUnread ? HColor.accentTag : .black, .black)
                                .font(.system(size: 26))
                                .frame(width: 46, height: 46)
                        }
                        .accessibilityLabel("Notifications")
                    }
                    if let onSearch {
                        Button(action: onSearch) {
                            Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(.black)
                                .frame(width: 46, height: 46)
                        }
                        .accessibilityLabel("Search")
                    }
                    trailing()
                }
                .padding(.trailing, 14)
            case .title(let title):
                Text(title)
                    .font(HFont.inter(title.count > 14 ? 24 : 30, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .gradientForeground(HGradient.title)
                    .padding(.horizontal, 56)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.black).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Back")
                    }
                    Spacer()
                    trailing()
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(height: 51)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.9))
        .background(Color.white.opacity(0.44).ignoresSafeArea(edges: .top))
    }
}

extension HuddlHeader where Trailing == EmptyView {
    init(style: HeaderStyle, onBack: (() -> Void)? = nil, onBell: (() -> Void)? = nil,
         onSearch: (() -> Void)? = nil, hasUnread: Bool = false) {
        self.init(style: style, onBack: onBack, onBell: onBell, onSearch: onSearch, hasUnread: hasUnread) { EmptyView() }
    }
}

// MARK: - Buttons

/// Navy gradient rectangle button (e.g. SIGN UP, SIGN IN). Radius 5.
struct NavyButton: View {
    let title: String
    var width: CGFloat? = 136
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) } else {
                    Text(title).font(HFont.button(15)).tracking(-0.3).foregroundStyle(.white)
                }
            }
            .frame(width: width, height: 45)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(HGradient.navy, in: RoundedRectangle(cornerRadius: HRadius.navyButton))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .disabled(isLoading || !isEnabled)
    }
}

/// Orange gradient pill CTA (POST, SHARE MOMENTS, SEND APPLICATION…).
struct OrangeButton: View {
    let title: String
    var isLoading = false
    var isEnabled = true
    var height: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) } else {
                    Text(title).font(HFont.button(15)).tracking(0.3).foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity).frame(height: height)
            .background(HGradient.orange, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.65), lineWidth: 1.5))
            .shadow(color: Color(hex: 0xF04420, alpha: 0.22), radius: 8, y: 5)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .disabled(isLoading)
    }
}

/// Navy gradient pill CTA (secondary primary actions like VIEW MY GAMES).
struct NavyPillButton: View {
    let title: String
    var isLoading = false
    var height: CGFloat = 52
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) } else {
                    Text(title).font(HFont.button(15)).tracking(0.3).foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity).frame(height: height)
            .background(HGradient.navy, in: Capsule())
        }
        .disabled(isLoading)
    }
}

/// Ghost secondary button (white, navy text).
struct GhostButton: View {
    let title: String
    var color: Color = HColor.brandNavy
    var height: CGFloat = 52
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(HFont.button(15)).tracking(0.3).foregroundStyle(color)
                .frame(maxWidth: .infinity).frame(height: height)
                .background(Color.white.opacity(0.8), in: Capsule())
                .overlay(Capsule().stroke(HColor.chipBorder, lineWidth: 1))
        }
    }
}

/// Small pill button (e.g. VIEW, JOIN TOO, APPLY, INTERESTED).
struct SmallPillButton: View {
    enum Kind { case orange, navy, outline, destructive }
    let title: String
    var kind: Kind = .navy
    var width: CGFloat? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(HFont.inter(12, .bold)).tracking(0.3)
                .foregroundStyle(kind == .outline ? HColor.brandNavy : (kind == .destructive ? HColor.destructive : .white))
                .padding(.horizontal, 14).frame(height: 30)
                .frame(minWidth: width)
                .background {
                    switch kind {
                    case .orange: Capsule().fill(HGradient.orange)
                    case .navy: Capsule().fill(HGradient.navy)
                    case .outline: Capsule().fill(Color.white.opacity(0.8)).overlay(Capsule().stroke(HColor.chipBorder))
                    case .destructive: Capsule().fill(Color.white).overlay(Capsule().stroke(HColor.destructive.opacity(0.4)))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chips & tags

/// Status tag (OPEN, PENDING, INVITED YOU…).
struct StatusTag: View {
    enum Kind { case success, accent, navy, muted, destructive }
    let text: String
    var kind: Kind = .success
    var body: some View {
        Text(text).font(HFont.inter(10, .semibold)).tracking(0.3)
            .foregroundStyle(fg)
            .padding(.horizontal, 10).frame(height: 22)
            .background(bg, in: Capsule())
    }
    private var fg: Color {
        switch kind {
        case .success: HColor.success
        case .accent: HColor.accentTag
        case .navy: HColor.brandNavy
        case .muted: HColor.secondary
        case .destructive: HColor.destructive
        }
    }
    private var bg: Color {
        switch kind {
        case .success: HColor.successBG
        case .accent: HColor.accentTagBG
        case .navy: HColor.avatarBG
        case .muted: Color(hex: 0xEEF1F4)
        case .destructive: Color(hex: 0xFCE8E6)
        }
    }
}

/// Info chip (2v2 · Group play · Fixed teams · No subs).
struct InfoChip: View {
    let text: String
    var body: some View {
        Text(text).font(HFont.inter(12, .semibold)).foregroundStyle(HColor.brandNavy)
            .padding(.horizontal, 13).frame(height: 30)
            .background(Color.white.opacity(0.7), in: Capsule())
            .overlay(Capsule().stroke(HColor.chipBorder, lineWidth: 1))
    }
}

/// Selectable chip (Format chip On/Off, sports chips).
struct SelectChip: View {
    let text: String
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(HFont.inter(12, .semibold))
                .foregroundStyle(isOn ? .white : HColor.brandNavy)
                .padding(.horizontal, 14).frame(height: 30)
                .background {
                    if isOn { Capsule().fill(HGradient.navy) }
                    else { Capsule().fill(Color.white.opacity(0.7)).overlay(Capsule().stroke(HColor.chipBorder)) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Segmented control (frosted pill)

struct FrostedSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = value }
                } label: {
                    Text(label).font(HFont.inter(13, .semibold))
                        .foregroundStyle(selection == value ? HColor.brandNavy : HColor.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background {
                            if selection == value {
                                Capsule().fill(.white).shadow(color: HColor.shadow.opacity(0.12), radius: 5, y: 3)
                                    .matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
                .accessibilityIdentifier("seg.\(label.components(separatedBy: " ·").first ?? label)")
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1))
        .frame(height: 40)
    }
}

/// Underline-style tabs used inside screens (Active / Expired, Matches / Hosted / Reviews…).
struct TextTabs<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 22) {
            ForEach(options, id: \.0) { value, label in
                Button { withAnimation(.easeInOut(duration: 0.2)) { selection = value } } label: {
                    VStack(spacing: 6) {
                        Text(label).font(HFont.inter(14, .semibold))
                            .foregroundStyle(selection == value ? HColor.brandNavy : HColor.secondary)
                        Capsule().fill(selection == value ? AnyShapeStyle(HGradient.orange) : AnyShapeStyle(Color.clear))
                            .frame(height: 3)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Avatars

/// Player avatar. Shows the approved photo when present, otherwise initials on #E3EEF7.
struct AvatarView: View {
    let name: String
    var photoURL: String?
    var size: CGFloat = 44
    var ring = false

    var body: some View {
        ZStack {
            Circle().fill(HColor.avatarBG)
            if let photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { initials }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: ring ? 2 : 0))
        .accessibilityLabel(name)
    }

    private var initials: some View {
        Text(Self.initials(for: name))
            .font(HFont.rounded(size * 0.38, .semibold))
            .foregroundStyle(HColor.brandNavy)
    }

    static func initials(for name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? parts.last!.first.map(String.init) ?? "" : ""
        return (first + last).uppercased()
    }
}

/// Overlapping avatar stack (roster previews, "joined" activity).
struct AvatarStack: View {
    let people: [(name: String, photo: String?)]
    var size: CGFloat = 40
    var overlap: CGFloat = 10
    var emptySlots = 0
    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(people.enumerated()), id: \.offset) { _, p in
                AvatarView(name: p.name, photoURL: p.photo, size: size, ring: true)
            }
            ForEach(0..<emptySlots, id: \.self) { _ in
                Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    .foregroundStyle(HColor.muted)
                    .background(Circle().fill(Color.white))
                    .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - Venue cover (neutral placeholder — never a portrait)

struct VenueCoverView: View {
    let sport: Sport
    var photoURL: String?
    var showsCaption = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
                if showsCaption {
                    HStack(spacing: 4) {
                        Image(systemName: "photo").font(.system(size: 10))
                        Text("No venue photo yet").font(HFont.inter(10, .semibold))
                    }
                    .foregroundStyle(HColor.secondary)
                    .padding(.horizontal, 9).frame(height: 24)
                    .background(Color.white.opacity(0.7), in: Capsule())
                    .padding(12)
                }
            }
        }
        .clipped()
        .accessibilityLabel("Venue cover")
    }

    private var placeholder: some View {
        ZStack {
            HGradient.venue
            CourtLines(sport: sport)
                .stroke(HColor.brandNavy.opacity(0.14), lineWidth: 1.5)
                .padding(.vertical, 34).padding(.horizontal, 80)
        }
    }
}

/// Court line-art per sport for the venue placeholder.
struct CourtLines: Shape {
    let sport: Sport
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addRect(r)
        switch sport {
        case .tennis, .badminton, .pickleball:
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            let inset = r.height * 0.12
            p.move(to: CGPoint(x: r.minX, y: r.minY + inset)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + inset))
            p.move(to: CGPoint(x: r.minX, y: r.maxY - inset)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - inset))
            let s = r.width * 0.23
            p.move(to: CGPoint(x: r.minX + s, y: r.minY + inset)); p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - inset))
            p.move(to: CGPoint(x: r.maxX - s, y: r.minY + inset)); p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - inset))
            p.move(to: CGPoint(x: r.minX + s, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX - s, y: r.midY))
        case .volleyball:
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            let a = r.width / 6
            p.move(to: CGPoint(x: r.midX - a, y: r.minY)); p.addLine(to: CGPoint(x: r.midX - a, y: r.maxY))
            p.move(to: CGPoint(x: r.midX + a, y: r.minY)); p.addLine(to: CGPoint(x: r.midX + a, y: r.maxY))
        case .basketball, .football:
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addEllipse(in: CGRect(x: r.midX - r.height * 0.18, y: r.midY - r.height * 0.18, width: r.height * 0.36, height: r.height * 0.36))
            p.addRect(CGRect(x: r.minX, y: r.midY - r.height * 0.2, width: r.width * 0.14, height: r.height * 0.4))
            p.addRect(CGRect(x: r.maxX - r.width * 0.14, y: r.midY - r.height * 0.2, width: r.width * 0.14, height: r.height * 0.4))
        case .chess:
            let n = 8
            let side = min(r.width, r.height)
            let board = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
            p = Path(); p.addRect(board)
            for i in 1..<n {
                let t = CGFloat(i) / CGFloat(n)
                p.move(to: CGPoint(x: board.minX + side * t, y: board.minY)); p.addLine(to: CGPoint(x: board.minX + side * t, y: board.maxY))
                p.move(to: CGPoint(x: board.minX, y: board.minY + side * t)); p.addLine(to: CGPoint(x: board.maxX, y: board.minY + side * t))
            }
        case .billiards:
            p = Path(roundedRect: r, cornerRadius: 10)
            for pt in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                p.addEllipse(in: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12))
            }
            p.move(to: CGPoint(x: r.minX + r.width * 0.25, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY))
        }
        return p
    }
}

// MARK: - Cards & sections

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = HRadius.card
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .cardShadow(0.08, radius: 12, y: 8)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(HFont.inter(12, .semibold)).tracking(0.8).foregroundStyle(HColor.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Empty state used by every list.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(HGradient.tint).frame(width: 96, height: 96)
                Image(systemName: symbol).font(.system(size: 36, weight: .semibold)).foregroundStyle(HColor.brandNavy)
            }
            Text(title).font(HFont.inter(18, .bold)).foregroundStyle(HColor.darkText).multilineTextAlignment(.center)
            Text(message).font(HFont.inter(13, .medium)).foregroundStyle(HColor.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            if let actionTitle, let action {
                OrangeButton(title: actionTitle, height: 46, action: action).padding(.horizontal, 60).padding(.top, 6)
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction).font(HFont.inter(13, .semibold)).foregroundStyle(HColor.brandNavy)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Full-screen inline error with retry (network failures, unavailable services).
struct ErrorStateView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        EmptyStateView(symbol: "wifi.exclamationmark", title: "Something went wrong", message: message,
                       actionTitle: "TRY AGAIN", action: retry)
    }
}

/// Form row with chevron used in Settings-like lists.
struct ChevronRow: View {
    let symbol: String
    let title: String
    var value: String?
    var tint: Color = HColor.brandNavy
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint).frame(width: 24)
                Text(title).font(HFont.inter(15, .medium)).foregroundStyle(tint == HColor.destructive ? tint : HColor.darkText)
                Spacer()
                if let value { Text(value).font(HFont.inter(13, .medium)).foregroundStyle(HColor.secondary) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(HColor.muted)
            }
            .padding(.vertical, 13).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Labeled meta line with an icon (venue, date…).
struct MetaLine: View {
    let symbol: String
    let text: String
    var color: Color = .black
    var weight: InterWeight = .semibold
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(HColor.brandNavy).frame(width: 16)
            Text(text).font(HFont.inter(12, weight)).foregroundStyle(color)
        }
    }
}
