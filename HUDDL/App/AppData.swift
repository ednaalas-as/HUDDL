import Foundation
import FirebaseFirestore

/// Live per-user data shared across tabs (swipes, applications, invites, blocks, likes, badges).
@MainActor
@Observable
final class AppData {
    var swipes: [String: Swipe] = [:]
    var applications: [String: GameApplication] = [:]   // by gameId
    var invites: [String: GameInvite] = [:]              // pending, by gameId
    var blocked: Set<String> = []
    var blockedBy: Set<String> = []
    var hiddenPosts: Set<String> = []
    var likes: Set<String> = []
    var notifications: [AppNotification] = []
    var threads: [ChatThread] = []

    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var uid: String?

    var unreadNotifications: Int { notifications.filter { !$0.read }.count }
    var unreadChats: Int { threads.reduce(0) { $0 + ($1.unread[uid ?? ""] ?? 0) } }

    func hiddenUsers() -> Set<String> { blocked.union(blockedBy) }

    func start(uid: String) {
        guard self.uid != uid else { return }
        stop()
        self.uid = uid
        listeners = [
            GameService.listenSwipes(uid: uid) { [weak self] s in
                self?.swipes = Dictionary(uniqueKeysWithValues: s.compactMap { sw in sw.id.map { ($0, sw) } })
            },
            GameService.listenMyApplications(uid: uid) { [weak self] apps in
                var map: [String: GameApplication] = [:]
                for a in apps { if let g = a.gameId { map[g] = a } }
                self?.applications = map
            },
            GameService.listenMyInvites(uid: uid) { [weak self] inv in
                var map: [String: GameInvite] = [:]
                for i in inv { if let g = i.gameId { map[g] = i } }
                self?.invites = map
            },
            SocialService.listenBlocked(uid: uid) { [weak self] in self?.blocked = $0 },
            SocialService.listenBlockedBy(uid: uid) { [weak self] in self?.blockedBy = $0 },
            SocialService.listenHidden(uid: uid) { [weak self] in self?.hiddenPosts = $0 },
            SocialService.listenLikes(uid: uid) { [weak self] in self?.likes = $0 },
            NotificationService.listen(uid: uid) { [weak self] r in if case .success(let n) = r { self?.notifications = n } },
            ChatService.listenThreads(uid: uid) { [weak self] r in if case .success(let t) = r { self?.threads = t } },
        ]
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        uid = nil
        swipes = [:]; applications = [:]; invites = [:]; blocked = []; blockedBy = []
        hiddenPosts = []; likes = []; notifications = []; threads = []
    }

    /// The viewer's relationship to a game, used for chips and buttons.
    enum Relation { case host, joined, pending, invited, declined, none }

    func relation(to game: Game, uid: String) -> Relation {
        if game.host.id == uid { return .host }
        if game.isMember(uid) { return .joined }
        if invites[game.gid] != nil { return .invited }
        switch applications[game.gid]?.status {
        case .pending, .noRoom: return .pending
        case .declined: return .declined
        default: return .none
        }
    }
}
