import Foundation
import FirebaseFunctions

/// Thin wrapper over callable Cloud Functions for trusted operations
/// (roster changes, accept/decline transactions, cascades). See firebase/functions/src/index.ts.
enum FunctionsClient {
    static let region = "asia-southeast1"
    private static var functions: Functions { Functions.functions(region: region) }

    @discardableResult
    static func call(_ name: String, _ data: [String: Any] = [:]) async throws -> [String: Any] {
        do {
            let result = try await functions.httpsCallable(name).call(data)
            return result.data as? [String: Any] ?? [:]
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            // Surface the human-readable message thrown by the function (HttpsError).
            throw AppError.server(error.localizedDescription)
        }
    }
}

enum AppError: LocalizedError, Equatable {
    case server(String)
    case validation(String)
    case notSignedIn
    case offline

    var errorDescription: String? {
        switch self {
        case .server(let m), .validation(let m): m
        case .notSignedIn: "Please sign in again."
        case .offline: "You're offline. Check your connection and try again."
        }
    }

    /// Maps any error to copy suitable for a toast.
    static func message(_ error: Error) -> String {
        if let app = error as? AppError { return app.errorDescription ?? "Something went wrong." }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain || ns.code == 14 /* Firestore UNAVAILABLE */ {
            return AppError.offline.errorDescription!
        }
        return ns.localizedDescription
    }
}
