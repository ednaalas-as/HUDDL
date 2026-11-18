import SwiftUI

// MARK: - Toast (top, auto-dismiss ~2.8 s)

struct ToastMessage: Equatable, Identifiable {
    enum Kind { case success, info, error }
    let id = UUID()
    let text: String
    var kind: Kind = .success
}

@MainActor
@Observable
final class ToastCenter {
    var current: ToastMessage?
    private var task: Task<Void, Never>?

    func show(_ text: String, _ kind: ToastMessage.Kind = .success) {
        task?.cancel()
        let message = ToastMessage(text: text, kind: kind)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { current = message }
        switch kind {
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .info: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        UIAccessibility.post(notification: .announcement, argument: text)
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.current = nil }
        }
    }
    func error(_ text: String) { show(text, .error) }
    func info(_ text: String) { show(text, .info) }
}

struct ToastView: View {
    let message: ToastMessage
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(bg).frame(width: 32, height: 32)
                Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(fg)
            }
            Text(message.text).font(HFont.inter(13, .semibold)).foregroundStyle(HColor.darkText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, 9).padding(.trailing, 16).padding(.vertical, 9)
        .frame(minHeight: 52)
        .background(Color.white.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(Color.white, lineWidth: 1))
        .shadow(color: HColor.shadow.opacity(0.16), radius: 12, y: 8)
        .padding(.horizontal, 20)
    }
    private var symbol: String {
        switch message.kind { case .success: "checkmark"; case .info: "info"; case .error: "exclamationmark" }
    }
    private var fg: Color {
        switch message.kind { case .success: HColor.success; case .info: HColor.brandNavy; case .error: HColor.destructive }
    }
    private var bg: Color {
        switch message.kind { case .success: HColor.successBG; case .info: HColor.avatarBG; case .error: Color(hex: 0xFCE8E6) }
    }
}

struct ToastHost: ViewModifier {
    let center: ToastCenter
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message = center.current {
                ToastView(message: message)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(message.id)
                    .onTapGesture { withAnimation { center.current = nil } }
                    .zIndex(999)
            }
        }
    }
}

// MARK: - Confirmation dialog (centered card with icon, title, body, primary + ghost)

struct ConfirmRequest: Identifiable {
    let id = UUID()
    var symbol: String = "questionmark"
    var title: String
    var message: String
    var confirmTitle: String
    var cancelTitle: String = "Cancel"
    var destructive = false
    var onConfirm: () -> Void
    var onCancel: (() -> Void)? = nil
}

struct ConfirmDialogView: View {
    let request: ConfirmRequest
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            HColor.darkText.opacity(0.45).ignoresSafeArea()
                .onTapGesture { request.onCancel?(); dismiss() }
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(request.destructive ? Color(hex: 0xFCE8E6) : HColor.accentTagBG).frame(width: 60, height: 60)
                    Image(systemName: request.symbol).font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(request.destructive ? HColor.destructive : HColor.accentTag)
                }
                Text(request.title).font(HFont.inter(18, .bold)).foregroundStyle(HColor.darkText).multilineTextAlignment(.center)
                    .accessibilityIdentifier("dialog.title")
                Text(request.message).font(HFont.inter(13, .medium)).foregroundStyle(HColor.body)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    Button {
                        dismiss(); request.onConfirm()
                    } label: {
                        Text(request.confirmTitle).font(HFont.button(15)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background {
                                if request.destructive { Capsule().fill(HColor.destructive) }
                                else { Capsule().fill(HGradient.navy) }
                            }
                    }
                    .accessibilityIdentifier("dialog.confirm")
                    Button {
                        request.onCancel?(); dismiss()
                    } label: {
                        Text(request.cancelTitle).font(HFont.button(15)).foregroundStyle(HColor.brandNavy)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: HRadius.card, style: .continuous))
            .shadow(color: HColor.shadow.opacity(0.2), radius: 30, y: 16)
            .padding(.horizontal, 32)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .accessibilityAddTraits(.isModal)
    }
}

@MainActor
@Observable
final class DialogCenter {
    var request: ConfirmRequest?
    func confirm(_ request: ConfirmRequest) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.request = request }
    }
    func dismiss() { withAnimation(.easeOut(duration: 0.2)) { request = nil } }
}

struct DialogHost: ViewModifier {
    let center: DialogCenter
    func body(content: Content) -> some View {
        content.overlay {
            if let request = center.request {
                ConfirmDialogView(request: request) { center.dismiss() }.zIndex(998)
            }
        }
    }
}

// MARK: - Full-screen loading ("Posting…", "Signing you in…")

struct LoadingOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            HGradient.splash.ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView().controlSize(.large).tint(HColor.brandNavy)
                Text(text).font(HFont.inter(16, .semibold)).foregroundStyle(HColor.brandNavy)
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Success screen (badge + title + body + two CTAs)

struct SuccessScreen: View {
    var symbol = "checkmark"
    let title: String
    let message: String
    var badgeText: String? = nil
    let primaryTitle: String
    let primary: () -> Void
    var secondaryTitle: String?
    var secondary: (() -> Void)?

    var body: some View {
        ZStack {
            GlowBackground()
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    Circle().fill(HGradient.orange).frame(width: 110, height: 110)
                        .shadow(color: Color(hex: 0xF04420, alpha: 0.25), radius: 16, y: 8)
                    Image(systemName: symbol).font(.system(size: 46, weight: .bold)).foregroundStyle(.white)
                }
                if let badgeText { StatusTag(text: badgeText, kind: .accent) }
                Text(title).font(HFont.inter(26, .extraBold)).foregroundStyle(HColor.brandNavy).multilineTextAlignment(.center)
                Text(message).font(HFont.inter(14, .medium)).foregroundStyle(HColor.body)
                    .multilineTextAlignment(.center).padding(.horizontal, 36)
                Spacer()
                VStack(spacing: 12) {
                    OrangeButton(title: primaryTitle, action: primary)
                    if let secondaryTitle, let secondary { GhostButton(title: secondaryTitle, action: secondary) }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .onAppear { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }
}

// MARK: - Bottom sheet chrome

extension View {
    /// HUDDL bottom-sheet styling: grabber, radius 30.
    func huddlSheet(_ detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(HRadius.sheet)
            .presentationBackground(.white)
    }
}

struct SheetTitle: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(HFont.inter(20, .extraBold)).foregroundStyle(HColor.brandNavy)
            if let subtitle { Text(subtitle).font(HFont.inter(13, .medium)).foregroundStyle(HColor.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }
}

/// One option row inside a choice sheet.
struct SheetOptionRow: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var isSelected = false
    var isDisabled = false
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(destructive ? Color(hex: 0xFCE8E6) : HColor.avatarBG).frame(width: 40, height: 40)
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(destructive ? HColor.destructive : HColor.brandNavy)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(HFont.inter(15, .semibold)).foregroundStyle(destructive ? HColor.destructive : HColor.darkText)
                    if let subtitle { Text(subtitle).font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary) }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(HColor.accentTag)
                }
            }
            .padding(.vertical, 8).contentShape(Rectangle())
            .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Form fields

/// Auth field (Username / Email / password): white 54% fill, radius 10, SF Compact Rounded 17.
struct AuthField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var error: String?
    @State private var reveal = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Group {
                    if isSecure && !reveal {
                        SecureField("", text: $text, prompt: prompt)
                    } else {
                        TextField("", text: $text, prompt: prompt)
                            .keyboardType(keyboard)
                    }
                }
                .font(HFont.rounded(17))
                .tracking(-0.34)
                .foregroundStyle(HColor.darkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(contentType)
                .focused($focused)
                .accessibilityIdentifier("field.\(placeholder)")
                if isSecure && !text.isEmpty {
                    Button { reveal.toggle() } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye").foregroundStyle(HColor.muted)
                    }
                    .accessibilityLabel(reveal ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, 25)
            .frame(height: 50)
            .background(Color.white.opacity(0.54), in: RoundedRectangle(cornerRadius: HRadius.field))
            .overlay(RoundedRectangle(cornerRadius: HRadius.field)
                .stroke(error != nil ? HColor.destructive : (focused ? HColor.orange.opacity(0.6) : Color.clear), lineWidth: 1.2))
            if let error {
                Text(error).font(HFont.inter(11, .semibold)).foregroundStyle(HColor.destructive).padding(.leading, 6)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
    }

    private var prompt: Text {
        Text(placeholder).font(HFont.rounded(17)).foregroundColor(HColor.placeholder)
    }
}

/// In-app form field with label (Host a game, Edit profile, Contact support…).
struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var error: String?
    var maxLength: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: label)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(HColor.placeholder), axis: axis)
                .font(HFont.inter(15, .medium))
                .foregroundStyle(HColor.darkText)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(error != nil ? HColor.destructive : HColor.chipBorder, lineWidth: 1))
                .onChange(of: text) { _, new in
                    if let maxLength, new.count > maxLength { text = String(new.prefix(maxLength)) }
                }
            if let error {
                Text(error).font(HFont.inter(11, .semibold)).foregroundStyle(HColor.destructive)
            }
        }
    }
}

/// Square checkbox (check box component, 15–18pt).
struct CheckBox: View {
    @Binding var isOn: Bool
    let label: String
    var body: some View {
        Button { isOn.toggle(); UISelectionFeedbackGenerator().selectionChanged() } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? AnyShapeStyle(HGradient.orange) : AnyShapeStyle(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(isOn ? Color.clear : HColor.muted, lineWidth: 1.2))
                    .overlay(Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).opacity(isOn ? 1 : 0))
                    .frame(width: 18, height: 18)
                Text(label).font(HFont.inter(12, .medium)).foregroundStyle(HColor.body)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Toggle row (Toggle component On/Off), tinted orange.
struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var locked = false
    var onLockedTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(HFont.inter(15, .semibold)).foregroundStyle(HColor.darkText)
                    if locked { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(HColor.muted) }
                }
                if let subtitle { Text(subtitle).font(HFont.inter(12, .medium)).foregroundStyle(HColor.secondary) }
            }
            Spacer()
            Toggle("", isOn: locked ? .constant(true) : $isOn)
                .labelsHidden()
                .tint(HColor.orange)
                .allowsHitTesting(!locked)
        }
        .contentShape(Rectangle())
        .onTapGesture { if locked { onLockedTap?() } }
        .accessibilityElement(children: .combine)
    }
}
