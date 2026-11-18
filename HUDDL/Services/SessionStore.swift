import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Owns the authentication state and the signed-in user's profile document.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable { case launching, signedOut, needsProfile, signedIn }

    var phase: Phase = .launching
    var user: AppUser?
    var lastResetEmailAt: Date?

    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var userListener: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }

    var uid: String? { Auth.auth().currentUser?.uid }
    var me: PlayerRef? { user.map(PlayerRef.init) }
    /// The account email lives only in Firebase Auth (never in public Firestore docs).
    var email: String? { Auth.auth().currentUser?.email }

    @AppStorage("huddl.rememberMe") @ObservationIgnored var rememberMe = true
    @AppStorage("huddl.onboardingSeen") @ObservationIgnored var onboardingSeen = false

    func start() {
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in self?.handleAuthChange(firebaseUser) }
        }
    }

    private func handleAuthChange(_ firebaseUser: FirebaseAuth.User?) {
        userListener?.remove(); userListener = nil
        guard let firebaseUser else {
            user = nil
            phase = .signedOut
            return
        }
        userListener = db.collection("users").document(firebaseUser.uid).addSnapshotListener { [weak self] snap, _ in
            guard let self else { return }
            Task { @MainActor in
                if let snap, snap.exists, let user = try? snap.data(as: AppUser.self) {
                    self.user = user
                    self.phase = user.profileComplete ? .signedIn : .needsProfile
                    PushService.shared.syncToken(for: user.uid)
                } else if snap?.exists == false {
                    // Auth account without a profile doc (e.g. interrupted sign up) → finish setup.
                    self.user = nil
                    self.phase = .needsProfile
                }
            }
        }
    }

    // MARK: Sign up

    func signUp(username: String, email: String, password: String) async throws {
        let uname = Validation.normalizedUsername(username)
        // Fast pre-check so the user sees "taken" before an account is created.
        let taken = try await db.collection("usernames").document(uname).getDocument().exists
        if taken { throw AppError.validation("That username is taken. Try another one.") }

        let result: AuthDataResult
        do {
            result = try await Auth.auth().createUser(withEmail: email.trimmingCharacters(in: .whitespaces), password: password)
        } catch {
            throw AppError.validation(Self.authMessage(error))
        }
        let uid = result.user.uid
        let user = AppUser(id: nil, username: uname, displayName: uname,
                           city: Geo.lucena.name, homeArea: nil, createdAt: Date())
        do {
            try await db.runTransaction { tx, errorPointer in
                let nameRef = self.db.collection("usernames").document(uname)
                do {
                    if try tx.getDocument(nameRef).exists {
                        errorPointer?.pointee = NSError(domain: "HUDDL", code: 409,
                                                        userInfo: [NSLocalizedDescriptionKey: "That username is taken. Try another one."])
                        return nil
                    }
                } catch let e as NSError { errorPointer?.pointee = e; return nil }
                tx.setData(["uid": uid], forDocument: nameRef)
                do { try tx.setData(from: user, forDocument: self.db.collection("users").document(uid)) }
                catch let e as NSError { errorPointer?.pointee = e; return nil }
                return nil
            }
        } catch {
            // Roll back the auth account so the user can retry with another username.
            try? await result.user.delete()
            throw AppError.validation(AppError.message(error))
        }
    }

    // MARK: Sign in (username or email)

    func signIn(identifier: String, password: String) async throws {
        let id = identifier.trimmingCharacters(in: .whitespaces)
        do {
            if id.contains("@") && !id.hasPrefix("@") {
                try await Auth.auth().signIn(withEmail: id, password: password)
            } else {
                // Username sign-in is resolved server-side so emails are never exposed to other clients.
                let res = try await FunctionsClient.call("signInWithUsername",
                                                         ["username": Validation.normalizedUsername(id), "password": password])
                guard let token = res["token"] as? String else { throw AppError.server("Couldn't sign you in. Try again.") }
                try await Auth.auth().signIn(withCustomToken: token)
            }
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.validation(Self.authMessage(error))
        }
    }

    // MARK: Password reset (Figma: link expires in 30 minutes; resend has a 60-second cooldown)

    var resendCooldownRemaining: Int {
        guard let last = lastResetEmailAt else { return 0 }
        return max(0, 60 - Int(Date().timeIntervalSince(last)))
    }

    func sendPasswordReset(email: String) async throws {
        if resendCooldownRemaining > 0 {
            throw AppError.validation("Please wait \(resendCooldownRemaining)s before resending")
        }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespaces))
            lastResetEmailAt = Date()
        } catch {
            let code = AuthErrorCode(rawValue: (error as NSError).code)
            // Don't reveal whether an account exists.
            if code == .userNotFound { lastResetEmailAt = Date(); return }
            throw AppError.validation(Self.authMessage(error))
        }
    }

    func updatePassword(current: String, new: String) async throws {
        guard let fu = Auth.auth().currentUser, let email = fu.email else { throw AppError.notSignedIn }
        do {
            let cred = EmailAuthProvider.credential(withEmail: email, password: current)
            try await fu.reauthenticate(with: cred)
            try await fu.updatePassword(to: new)
        } catch {
            throw AppError.validation(Self.authMessage(error))
        }
    }

    // MARK: Profile

    func completeProfile(displayName: String, sports: [SportSkill], homeArea: HomeArea, photoURL: String?) async throws {
        guard let uid else { throw AppError.notSignedIn }
        var data: [String: Any] = [
            "displayName": displayName,
            "sports": sports.map { ["sport": $0.sport.rawValue, "skill": $0.skill.rawValue] },
            "homeArea": ["name": homeArea.name, "latitude": homeArea.latitude, "longitude": homeArea.longitude, "geohash": homeArea.geohash],
            "city": homeArea.name,
            "profileComplete": true,
        ]
        if let photoURL { data["photoURL"] = photoURL }
        try await db.collection("users").document(uid).setData(data, merge: true)
    }

    func updateProfile(_ fields: [String: Any]) async throws {
        guard let uid else { throw AppError.notSignedIn }
        try await db.collection("users").document(uid).setData(fields, merge: true)
    }

    func signOut() {
        PushService.shared.clearToken(for: uid)
        try? Auth.auth().signOut()
    }

    func deleteAccount() async throws {
        _ = try await FunctionsClient.call("deleteAccount")
        try? Auth.auth().signOut()
    }

    static func authMessage(_ error: Error) -> String {
        guard let code = AuthErrorCode(rawValue: (error as NSError).code) else { return AppError.message(error) }
        switch code {
        case .emailAlreadyInUse: return "An account with this email already exists. Try signing in."
        case .invalidEmail: return "Enter a valid email address"
        case .weakPassword: return "Use at least 8 characters"
        case .wrongPassword, .invalidCredential, .userNotFound: return "Wrong username or password"
        case .tooManyRequests: return "Too many attempts. Try again in a few minutes."
        case .networkError: return AppError.offline.errorDescription!
        case .requiresRecentLogin: return "Please sign in again to continue."
        default: return error.localizedDescription
        }
    }
}
