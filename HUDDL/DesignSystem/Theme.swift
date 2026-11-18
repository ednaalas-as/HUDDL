import SwiftUI
import CoreText

// MARK: - Colors (from the HUDDL Figma file)

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum HColor {
    static let brandNavy = Color(hex: 0x174F7A)
    static let darkText = Color(hex: 0x0D223A)
    static let body = Color(hex: 0x6A6A6A)
    static let secondary = Color(hex: 0x7A8794)
    static let muted = Color(hex: 0x9AA3B2)
    static let greyLabel = Color(hex: 0x7F7F7F)
    static let placeholder = Color(hex: 0xBDBDBD)
    static let orLabel = Color(hex: 0x8F8F8F)
    static let destructive = Color(hex: 0xD93B2F)
    static let success = Color(hex: 0x1F9D5C)
    static let successBG = Color(hex: 0xD1F2E1)
    static let accentTag = Color(hex: 0xF06A24)
    static let accentTagBG = Color(hex: 0xFFF1E6)
    static let avatarBG = Color(hex: 0xE3EEF7)
    static let orange = Color(hex: 0xFF7A00)
    static let navOrange = Color(hex: 0xE86A17)
    static let outline = Color(hex: 0xE7E7E7)
    static let buttonText = Color(hex: 0x121212)
    static let chipBorder = Color(hex: 0x174F7A, alpha: 0.15)
    static let shadow = Color(hex: 0x174F7A)
    static let peachBG = Color(hex: 0xFFF9F5)
}

enum HGradient {
    /// Primary navy gradient (buttons, titles): #172F4F → #1D4F7A → #2878A8
    static let navy = LinearGradient(colors: [Color(hex: 0x172F4F), Color(hex: 0x1D4F7A), Color(hex: 0x2878A8)],
                                     startPoint: UnitPoint(x: 0, y: 0.35), endPoint: UnitPoint(x: 1, y: 0.65))
    /// Accent orange gradient (+ button, primary CTAs)
    static let orange = LinearGradient(colors: [Color(hex: 0xFFB000), Color(hex: 0xFF8A00), Color(hex: 0xFF7A00), Color(hex: 0xF04420)],
                                       startPoint: .leading, endPoint: .trailing)
    /// Card / roster tint: soft blue → peach
    static let tint = LinearGradient(colors: [Color(hex: 0xEAF5FC), Color(hex: 0xF2F8FC), Color(hex: 0xFFFDFC), Color(hex: 0xFFF2E9)],
                                     startPoint: .leading, endPoint: .trailing)
    /// Header title text: navy → orange
    static let title = LinearGradient(colors: [Color(hex: 0x174F7A), Color(hex: 0x2878A8), Color(hex: 0x3B3B3B), Color(hex: 0xE9782C), Color(hex: 0xFF7A00)],
                                      startPoint: .leading, endPoint: .trailing)
    /// Main-screen background (Discover etc.)
    static let screen = LinearGradient(stops: [
        .init(color: .white, location: 0),
        .init(color: Color(hex: 0xFDFEFE), location: 0.45),
        .init(color: Color(hex: 0xFAFCFE), location: 0.70),
        .init(color: Color(hex: 0xEAF3FA), location: 0.82),
        .init(color: Color(hex: 0xF4F8FC), location: 0.92),
        .init(color: Color(hex: 0xE2EFF8), location: 1),
    ], startPoint: .top, endPoint: .bottom)
    /// Splash background
    static let splash = LinearGradient(stops: [
        .init(color: Color(hex: 0xE8F4FF), location: 0),
        .init(color: Color(hex: 0xEDF3FF), location: 0.22),
        .init(color: Color(hex: 0xF3F1FF), location: 0.45),
        .init(color: Color(hex: 0xFFF0E6), location: 0.68),
        .init(color: Color(hex: 0xFAF1F3), location: 0.84),
        .init(color: Color(hex: 0xFFF5EB), location: 1),
    ], startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1))
    /// Venue cover placeholder
    static let venue = LinearGradient(stops: [
        .init(color: Color(hex: 0xE6EFF7), location: 0),
        .init(color: Color(hex: 0xF3F5F8), location: 0.39),
        .init(color: Color(hex: 0xF8EEE6), location: 0.71),
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let favicon = LinearGradient(stops: [
        .init(color: Color(hex: 0x172033), location: 0),
        .init(color: Color(hex: 0x19304D), location: 0.45),
        .init(color: Color(hex: 0x1D4A70), location: 1),
    ], startPoint: .top, endPoint: .bottom)
}

// MARK: - Typography

enum InterWeight: String {
    case light = "Inter-Light", regular = "Inter-Regular", medium = "Inter-Medium", semibold = "Inter-SemiBold",
         bold = "Inter-Bold", extraBold = "Inter-ExtraBold"
}

enum HFont {
    /// Inter, scaled with Dynamic Type relative to body.
    static func inter(_ size: CGFloat, _ weight: InterWeight = .regular) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: .body)
    }
    /// SF Pro Semibold — used on buttons.
    static func button(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .semibold) }
    /// SF Compact Rounded — fields and names.
    static func rounded(_ size: CGFloat = 17, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func registerFonts() {
        for name in ["Inter-Light", "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold", "Inter-ExtraBold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - Shape & shadow helpers

enum HRadius {
    static let card: CGFloat = 30
    static let field: CGFloat = 10
    static let navyButton: CGFloat = 5
    static let sheet: CGFloat = 30
}

extension View {
    /// Soft navy-tinted card shadow used throughout the design.
    func cardShadow(_ opacity: Double = 0.12, radius: CGFloat = 15, y: CGFloat = 12) -> some View {
        shadow(color: HColor.shadow.opacity(opacity), radius: radius, x: 0, y: y)
    }

    /// Fills text with a gradient (used for header titles).
    func gradientForeground(_ gradient: LinearGradient) -> some View {
        overlay(gradient).mask(self)
    }
}
