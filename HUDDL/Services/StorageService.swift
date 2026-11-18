import Foundation
import UIKit
import FirebaseStorage
import FirebaseAuth

/// Uploads media to Cloud Storage for Firebase. Paths are owner-scoped so Storage rules can enforce access.
enum StorageService {
    enum Folder: String { case avatars, posts, chats, support }

    /// Compresses and uploads a JPEG; returns its download URL.
    static func uploadImage(_ image: UIImage, folder: Folder, maxDimension: CGFloat = 1600) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw AppError.notSignedIn }
        let resized = image.resized(maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: 0.82) else { throw AppError.validation("Couldn't read that photo") }
        let ref = Storage.storage().reference().child("\(folder.rawValue)/\(uid)/\(UUID().uuidString).jpg")
        let meta = StorageMetadata(); meta.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: meta)
        return try await ref.downloadURL().absoluteString
    }

    /// Uploads a video file (post-game moments).
    static func uploadVideo(at url: URL, folder: Folder = .posts) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw AppError.notSignedIn }
        let ref = Storage.storage().reference().child("\(folder.rawValue)/\(uid)/\(UUID().uuidString).mov")
        let meta = StorageMetadata(); meta.contentType = "video/quicktime"
        _ = try await ref.putFileAsync(from: url, metadata: meta)
        return try await ref.downloadURL().absoluteString
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
