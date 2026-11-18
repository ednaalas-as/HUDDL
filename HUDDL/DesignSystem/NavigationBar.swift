import SwiftUI

enum MainTab: Hashable { case home, huddle, chat, profile }

/// Floating frosted navigation bar with the raised orange "+" (NAVIGATION BAR component).
struct HuddlTabBar: View {
    @Binding var selection: MainTab
    var chatBadge = 0
    let onHost: () -> Void
    let onReselect: (MainTab) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            NotchedBarShape()
                .fill(.ultraThinMaterial)
                .overlay(NotchedBarShape().fill(Color.white.opacity(0.35)))
                .overlay(NotchedBarShape().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .frame(height: 68)
                .shadow(color: Color(hex: 0x173B5C, alpha: 0.1), radius: 10, y: 6)
                .padding(.top, 16)

            HStack(spacing: 3) {
                item(.home, label: "HOME") { Image(systemName: "house.fill").font(.system(size: 20)) }
                item(.huddle, label: "HUDDLE") { Image("HuddleIcon").renderingMode(.template).resizable().frame(width: 21, height: 21) }
                Color.clear.frame(width: 70, height: 68)
                item(.chat, label: "CHAT", badge: chatBadge) { Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 18)) }
                item(.profile, label: "PROFILE") { Image(systemName: "person.crop.circle.fill").font(.system(size: 20)) }
            }
            .frame(height: 68)
            .padding(.top, 16)

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onHost()
            }) {
                ZStack {
                    Circle().fill(HGradient.orange)
                        .overlay(Circle().stroke(Color.white.opacity(0.65), lineWidth: 1))
                        .shadow(color: Color(hex: 0xF04420, alpha: 0.22), radius: 6, y: 5)
                        .shadow(color: Color(hex: 0x172F4F, alpha: 0.1), radius: 11, y: 8)
                    Image(systemName: "plus").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)
            }
            .accessibilityLabel("Host a game")
        }
        .frame(maxWidth: 408)
        .frame(height: 92)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func item<I: View>(_ tab: MainTab, label: String, badge: Int = 0, @ViewBuilder icon: () -> I) -> some View {
        let active = selection == tab
        let activeColor = tab == .huddle ? HColor.navOrange : HColor.brandNavy
        Button {
            if active { onReselect(tab) } else {
                UISelectionFeedbackGenerator().selectionChanged()
                selection = tab
            }
        } label: {
            VStack(spacing: active ? 5 : 3) {
                icon()
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 9 ? "9+" : "\(badge)").font(HFont.inter(9, .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                                .background(HColor.accentTag, in: Capsule()).offset(x: 10, y: -6)
                        }
                    }
                Text(label).font(HFont.inter(12, .semibold))
            }
            .foregroundStyle(active ? activeColor : HColor.secondary)
            .frame(maxWidth: 75.5).frame(height: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.capitalized)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// The bar outline from Figma ("Subtract"), 408×68 with the notch for the + button.
struct NotchedBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Original path is drawn in a 436×96 canvas with the bar at (14, 8) → normalise to 408×68.
        let sx = rect.width / 408, sy = rect.height / 68
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + (x - 14) * sx, y: rect.minY + (y - 8) * sy) }
        var path = Path()
        path.move(to: p(388, 8))
        path.addCurve(to: p(422, 42), control1: p(406.778, 8), control2: p(422, 23.2223))
        path.addCurve(to: p(388, 76), control1: p(422, 60.7775), control2: p(406.778, 76))
        path.addLine(to: p(48, 76))
        path.addCurve(to: p(14, 42), control1: p(29.2224, 76), control2: p(14.0002, 60.7775))
        path.addCurve(to: p(48, 8), control1: p(14, 23.2223), control2: p(29.2223, 8))
        path.addLine(to: p(169.65, 8))
        path.addCurve(to: p(183, 25), control1: p(177.61, 8), control2: p(183, 17.0399))
        path.addCurve(to: p(218, 60), control1: p(183, 44.3298), control2: p(198.67, 60))
        path.addCurve(to: p(253, 25), control1: p(237.33, 60), control2: p(253, 44.3298))
        path.addCurve(to: p(266.35, 8), control1: p(253, 17.0399), control2: p(258.39, 8))
        path.closeSubpath()
        return path
    }
}
