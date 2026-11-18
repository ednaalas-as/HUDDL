import SwiftUI
import FirebaseAuth

@main
struct HUDDLApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionStore()
    @State private var router = Router()
    @State private var toasts = ToastCenter()
    @State private var dialogs = DialogCenter()

    init() {
        // Must run before any @State store touches Firebase (SwiftUI builds state before the app delegate runs).
        FirebaseBootstrap.configure()
        HFont.registerFonts()
        // UI-test hooks (only active when the test runner passes these launch arguments).
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestReset") {
            try? Auth.auth().signOut()
            UserDefaults.standard.removeObject(forKey: "huddl.onboardingSeen")
            UserDefaults.standard.set(true, forKey: "huddl.rememberMe")
        }
        if args.contains("-uiTestNoAnimations") { UIView.setAnimationsEnabled(false) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(router)
                .environment(toasts)
                .environment(dialogs)
                .modifier(ToastHost(center: toasts))
                .modifier(DialogHost(center: dialogs))
                .tint(HColor.brandNavy)
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @State private var splashDone = false
    @State private var showWelcome = false

    var body: some View {
        ZStack {
            if !splashDone || session.phase == .launching {
                SplashView()
                    .transition(.opacity)
            } else {
                switch session.phase {
                case .signedOut, .launching:
                    AuthFlowView().transition(.opacity)
                case .needsProfile:
                    ProfileSetupView(onDone: {}).transition(.move(edge: .trailing))
                case .signedIn:
                    if showWelcome {
                        WelcomeView { destination in
                            router.reset(to: destination)
                            withAnimation { showWelcome = false }
                        }
                        .transition(.opacity)
                    } else {
                        MainTabView().transition(.opacity)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.phase)
        .animation(.easeInOut(duration: 0.35), value: splashDone)
        .task {
            if !session.rememberMe { session.signOut() }
            session.start()
            try? await Task.sleep(for: .seconds(1.4))
            splashDone = true
        }
        .onChange(of: session.phase) { old, new in
            if new == .signedOut { router.resetAll() }
            if old == .needsProfile && new == .signedIn { showWelcome = true }
        }
    }
}
