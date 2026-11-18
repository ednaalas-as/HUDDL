import Foundation
import FirebaseFirestore

// MARK: - Sports

enum Sport: String, Codable, CaseIterable, Identifiable, Hashable {
    case tennis, volleyball, basketball, badminton, pickleball, football, chess, billiards
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tennis: "Lawn tennis"
        case .volleyball: "Volleyball"
        case .basketball: "Basketball"
        case .badminton: "Badminton"
        case .pickleball: "Pickleball"
        case .football: "Football"
        case .chess: "Chess"
        case .billiards: "Billiards"
        }
    }
    /// Uppercase label used on cards ("LAWN TENNIS").
    var label: String { title.uppercased() }

    var symbol: String {
        switch self {
        case .tennis: "tennisball.fill"
        case .volleyball: "volleyball.fill"
        case .basketball: "basketball.fill"
        case .badminton: "figure.badminton"
        case .pickleball: "figure.pickleball"
        case .football: "soccerball"
        case .chess: "checkerboard.rectangle"
        case .billiards: "circle.circle.fill"
        }
    }

    /// Sports offered in the host "Sport" sheet (Figma lists the first five; Chess & Billiards added for HUDDL's players).
    static let hostable: [Sport] = [.tennis, .volleyball, .basketball, .badminton, .pickleball, .chess, .billiards]
}

enum SkillLevel: String, Codable, CaseIterable, Identifiable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

// MARK: - Users

struct SportSkill: Codable, Hashable {
    var sport: Sport
    var skill: SkillLevel
}

struct HomeArea: Codable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
    var geohash: String
}

struct UserStats: Codable, Hashable {
    var games: Int = 0
    var wins: Int = 0
    var hosted: Int = 0
    var rating: Double? = nil      // OPEN: rating formula undefined — shown only when set.
    var reliability: Double? = nil // OPEN: reliability formula undefined.
}

enum InvitePrivacy: String, Codable, CaseIterable, Identifiable {
    case everyone, played, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .played: "Players I've played with"
        case .none: "No one"
        }
    }
}

struct NotificationPrefs: Codable, Hashable {
    var invites = true
    var applications = true
    var chat = true
    var reminders = true
}

struct UserSettings: Codable, Hashable {
    var notifications = NotificationPrefs()
    var whoCanInvite: InvitePrivacy = .everyone
}

struct AppUser: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var username: String
    var displayName: String
    var photoURL: String?
    var city: String?
    var homeArea: HomeArea?
    var sports: [SportSkill] = []
    var stats = UserStats()
    var settings = UserSettings()
    var profileComplete = false
    var fcmToken: String?
    var createdAt: Date?

    var uid: String { id ?? "" }
    var handle: String { "@\(username)" }
    var primarySport: SportSkill? { sports.first }
}

/// Lightweight denormalized player reference stored inside games, posts, chats.
struct PlayerRef: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var username: String
    var photoURL: String?

    init(id: String, name: String, username: String, photoURL: String? = nil) {
        self.id = id; self.name = name; self.username = username; self.photoURL = photoURL
    }
    init(_ user: AppUser) {
        self.init(id: user.uid, name: user.displayName, username: user.username, photoURL: user.photoURL)
    }
}

// MARK: - Venues

struct Venue: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var geohash: String
    var photoURL: String?
    var sports: [Sport] = []
}

// MARK: - Games

enum GameStatus: String, Codable {
    case open, full, started, ended, cancelled
}

enum PlayType: String, Codable { case solo, group }

struct GameFormat: Codable, Hashable {
    var playersPerTeam: Int
    var teams: Int = 2
    var isCustom = false
    var label: String { "\(playersPerTeam)v\(playersPerTeam)" }
    var totalPlayers: Int { playersPerTeam * teams }

    static let presets: [Int] = [1, 2, 3, 5, 6]
    static let maxPlayersPerTeam = 6
}

struct GameRules: Codable, Hashable {
    var fixedTeams = true
    var noSubs = true
}

struct Team: Codable, Hashable, Identifiable {
    var id: String          // "A" / "B"
    var capacity: Int
    var members: [PlayerRef] = []
    var spotsLeft: Int { max(0, capacity - members.count) }
    var isFull: Bool { spotsLeft == 0 }
}

struct Game: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var host: PlayerRef
    var title: String
    var sport: Sport
    var venueId: String
    var venueName: String
    var venueAddress: String?
    var venuePhotoURL: String?
    var latitude: Double
    var longitude: Double
    var geohash: String
    var startAt: Date
    var durationMin: Int = 120
    var notes: String?
    var format: GameFormat
    var playType: PlayType
    var rules = GameRules()
    var inviteOnly = false
    var status: GameStatus = .open
    var teams: [Team]
    var memberIds: [String] = []
    var spotsLeft: Int
    var createdAt: Date?
    var result: GameResult?

    var gid: String { id ?? "" }
    var filled: Int { teams.reduce(0) { $0 + $1.members.count } }
    var capacity: Int { teams.reduce(0) { $0 + $1.capacity } }
    var endAt: Date { startAt.addingTimeInterval(TimeInterval(durationMin * 60)) }
    var hasStarted: Bool { Date() >= startAt }
    var hasEnded: Bool { status == .ended || Date() >= endAt }
    var isJoinable: Bool { status == .open && !hasStarted && spotsLeft > 0 }

    func team(of uid: String) -> Team? { teams.first { $0.members.contains { $0.id == uid } } }
    func isMember(_ uid: String) -> Bool { memberIds.contains(uid) }

    var formatChips: [String] {
        [format.label, playType == .group ? "Group play" : "Solo players", "Fixed teams", "No subs"]
    }
}

struct SetScore: Codable, Hashable {
    var a: Int
    var b: Int
}

struct GameResult: Codable, Hashable {
    var winnerTeamId: String
    var sets: [SetScore]
    var postedBy: String
    var postedAt: Date
    var flagDeadline: Date
    var flagged = false

    var scoreLine: String {
        sets.map { winnerTeamId == "A" ? "\($0.a)–\($0.b)" : "\($0.b)–\($0.a)" }.joined(separator: ", ")
    }
}

// MARK: - Applications & invites

enum ApplicationStatus: String, Codable {
    case pending, accepted, declined, withdrawn, noRoom
}

enum JoinAs: String, Codable { case solo, group }

struct GameApplication: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var applicant: PlayerRef
    var teamId: String
    var joinAs: JoinAs
    var groupMembers: [PlayerRef] = []
    var note: String = ""
    var committed: Bool
    var status: ApplicationStatus = .pending
    var via: String = "apply"   // apply | invite
    var createdAt: Date?
    var gameId: String?
    var gameTitle: String?

    var size: Int { 1 + groupMembers.count }
}

enum InviteStatus: String, Codable { case sent, accepted, declined, cancelled }

struct GameInvite: Codable, Identifiable, Hashable {
    @DocumentID var id: String?   // == invitee uid
    var invitee: PlayerRef
    var invitedBy: PlayerRef
    var teamId: String
    var message: String
    var status: InviteStatus = .sent
    var createdAt: Date?
    var gameId: String?
    var gameTitle: String?
}

// MARK: - Swipes

enum SwipeDecision: String, Codable { case interested, notInterested }

struct Swipe: Codable, Identifiable, Hashable {
    @DocumentID var id: String?   // == gameId
    var decision: SwipeDecision
    var createdAt: Date?
    var removed = false
}

// MARK: - Feed

enum PostAudience: String, Codable, CaseIterable, Identifiable {
    case everyone, gamePlayers, onlyMe
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .gamePlayers: "Players from this game"
        case .onlyMe: "Only me"
        }
    }
}

enum PostType: String, Codable { case postGame, result, hosting, joined }

struct MediaItem: Codable, Hashable, Identifiable {
    var id: String { url }
    var url: String
    var type: String   // photo | video
    var duration: Double?
}

struct ResultSnapshot: Codable, Hashable {
    var sport: Sport
    var gameTitle: String
    var winnerTeamId: String
    var scoreLine: String
    var teamA: [PlayerRef]
    var teamB: [PlayerRef]
}

struct Post: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var author: PlayerRef
    var type: PostType
    var gameId: String?
    var gameTitle: String?
    var venueName: String?
    var gameDate: Date?
    var gameSport: Sport?
    var spotsLeft: Int?
    var includeResult = false
    var result: ResultSnapshot?
    var media: [MediaItem] = []
    var caption: String = ""
    var tagged: [PlayerRef] = []
    var actors: [PlayerRef] = []
    var audience: PostAudience = .everyone
    var visibleTo: [String] = []      // uids allowed when audience != everyone
    var likeCount = 0
    var commentCount = 0
    var repostCount = 0
    var createdAt: Date?

    var pid: String { id ?? "" }
}

struct Comment: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var author: PlayerRef
    var text: String
    var createdAt: Date?
}

// MARK: - Chat

enum ChatType: String, Codable { case game, direct }

struct ChatThread: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var type: ChatType
    var gameId: String?
    var title: String
    var memberIds: [String]
    var members: [PlayerRef]
    var readOnly = false
    var lastMessage: String?
    var lastSenderId: String?
    var updatedAt: Date?
    var unread: [String: Int] = [:]

    var cid: String { id ?? "" }
    func other(than uid: String) -> PlayerRef? { members.first { $0.id != uid } }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var senderId: String
    var senderName: String
    var text: String?
    var imageURL: String?
    var system = false
    var createdAt: Date?
}

// MARK: - Notifications

enum NotificationKind: String, Codable {
    case invite, inviteDeclined, accepted, declined, applied, spotLeft, expired, ended, cancelled, full, result, comment, like
}

struct AppNotification: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var type: NotificationKind
    var title: String
    var body: String
    var actor: PlayerRef?
    var gameId: String?
    var postId: String?
    var teamId: String?
    var read = false
    var resolved = false     // invite answered
    var createdAt: Date?
}

// MARK: - Reviews, reports, support

struct Review: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var revieweeId: String
    var reviewer: PlayerRef
    var gameId: String
    var gameTitle: String?
    var tags: [String]
    var text: String
    var helpfulCount = 0
    var createdAt: Date?
}

struct Report: Codable {
    var reporterId: String
    var targetType: String   // post | user
    var targetId: String
    var reason: String
    var createdAt: Date?
}

struct SupportTicket: Codable {
    var uid: String
    var topic: String
    var message: String
    var attachmentURL: String?
    var createdAt: Date?
}
