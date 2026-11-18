import Foundation
import UIKit
import UserNotifications
import FirebaseMessaging
import FirebaseFirestore

/// Firebase Cloud Messaging registration. Pushes are sent by Cloud Functions when notification
/// documents are created (see firebase/functions). Requires a real Firebase project + APNs key;
/// against the emulators the in-app Notifications list still works, only remote pushes are skipped.
@MainActor
final class PushService: NSObject, MessagingDelegate, UNUserNotificationCenterDelegate {
    static let shared = PushService()
    private var currentUid: String?
    /// Set by the router to open the content a tapped push refers to.
    var onOpen: ((_ gameId: String?, _ postId: String?, _ type: String?) -> Void)?

    var isEnabled: Bool { !FirebaseBootstrap.usingEmulators }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        guard isEnabled else { return }
        Messaging.messaging().delegate = self
    }

    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted && isEnabled { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    func syncToken(for uid: String) {
        currentUid = uid
        guard isEnabled else { return }
        Messaging.messaging().token { token, _ in
            guard let token else { return }
            Task { try? await Firestore.firestore().collection("users").document(uid).setData(["fcmToken": token], merge: true) }
        }
    }

    func clearToken(for uid: String?) {
        guard let uid, isEnabled else { return }
        Task { try? await Firestore.firestore().collection("users").document(uid).updateData(["fcmToken": FieldValue.delete()]) }
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in if let uid = self.currentUid { self.syncToken(for: uid) } }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let gameId = info["gameId"] as? String, postId = info["postId"] as? String, type = info["type"] as? String
        await MainActor.run { self.onOpen?(gameId, postId, type) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseBootstrap.configure()   // no-op if already configured in HUDDLApp.init
        PushService.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard !FirebaseBootstrap.usingEmulators else { return }
        Messaging.messaging().apnsToken = deviceToken
    }
}
