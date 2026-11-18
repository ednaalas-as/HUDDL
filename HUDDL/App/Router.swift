import SwiftUI

/// Every pushable destination in the app. States (loading, error, saved…) are view state, not routes.
enum Route: Hashable {
    case game(String)
    case applicants(String)
    case invitePlayers(String)
    case postResult(String)
    case player(String)
    case post(String)
    case chat(String)
    case notifications
    case search
    case settings
    case editProfile
    case sportsSkill
    case password
    case blockedPlayers
    case helpCenter
    case helpArticle(HelpArticle)
    case contactSupport
    case terms
    case deleteAccount
    case hostedGames
}

/// Full-screen flows presented over the tab bar.
enum CoverFlow: Identifiable, Hashable {
    case host
    case editGame(String)
    case compose(gameId: String)
    case apply(String)

    var id: String {
        switch self {
        case .host: "host"
        case .editGame(let id): "edit-\(id)"
        case .compose(let id): "compose-\(id)"
        case .apply(let id): "apply-\(id)"
        }
    }
}

enum HuddleSegment: Hashable { case discover, interested, notInterested }

@MainActor
@Observable
final class Router {
    var tab: MainTab = .home
    var homePath = NavigationPath()
    var huddlePath = NavigationPath()
    var chatPath = NavigationPath()
    var profilePath = NavigationPath()
    var cover: CoverFlow?
    var huddleSegment: HuddleSegment = .discover
    /// Bumped to ask Home to scroll to top / refresh after a new post.
    var homeRefreshToken = UUID()
    var profileTabRequest: ProfileTab?

    /// True when the current tab shows its root screen (the tab bar is visible only there).
    var isAtRoot: Bool {
        switch tab {
        case .home: homePath.isEmpty
        case .huddle: huddlePath.isEmpty
        case .chat: chatPath.isEmpty
        case .profile: profilePath.isEmpty
        }
    }

    func push(_ route: Route) {
        switch tab {
        case .home: homePath.append(route)
        case .huddle: huddlePath.append(route)
        case .chat: chatPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func pop() {
        switch tab {
        case .home: if !homePath.isEmpty { homePath.removeLast() }
        case .huddle: if !huddlePath.isEmpty { huddlePath.removeLast() }
        case .chat: if !chatPath.isEmpty { chatPath.removeLast() }
        case .profile: if !profilePath.isEmpty { profilePath.removeLast() }
        }
    }

    func popToRoot(_ t: MainTab? = nil) {
        switch t ?? tab {
        case .home: homePath = NavigationPath()
        case .huddle: huddlePath = NavigationPath()
        case .chat: chatPath = NavigationPath()
        case .profile: profilePath = NavigationPath()
        }
    }

    /// Switch tab and optionally push a route on it.
    func go(_ t: MainTab, _ route: Route? = nil, root: Bool = true) {
        if root { popToRoot(t) }
        tab = t
        if let route { push(route) }
    }

    func openHuddle(_ segment: HuddleSegment) {
        huddleSegment = segment
        go(.huddle)
    }

    func showHomeWithNewPost() {
        popToRoot(.home)
        tab = .home
        homeRefreshToken = UUID()
    }

    func reset(to destination: WelcomeDestination) {
        resetAll()
        switch destination {
        case .discover: huddleSegment = .discover; tab = .huddle
        case .home: tab = .home
        }
    }

    func resetAll() {
        homePath = NavigationPath(); huddlePath = NavigationPath(); chatPath = NavigationPath(); profilePath = NavigationPath()
        cover = nil; tab = .home; huddleSegment = .discover
    }

    /// Handles a notification / push target.
    func open(gameId: String?, postId: String?) {
        if let postId { go(.home, .post(postId)) } else if let gameId { go(tab, .game(gameId), root: false) }
    }
}

enum WelcomeDestination { case discover, home }
enum ProfileTab: Hashable { case matches, hosted, reviews }

/// Resolves a Route to its screen. Shared by all tab stacks.
struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .game(let id): GameDetailsView(gameId: id)
        case .applicants(let id): ApplicantsView(gameId: id)
        case .invitePlayers(let id): InvitePlayersView(gameId: id)
        case .postResult(let id): PostResultView(gameId: id)
        case .player(let uid): PlayerProfileView(uid: uid)
        case .post(let id): PostDetailView(postId: id)
        case .chat(let id): ChatThreadView(chatId: id)
        case .notifications: NotificationsView()
        case .search: SearchView()
        case .settings: SettingsView()
        case .editProfile: EditProfileView()
        case .sportsSkill: SportsSkillView()
        case .password: PasswordSecurityView()
        case .blockedPlayers: BlockedPlayersView()
        case .helpCenter: HelpCenterView()
        case .helpArticle(let a): HelpArticleView(article: a)
        case .contactSupport: ContactSupportView()
        case .terms: TermsView()
        case .deleteAccount: DeleteAccountView()
        case .hostedGames: ProfileView(initialTab: .hosted)
        }
    }
}

extension View {
    /// Attaches the shared route table and hides the system nav bar (HUDDL uses its own header).
    func huddlRoutes() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0).toolbar(.hidden, for: .navigationBar) }
    }
}

/// HUDDL hides the system navigation bar (it uses its own header), which normally disables
/// the edge swipe-back gesture. Re-enable it so back navigation stays native.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
