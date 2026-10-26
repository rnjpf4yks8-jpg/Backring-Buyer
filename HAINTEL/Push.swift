import SwiftUI
import UserNotifications

extension Notification.Name {
    /// Apple gave this phone a push token (object: the token as hex).
    static let pushToken = Notification.Name("BackringBuyerPushToken")
    /// The person tapped one of our notifications.
    static let pushOpened = Notification.Name("BackringBuyerPushOpened")
}

/// Receives the phone's push token from Apple, and shows notifications while the app is open.
/// The server side is firebase/functions/people.js (onPersonChanged).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set when a notification tap launched the app, before the screens were listening.
    static var openedFromNotification = false

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .pushToken, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No push for this build (push not switched on for the app yet). Everything else still works.
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        AppDelegate.openedFromNotification = true
        NotificationCenter.default.post(name: .pushOpened, object: nil)
        completionHandler()
    }
}

enum PushNotifications {
    /// Asks for permission (iOS only shows the prompt once) and, if allowed, registers with Apple.
    @MainActor
    static func enable() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }
}
