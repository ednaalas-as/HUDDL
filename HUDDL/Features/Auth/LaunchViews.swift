import SwiftUI

// MARK: - Splash (SPLASH SCREEN 2:2)

struct SplashView: View {
    @State private var appear = false
    var body: some View {
        ZStack {
            HGradient.splash.ignoresSafeArea()
            FaviconMark(size: 100)
                .scaleEffect(appear ? 1 : 0.85)
                .opacity(appear ? 1 : 0)
            VStack(spacing: 2) {
                Spacer()
                Wordmark(height: 27)
                Text("Match Up. Match On.").font(HFont.inter(12, .semibold)).foregroundStyle(HColor.orLabel)
            }
            .padding(.bottom, 50)
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HUDDL. Match Up. Match On.")
    }
}

// MARK: - Onboarding (ONBOARDING SCREEN 1–3)

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [(image: String, title: String, body: String)] = [
        ("Onboarding1", "Find your next game.", "Connect with players, join matches, and be part of a growing sports community."),
        ("Onboarding2", "Try new things near you.", "Try new sports and Match with people who share your passion."),
        ("Onboarding3", "More than a game.", "Play, record, and grow with a community that moves together."),
    ]

    var body: some View {
        ZStack {
            OnboardingBackground()
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    GeometryReader { geo in
                        Image(pages[i].image).resizable().scaledToFit()
                            .frame(width: geo.size.width * (i == 2 ? 0.95 : 1.0), height: geo.size.height * 0.68)
                            .frame(width: geo.size.width)
                            .offset(y: geo.size.height * 0.05)
                            .accessibilityHidden(true)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Image("WordmarkDark").resizable().scaledToFit().frame(height: 40)
                        Text("Match Up. Match On.").font(HFont.inter(15, .semibold)).foregroundStyle(HColor.orLabel)
                            .padding(.leading, 17)
                    }
                    Spacer()
                    if page < 2 {
                        Button("SKIP") { withAnimation { page = 2 } }
                            .font(HFont.inter(14, .semibold)).foregroundStyle(.white)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 24)
                Spacer()
                Text(pages[page].title)
                    .font(HFont.inter(40, .semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .id("t\(page)").transition(.opacity)
                Text(pages[page].body)
                    .font(HFont.inter(17, .light)).tracking(0.85).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                    .id("b\(page)").transition(.opacity)
                HStack {
                    PageDots(count: 3, index: page)
                    Spacer()
                    if page < 2 {
                        Button { withAnimation { page += 1 } } label: {
                            Image("ArrowButton").resizable().frame(width: 85, height: 85)
                        }
                        .accessibilityLabel("Next")
                    } else {
                        Button(action: onFinish) {
                            Text("Get Started").font(HFont.inter(22, .semibold)).tracking(1.1).foregroundStyle(.white)
                                .frame(width: 218, height: 66)
                                .background(LinearGradient(stops: [
                                    .init(color: Color(hex: 0xFFB000), location: 0), .init(color: Color(hex: 0xFF8A00), location: 0.43),
                                    .init(color: Color(hex: 0xFF6B00), location: 0.72), .init(color: Color(hex: 0xF04420), location: 0.96),
                                ], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 30))
                                .shadow(color: .black.opacity(0.25), radius: 2, y: 4)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 85)
                .padding(.top, 10)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
            .animation(.easeInOut(duration: 0.25), value: page)
        }
        .preferredColorScheme(.dark)
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 17) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == index ? Color(hex: 0xFF7235) : Color(hex: 0xC7D1D9))
                    .frame(width: i == index ? 32 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.3), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}

private struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            Color(hex: 0x0D223A)
            RadialGradient(colors: [Color(hex: 0x176DA3, alpha: 0.65), Color(hex: 0x14547F, alpha: 0.35), .clear],
                           center: UnitPoint(x: 0.19, y: 0.15), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(hex: 0xFF7A00, alpha: 0.15), Color(hex: 0xF04420, alpha: 0.07), .clear],
                           center: UnitPoint(x: 0.83, y: 0.4), startRadius: 0, endRadius: 340)
            RadialGradient(colors: [Color(hex: 0x164C78, alpha: 0.55), Color(hex: 0x164C78, alpha: 0.2), .clear],
                           center: UnitPoint(x: 0.24, y: 0.88), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(hex: 0x2494CF, alpha: 0.35), Color(hex: 0x1B75AC, alpha: 0.15), .clear],
                           center: UnitPoint(x: 0.96, y: 0.96), startRadius: 0, endRadius: 260)
            // Figma: DESIGN ACCENT rotated 90°, 580×870 at (-8, 162), 30% opacity, normal blend.
            GeometryReader { geo in
                Image("DesignAccent").resizable().scaledToFill()
                    .frame(width: geo.size.height * 1.35, height: geo.size.width * 1.6)
                    .rotationEffect(.degrees(90))
                    .opacity(0.3)
                    .position(x: geo.size.width * 0.64, y: geo.size.height * 0.62)
            }
            .allowsHitTesting(false)
        }
        .clipped()
        .ignoresSafeArea()
    }
}

// MARK: - Welcome (WELCOME 635:3038)

struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    let onChoose: (WelcomeDestination) -> Void

    private var firstName: String {
        session.user?.displayName.split(separator: " ").first.map(String.init) ?? "there"
    }
    private var sportsText: String {
        let names = (session.user?.sports ?? []).map { $0.sport.title.lowercased() }
        switch names.count {
        case 0: return "games"
        case 1: return "\(names[0]) games"
        default: return names.dropLast().joined(separator: ", ") + " and \(names.last!) games"
        }
    }

    var body: some View {
        SuccessScreen(
            symbol: "checkmark",
            title: "You’re all set, \(firstName)!",
            message: "We’ll show you \(sportsText) around \(session.user?.homeArea?.name ?? "you"). Swipe right on the ones you like.",
            primaryTitle: "FIND A GAME", primary: { onChoose(.discover) },
            secondaryTitle: "GO TO HOME", secondary: { onChoose(.home) })
    }
}
