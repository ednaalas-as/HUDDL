import Foundation
import FirebaseFirestore

/// Games, swipes, saves, applications and invites.
/// Simple owner-scoped writes go straight to Firestore (guarded by security rules);
/// anything that changes rosters or other people's data goes through Cloud Functions.
enum GameService {
    private static var db: Firestore { Firestore.firestore() }
    static var games: CollectionReference { db.collection("games") }

    // MARK: Reading

    static func listen(_ id: String, onChange: @escaping (Result<Game?, Error>) -> Void) -> ListenerRegistration {
        games.document(id).addSnapshotListener { snap, error in
            if let error { onChange(.failure(error)); return }
            guard let snap, snap.exists else { onChange(.success(nil)); return }
            onChange(Result { try snap.data(as: Game.self) })
        }
    }

    static func fetch(_ id: String) async throws -> Game? {
        let snap = try await games.document(id).getDocument()
        return snap.exists ? try snap.data(as: Game.self) : nil
    }

    static func fetch(ids: [String]) async throws -> [Game] {
        var result: [Game] = []
        for chunk in ids.chunked(30) where !chunk.isEmpty {
            let snap = try await games.whereField(FieldPath.documentID(), in: chunk).getDocuments()
            result += snap.documents.compactMap { try? $0.data(as: Game.self) }
        }
        return result
    }

    /// Open, public games within 10 km of the home area (geohash cells + exact distance filter).
    static func discover(near area: HomeArea, radiusKm: Double = 10) async throws -> [Game] {
        var found: [String: Game] = [:]
        for prefix in Geo.coveringPrefixes(lat: area.latitude, lon: area.longitude) {
            let snap = try await games
                .whereField("status", isEqualTo: GameStatus.open.rawValue)
                .whereField("inviteOnly", isEqualTo: false)
                .whereField("geohash", isGreaterThanOrEqualTo: prefix)
                .whereField("geohash", isLessThan: prefix + "~")
                .getDocuments()
            for doc in snap.documents {
                if let g = try? doc.data(as: Game.self) { found[g.gid] = g }
            }
        }
        return found.values.filter {
            !$0.hasStarted && Geo.distanceKm(area.latitude, area.longitude, $0.latitude, $0.longitude) <= radiusKm
        }
    }

    /// Games the user hosts (any status).
    static func hosted(by uid: String) async throws -> [Game] {
        let snap = try await games.whereField("host.id", isEqualTo: uid).order(by: "startAt", descending: true).getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Game.self) }
    }

    /// Games the user is on a roster for.
    static func joined(by uid: String) async throws -> [Game] {
        let snap = try await games.whereField("memberIds", arrayContains: uid).order(by: "startAt", descending: true).getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Game.self) }
    }

    static func search(_ text: String) async throws -> [Game] {
        let q = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let snap = try await games.whereField("status", in: [GameStatus.open.rawValue, GameStatus.full.rawValue])
            .whereField("inviteOnly", isEqualTo: false).limit(to: 200).getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Game.self) }.filter {
            $0.title.lowercased().contains(q) || $0.venueName.lowercased().contains(q) ||
            $0.sport.title.lowercased().contains(q) || $0.host.name.lowercased().contains(q)
        }
    }

    // MARK: Hosting

    static func create(_ game: Game) async throws -> String {
        let ref = games.document()
        try ref.setData(from: game)
        // setData(from:) is fire-and-forget; wait for the server so errors surface.
        _ = try await ref.getDocument(source: .server)
        return ref.documentID
    }

    /// Host edits (title, venue, time, notes, invite-only). Format/rosters are locked once players have joined.
    static func update(_ id: String, fields: [String: Any]) async throws {
        try await FunctionsClient.call("editGame", ["gameId": id, "fields": fields])
    }

    static func cancel(_ id: String) async throws {
        try await FunctionsClient.call("cancelGame", ["gameId": id])
    }

    // MARK: Swipes & saves

    static func swipe(_ gameId: String, uid: String, decision: SwipeDecision) async throws {
        try await db.collection("users").document(uid).collection("swipes").document(gameId)
            .setData(["decision": decision.rawValue, "createdAt": FieldValue.serverTimestamp(), "removed": false])
    }

    static func removeSwipe(_ gameId: String, uid: String) async throws {
        try await db.collection("users").document(uid).collection("swipes").document(gameId)
            .setData(["removed": true], merge: true)
    }

    static func listenSwipes(uid: String, onChange: @escaping ([Swipe]) -> Void) -> ListenerRegistration {
        db.collection("users").document(uid).collection("swipes").addSnapshotListener { snap, _ in
            onChange(snap?.documents.compactMap { try? $0.data(as: Swipe.self) } ?? [])
        }
    }

    static func setSaved(_ gameId: String, uid: String, saved: Bool) async throws {
        let ref = db.collection("users").document(uid).collection("saved").document(gameId)
        if saved { try await ref.setData(["createdAt": FieldValue.serverTimestamp()]) } else { try await ref.delete() }
    }

    static func isSaved(_ gameId: String, uid: String) async -> Bool {
        (try? await db.collection("users").document(uid).collection("saved").document(gameId).getDocument().exists) ?? false
    }

    // MARK: Applications

    struct ApplyRequest {
        var gameId: String
        var teamId: String
        var joinAs: JoinAs
        var groupMemberIds: [String]
        var note: String
        var committed: Bool
    }

    static func apply(_ r: ApplyRequest) async throws {
        try await FunctionsClient.call("applyToGame", [
            "gameId": r.gameId, "teamId": r.teamId, "joinAs": r.joinAs.rawValue,
            "groupMemberIds": r.groupMemberIds, "note": r.note, "committed": r.committed,
        ])
    }

    static func withdraw(gameId: String) async throws {
        try await FunctionsClient.call("withdrawApplication", ["gameId": gameId])
    }

    /// The current user's own application for a game (doc id == applicant uid).
    static func myApplication(gameId: String, uid: String) async -> GameApplication? {
        try? await games.document(gameId).collection("applications").document(uid).getDocument().data(as: GameApplication.self)
    }

    static func listenMyApplications(uid: String, onChange: @escaping ([GameApplication]) -> Void) -> ListenerRegistration {
        db.collectionGroup("applications").whereField("applicantId", isEqualTo: uid).addSnapshotListener { snap, _ in
            onChange(snap?.documents.compactMap { try? $0.data(as: GameApplication.self) } ?? [])
        }
    }

    static func listenApplicants(gameId: String, onChange: @escaping ([GameApplication]) -> Void) -> ListenerRegistration {
        games.document(gameId).collection("applications").order(by: "createdAt").addSnapshotListener { snap, _ in
            onChange(snap?.documents.compactMap { try? $0.data(as: GameApplication.self) } ?? [])
        }
    }

    static func accept(gameId: String, applicantId: String) async throws -> [String: Any] {
        try await FunctionsClient.call("acceptApplication", ["gameId": gameId, "applicantId": applicantId])
    }

    static func decline(gameId: String, applicantId: String, reason: String?) async throws {
        try await FunctionsClient.call("declineApplication", ["gameId": gameId, "applicantId": applicantId, "reason": reason ?? ""])
    }

    static func leave(gameId: String) async throws {
        try await FunctionsClient.call("leaveGame", ["gameId": gameId])
    }

    // MARK: Invites

    static func invite(gameId: String, inviteeId: String, teamId: String, message: String) async throws {
        try await FunctionsClient.call("invitePlayer", ["gameId": gameId, "inviteeId": inviteeId, "teamId": teamId, "message": message])
    }

    static func cancelInvite(gameId: String, inviteeId: String) async throws {
        try await FunctionsClient.call("cancelInvite", ["gameId": gameId, "inviteeId": inviteeId])
    }

    static func respondInvite(gameId: String, accept: Bool) async throws {
        try await FunctionsClient.call("respondInvite", ["gameId": gameId, "accept": accept])
    }

    static func listenInvites(gameId: String, onChange: @escaping ([GameInvite]) -> Void) -> ListenerRegistration {
        games.document(gameId).collection("invites").addSnapshotListener { snap, _ in
            onChange(snap?.documents.compactMap { try? $0.data(as: GameInvite.self) } ?? [])
        }
    }

    static func listenMyInvites(uid: String, onChange: @escaping ([GameInvite]) -> Void) -> ListenerRegistration {
        db.collectionGroup("invites").whereField("invitee.id", isEqualTo: uid)
            .whereField("status", isEqualTo: InviteStatus.sent.rawValue).addSnapshotListener { snap, _ in
                onChange(snap?.documents.compactMap { try? $0.data(as: GameInvite.self) } ?? [])
            }
    }

    // MARK: Results

    static func postResult(gameId: String, winnerTeamId: String, sets: [SetScore], caption: String, mediaURLs: [String]) async throws {
        try await FunctionsClient.call("postResult", [
            "gameId": gameId, "winnerTeamId": winnerTeamId,
            "sets": sets.map { ["a": $0.a, "b": $0.b] }, "caption": caption, "mediaURLs": mediaURLs,
        ])
    }

    // MARK: Venues

    static func venues() async throws -> [Venue] {
        let snap = try await db.collection("venues").order(by: "name").getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Venue.self) }
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
