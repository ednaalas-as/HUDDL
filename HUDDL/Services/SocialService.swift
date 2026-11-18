import Foundation
import FirebaseFirestore

/// Feed posts, likes, comments, reposts, hides, reports; players, blocks, reviews; chat; notifications.
enum SocialService {
    private static var db: Firestore { Firestore.firestore() }

    // MARK: Feed

    /// Home feed: public posts, plus posts whose audience includes the viewer.
    static func listenFeed(uid: String, limit: Int = 50, onChange: @escaping (Result<[Post], Error>) -> Void) -> ListenerRegistration {
        db.collection("posts")
            .whereFilter(Filter.orFilter([
                Filter.whereField("audience", isEqualTo: PostAudience.everyone.rawValue),
                Filter.whereField("visibleTo", arrayContains: uid),
            ]))
            .order(by: "createdAt", descending: true).limit(to: limit)
            .addSnapshotListener { snap, error in
                if let error { onChange(.failure(error)); return }
                onChange(.success(snap?.documents.compactMap { try? $0.data(as: Post.self) } ?? []))
            }
    }

    static func listenPost(_ id: String, onChange: @escaping (Post?) -> Void) -> ListenerRegistration {
        db.collection("posts").document(id).addSnapshotListener { snap, _ in
            onChange(snap.flatMap { try? $0.data(as: Post.self) })
        }
    }

    static func posts(by uid: String) async throws -> [Post] {
        let snap = try await db.collection("posts").whereField("author.id", isEqualTo: uid)
            .whereField("audience", isEqualTo: PostAudience.everyone.rawValue)
            .order(by: "createdAt", descending: true).limit(to: 50).getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Post.self) }
    }

    static func posts(forGame gameId: String, viewer uid: String) async throws -> [Post] {
        let snap = try await db.collection("posts").whereField("gameId", isEqualTo: gameId)
            .whereFilter(Filter.orFilter([
                Filter.whereField("audience", isEqualTo: PostAudience.everyone.rawValue),
                Filter.whereField("visibleTo", arrayContains: uid),
            ]))
            .order(by: "createdAt", descending: true).getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Post.self) }
    }

    /// Creates a post-game "moments" post. Tag/audience rules are enforced server-side.
    static func createMomentsPost(gameId: String, caption: String, media: [MediaItem], taggedIds: [String],
                                  includeResult: Bool, audience: PostAudience) async throws -> String {
        let res = try await FunctionsClient.call("createPost", [
            "gameId": gameId, "caption": caption,
            "media": media.map { m -> [String: Any] in
                var d: [String: Any] = ["url": m.url, "type": m.type]
                if let duration = m.duration { d["duration"] = duration }
                return d
            },
            "taggedIds": taggedIds, "includeResult": includeResult, "audience": audience.rawValue,
        ])
        return res["postId"] as? String ?? ""
    }

    static func isLiked(_ postId: String, uid: String) async -> Bool {
        (try? await db.collection("posts").document(postId).collection("likes").document(uid).getDocument().exists) ?? false
    }

    static func listenLikes(uid: String, onChange: @escaping (Set<String>) -> Void) -> ListenerRegistration {
        db.collectionGroup("likes").whereField("uid", isEqualTo: uid).addSnapshotListener { snap, _ in
            onChange(Set(snap?.documents.compactMap { $0.reference.parent.parent?.documentID } ?? []))
        }
    }

    static func setLike(_ postId: String, uid: String, liked: Bool) async throws {
        let ref = db.collection("posts").document(postId).collection("likes").document(uid)
        if liked { try await ref.setData(["uid": uid, "createdAt": FieldValue.serverTimestamp()]) } else { try await ref.delete() }
    }

    static func likers(_ postId: String, limit: Int = 3) async -> [String] {
        let snap = try? await db.collection("posts").document(postId).collection("likes").order(by: "createdAt", descending: true).limit(to: limit).getDocuments()
        return snap?.documents.map(\.documentID) ?? []
    }

    static func listenComments(_ postId: String, onChange: @escaping ([Comment]) -> Void) -> ListenerRegistration {
        db.collection("posts").document(postId).collection("comments").order(by: "createdAt").addSnapshotListener { snap, _ in
            onChange(snap?.documents.compactMap { try? $0.data(as: Comment.self) } ?? [])
        }
    }

    static func addComment(_ postId: String, author: PlayerRef, text: String) async throws {
        let comment = Comment(author: author, text: text, createdAt: Date())
        let ref = db.collection("posts").document(postId).collection("comments").document()
        try ref.setData(from: comment)
        try await ref.updateData(["createdAt": FieldValue.serverTimestamp()])
    }

    static func repost(_ postId: String) async throws {
        try await FunctionsClient.call("repost", ["postId": postId])
    }

    static func hide(_ postId: String, uid: String, hidden: Bool) async throws {
        let ref = db.collection("users").document(uid).collection("hiddenPosts").document(postId)
        if hidden { try await ref.setData(["createdAt": FieldValue.serverTimestamp()]) } else { try await ref.delete() }
    }

    static func listenHidden(uid: String, onChange: @escaping (Set<String>) -> Void) -> ListenerRegistration {
        db.collection("users").document(uid).collection("hiddenPosts").addSnapshotListener { snap, _ in
            onChange(Set(snap?.documents.map(\.documentID) ?? []))
        }
    }

    static func report(reporter: String, targetType: String, targetId: String, reason: String) async throws {
        try await db.collection("reports").addDocument(data: [
            "reporterId": reporter, "targetType": targetType, "targetId": targetId,
            "reason": reason, "createdAt": FieldValue.serverTimestamp(),
        ])
    }

    // MARK: Players

    static func user(_ uid: String) async throws -> AppUser? {
        let snap = try await db.collection("users").document(uid).getDocument()
        return snap.exists ? try snap.data(as: AppUser.self) : nil
    }

    static func listenUser(_ uid: String, onChange: @escaping (AppUser?) -> Void) -> ListenerRegistration {
        db.collection("users").document(uid).addSnapshotListener { snap, _ in onChange(snap.flatMap { try? $0.data(as: AppUser.self) }) }
    }

    static func users(ids: [String]) async throws -> [AppUser] {
        var out: [AppUser] = []
        for chunk in ids.chunked(30) where !chunk.isEmpty {
            let snap = try await db.collection("users").whereField(FieldPath.documentID(), in: chunk).getDocuments()
            out += snap.documents.compactMap { try? $0.data(as: AppUser.self) }
        }
        return out
    }

    static func allPlayers(limit: Int = 200) async throws -> [AppUser] {
        let snap = try await db.collection("users").whereField("profileComplete", isEqualTo: true).limit(to: limit).getDocuments()
        return snap.documents.compactMap { try? $0.data(as: AppUser.self) }
    }

    static func searchPlayers(_ text: String) async throws -> [AppUser] {
        let q = text.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        guard !q.isEmpty else { return [] }
        return try await allPlayers().filter { $0.username.contains(q) || $0.displayName.lowercased().contains(q) }
    }

    static func listenBlocked(uid: String, onChange: @escaping (Set<String>) -> Void) -> ListenerRegistration {
        db.collection("users").document(uid).collection("blocked").addSnapshotListener { snap, _ in
            onChange(Set(snap?.documents.map(\.documentID) ?? []))
        }
    }

    /// Blocks are silent: the other player is not notified.
    static func setBlocked(_ other: PlayerRef, by uid: String, blocked: Bool) async throws {
        let ref = db.collection("users").document(uid).collection("blocked").document(other.id)
        if blocked {
            try await ref.setData(["name": other.name, "username": other.username, "photoURL": other.photoURL ?? NSNull(),
                                   "createdAt": FieldValue.serverTimestamp()])
        } else { try await ref.delete() }
    }

    static func blockedPlayers(uid: String) async throws -> [PlayerRef] {
        let snap = try await db.collection("users").document(uid).collection("blocked").getDocuments()
        return snap.documents.map {
            PlayerRef(id: $0.documentID, name: $0["name"] as? String ?? "", username: $0["username"] as? String ?? "",
                      photoURL: $0["photoURL"] as? String)
        }
    }

    /// Uids who have blocked `uid`, maintained server-side in a private doc only `uid` can read,
    /// so content is hidden in both directions without exposing a queryable block list.
    static func listenBlockedBy(uid: String, onChange: @escaping (Set<String>) -> Void) -> ListenerRegistration {
        db.collection("users").document(uid).collection("private").document("blockedBy").addSnapshotListener { snap, _ in
            onChange(Set(snap?.data()?["uids"] as? [String] ?? []))
        }
    }

    static func reviews(for uid: String) async throws -> [Review] {
        let snap = try await db.collection("reviews").whereField("revieweeId", isEqualTo: uid)
            .order(by: "createdAt", descending: true).getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Review.self) }
    }

    static func markHelpful(_ reviewId: String, uid: String) async throws {
        try await db.collection("reviews").document(reviewId).collection("helpful").document(uid)
            .setData(["createdAt": FieldValue.serverTimestamp()])
    }

    static func submitTicket(_ t: SupportTicket) async throws {
        var data: [String: Any] = ["uid": t.uid, "topic": t.topic, "message": t.message, "createdAt": FieldValue.serverTimestamp()]
        if let a = t.attachmentURL { data["attachmentURL"] = a }
        try await db.collection("supportTickets").addDocument(data: data)
    }
}

// MARK: - Chat

enum ChatService {
    private static var db: Firestore { Firestore.firestore() }

    static func listenThreads(uid: String, onChange: @escaping (Result<[ChatThread], Error>) -> Void) -> ListenerRegistration {
        db.collection("chats").whereField("memberIds", arrayContains: uid).order(by: "updatedAt", descending: true)
            .addSnapshotListener { snap, error in
                if let error { onChange(.failure(error)); return }
                onChange(.success(snap?.documents.compactMap { try? $0.data(as: ChatThread.self) } ?? []))
            }
    }

    static func listenThread(_ id: String, onChange: @escaping (ChatThread?) -> Void) -> ListenerRegistration {
        db.collection("chats").document(id).addSnapshotListener { snap, _ in onChange(snap.flatMap { try? $0.data(as: ChatThread.self) }) }
    }

    static func listenMessages(_ chatId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration {
        db.collection("chats").document(chatId).collection("messages").order(by: "createdAt").limit(toLast: 200)
            .addSnapshotListener { snap, _ in onChange(snap?.documents.compactMap { try? $0.data(as: ChatMessage.self) } ?? []) }
    }

    static func send(chatId: String, sender: PlayerRef, text: String?, imageURL: String?) async throws {
        let ref = db.collection("chats").document(chatId).collection("messages").document()
        var data: [String: Any] = ["senderId": sender.id, "senderName": sender.name, "system": false,
                                   "createdAt": FieldValue.serverTimestamp()]
        if let text { data["text"] = text }
        if let imageURL { data["imageURL"] = imageURL }
        try await ref.setData(data)
    }

    static func markRead(chatId: String, uid: String) async {
        try? await db.collection("chats").document(chatId).updateData(["unread.\(uid)": 0])
    }

    /// Opens (or creates) the 1:1 DM thread with another player. Respects blocks server-side.
    static func directThread(with uid: String) async throws -> String {
        let res = try await FunctionsClient.call("openDirectChat", ["otherId": uid])
        guard let id = res["chatId"] as? String else { throw AppError.server("Couldn’t open this chat.") }
        return id
    }

    static func gameThreadId(_ gameId: String) -> String { "game_\(gameId)" }
}

// MARK: - Notifications

enum NotificationService {
    private static var db: Firestore { Firestore.firestore() }

    static func listen(uid: String, onChange: @escaping (Result<[AppNotification], Error>) -> Void) -> ListenerRegistration {
        db.collection("notifications").document(uid).collection("items").order(by: "createdAt", descending: true).limit(to: 100)
            .addSnapshotListener { snap, error in
                if let error { onChange(.failure(error)); return }
                onChange(.success(snap?.documents.compactMap { try? $0.data(as: AppNotification.self) } ?? []))
            }
    }

    static func markRead(uid: String, ids: [String]) async {
        let batch = db.batch()
        for id in ids { batch.updateData(["read": true], forDocument: db.collection("notifications").document(uid).collection("items").document(id)) }
        try? await batch.commit()
    }

    static func clearAll(uid: String, keepPendingInvites: [String]) async throws {
        let snap = try await db.collection("notifications").document(uid).collection("items").getDocuments()
        let batch = db.batch()
        for doc in snap.documents where !keepPendingInvites.contains(doc.documentID) { batch.deleteDocument(doc.reference) }
        try await batch.commit()
    }

    static func resolve(uid: String, id: String, declined: Bool) async {
        try? await db.collection("notifications").document(uid).collection("items").document(id)
            .updateData(["resolved": true, "read": true, "type": declined ? NotificationKind.inviteDeclined.rawValue : NotificationKind.accepted.rawValue])
    }
}
