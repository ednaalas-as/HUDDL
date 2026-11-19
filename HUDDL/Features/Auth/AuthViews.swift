import SwiftUI

/// Onboarding → Sign up / Sign in / Forgot password. Signed-in routing happens in RootView.
struct AuthFlowView: View {
    @Environment(SessionStore.self) private var session
    enum Screen { case onboarding, signUp, signIn, forgot }
    @State private var screen: Screen = .onboarding

    var body: some View {
        ZStack {
            switch screen {
            case .onboarding:
                OnboardingView { session.onboardingSeen = true; screen = .signUp }
                    .transition(.opacity)
            case .signUp:
                SignUpView(goSignIn: { screen = .signIn }).transition(.move(edge: .trailing))
            case .signIn:
                SignInView(goSignUp: { screen = .signUp }, goForgot: { screen = .forgot }).transition(.move(edge: .trailing))
            case .forgot:
                ForgotPasswordView(goBack: { screen = .signIn }).transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: screen)
        .onAppear { if session.onboardingSeen { screen = .signIn } }
    }
}

/// Shared layout: glow background, wordmark, translucent card.
private struct AuthScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            GlowBackground()
            ScrollView {
                VStack(spacing: 0) {
                    Wordmark(height: 50).padding(.top, 24)
                    VStack(spacing: 0) {
                        Text(title).font(.system(size: 30, weight: .semibold)).tracking(-0.6).foregroundStyle(.black)
                            .padding(.top, 40).padding(.bottom, 36)
                            .accessibilityAddTraits(.isHeader)
                        content()
                    }
                    .padding(.horizontal, 25)
                    .frame(maxWidth: 350)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct OrDivider: View {
    var body: some View {
        HStack(spacing: 15) {
            Rectangle().fill(HColor.orLabel.opacity(0.6)).frame(width: 80, height: 1)
            Text("or").font(HFont.rounded(17, .regular)).foregroundStyle(HColor.orLabel)
            Rectangle().fill(HColor.orLabel.opacity(0.6)).frame(width: 80, height: 1)
        }
    }
}

/// "Continue with Facebook / Google" (Text / … Border components).
private struct SocialButtons: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var googleBusy = false
    var body: some View {
        VStack(spacing: 15) {
            social("Continue with Facebook", symbol: "f.circle.fill", tint: Color(hex: 0x1877F2)) {
                // Facebook needs a Facebook developer app, which HUDDL doesn't have yet.
                toasts.info("Facebook sign-in isn't available yet. Use your username or Google for now.")
            }
            social("Continue with Google", symbol: "g.circle.fill", tint: Color(hex: 0xEA4335), busy: googleBusy) {
                guard !googleBusy else { return }
                googleBusy = true
                Task {
                    defer { googleBusy = false }
                    do { try await session.signInWithGoogle() }
                    catch is CancellationError { }   // closed Google's sheet: stay here quietly
                    catch { toasts.error(AppError.message(error)) }
                }
            }
            .accessibilityIdentifier("auth.google")
        }
    }
    private func social(_ title: String, symbol: String, tint: Color, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                if busy { ProgressView().frame(width: 20, height: 20) }
                else { Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(tint) }
                Text(title).font(HFont.inter(12, .semibold)).foregroundStyle(HColor.buttonText)
            }
            .frame(width: 230, height: 40)
            .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HColor.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct FooterLink: View {
    let prompt: String
    let link: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Text(prompt).font(HFont.inter(12, .semibold)).foregroundStyle(.black)
            Button(link, action: action).font(HFont.inter(12, .semibold)).foregroundStyle(HColor.orange)
        }
    }
}

// MARK: - Sign up (SIGN UP + ERROR / FILLED / LOADING)

struct SignUpView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    let goSignIn: () -> Void

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var errors: [String: String] = [:]
    @State private var loading = false

    var body: some View {
        AuthScaffold(title: "Sign Up") {
            VStack(spacing: 24) {
                AuthField(placeholder: "username", text: $username, contentType: .username, error: errors["username"])
                AuthField(placeholder: "email address", text: $email, keyboard: .emailAddress, contentType: .emailAddress, error: errors["email"])
                AuthField(placeholder: "password", text: $password, isSecure: true, contentType: .newPassword, error: errors["password"])
                AuthField(placeholder: "confirm password", text: $confirm, isSecure: true, contentType: .newPassword, error: errors["confirm"])
            }
            NavyButton(title: "SIGN UP", isLoading: loading, action: submit).padding(.top, 30)
            OrDivider().padding(.vertical, 18)
            SocialButtons()
            FooterLink(prompt: "Already have an Account?", link: "Sign In", action: goSignIn).padding(.vertical, 40)
        }
        .overlay { if loading { LoadingOverlay(text: "Creating your account…") } }
        .onChange(of: username) { errors["username"] = nil }
        .onChange(of: email) { errors["email"] = nil }
        .onChange(of: password) { errors["password"] = nil }
        .onChange(of: confirm) { errors["confirm"] = nil }
    }

    private func submit() {
        var e: [String: String] = [:]
        e["username"] = Validation.username(username)
        e["email"] = Validation.email(email)
        e["password"] = Validation.password(password)
        e["confirm"] = Validation.confirm(password, confirm)
        errors = e.compactMapValues { $0 }
        if username.isEmpty && email.isEmpty && password.isEmpty && confirm.isEmpty {
            toasts.error("Fill in all fields to create your account"); return
        }
        guard errors.isEmpty else { UINotificationFeedbackGenerator().notificationOccurred(.error); return }
        loading = true
        Task {
            do {
                try await session.signUp(username: username, email: email, password: password)
                // RootView moves to Profile setup when the profile doc appears.
            } catch {
                let message = AppError.message(error)
                if message.contains("username") { errors["username"] = message }
                else if message.contains("email") { errors["email"] = message }
                else { toasts.error(message) }
            }
            loading = false
        }
    }
}

// MARK: - Sign in (SIGN IN + ERROR / FILLED / LOADING)

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    let goSignUp: () -> Void
    let goForgot: () -> Void

    @State private var identifier = ""
    @State private var password = ""
    @State private var remember = true
    @State private var errors: [String: String] = [:]
    @State private var loading = false

    var body: some View {
        AuthScaffold(title: "Sign In") {
            VStack(spacing: 38) {
                AuthField(placeholder: "username", text: $identifier, contentType: .username, error: errors["id"])
                AuthField(placeholder: "password", text: $password, isSecure: true, contentType: .password, error: errors["password"])
            }
            HStack {
                CheckBox(isOn: $remember, label: "Remember me")
                Spacer()
                Button("Forgot Password?", action: goForgot).font(HFont.inter(12, .semibold)).foregroundStyle(HColor.orange)
            }
            .padding(.horizontal, 23).padding(.top, 15)
            NavyButton(title: "SIGN IN", isLoading: loading, action: submit).padding(.top, 32)
            OrDivider().padding(.vertical, 18)
            SocialButtons()
            FooterLink(prompt: "Don’t have an Account?", link: "Sign Up", action: goSignUp).padding(.vertical, 40)
        }
        .overlay { if loading { LoadingOverlay(text: "Signing you in…") } }
        .onAppear { remember = session.rememberMe }
        .onChange(of: identifier) { errors["id"] = nil }
        .onChange(of: password) { errors["password"] = nil }
    }

    private func submit() {
        var e: [String: String] = [:]
        if identifier.trimmingCharacters(in: .whitespaces).isEmpty { e["id"] = "Enter your username" }
        if password.isEmpty { e["password"] = "Enter your password" }
        errors = e
        guard e.isEmpty else { UINotificationFeedbackGenerator().notificationOccurred(.error); return }
        loading = true
        session.rememberMe = remember
        Task {
            do { try await session.signIn(identifier: identifier, password: password) }
            catch { errors["password"] = AppError.message(error) }
            loading = false
        }
    }
}

// MARK: - Forgot password (+ ERROR / FILLED / SENT / RESENT)

struct ForgotPasswordView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    let goBack: () -> Void

    @State private var email = ""
    @State private var error: String?
    @State private var sent = false
    @State private var loading = false
    @State private var cooldown = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        AuthScaffold(title: sent ? "Check your email" : "Forgot Password") {
            if sent {
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(HColor.successBG).frame(width: 72, height: 72)
                        Image(systemName: "envelope.badge.fill").font(.system(size: 28)).foregroundStyle(HColor.success)
                    }
                    Text("We sent a reset link to **\(email)**. The link expires in 30 minutes.")
                        .font(HFont.inter(13, .medium)).foregroundStyle(HColor.body).multilineTextAlignment(.center)
                    NavyButton(title: "BACK TO SIGN IN", width: 200, action: goBack).padding(.top, 10)
                    Button(cooldown > 0 ? "Resend link in \(cooldown)s" : "Didn’t get it? Resend link") { send(resend: true) }
                        .font(HFont.inter(12, .semibold))
                        .foregroundStyle(cooldown > 0 ? HColor.muted : HColor.orange)
                        .padding(.top, 6)
                }
            } else {
                Text("Enter the email you signed up with and we’ll send you a link to reset your password.")
                    .font(HFont.inter(13, .medium)).foregroundStyle(HColor.body).multilineTextAlignment(.center)
                    .padding(.bottom, 24)
                AuthField(placeholder: "email address", text: $email, keyboard: .emailAddress, contentType: .emailAddress, error: error)
                NavyButton(title: "SEND LINK", isLoading: loading) { send(resend: false) }.padding(.top, 30)
                Button("Back to Sign In", action: goBack).font(HFont.inter(12, .semibold)).foregroundStyle(HColor.orange).padding(.top, 30)
            }
        }
        .onChange(of: email) { error = nil }
        .onReceive(timer) { _ in cooldown = session.resendCooldownRemaining }
    }

    private func send(resend: Bool) {
        if let e = Validation.email(email) { error = e; return }
        if resend && session.resendCooldownRemaining > 0 {
            toasts.info("Please wait \(session.resendCooldownRemaining)s before resending"); return
        }
        loading = true
        Task {
            do {
                try await session.sendPasswordReset(email: email)
                withAnimation { sent = true }
                if resend { toasts.show("Reset link sent again") }
            } catch {
                self.error = AppError.message(error)
            }
            cooldown = session.resendCooldownRemaining
            loading = false
        }
    }
}
