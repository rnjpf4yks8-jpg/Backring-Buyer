import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct HAINTELApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = SaleStore(backend: HAINTELApp.makeBackend())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.blue)
                .preferredColorScheme(.light)
                .task { await store.start() }
                .task { await store.settlePurchases() }
                .onReceive(NotificationCenter.default.publisher(for: .pushToken)) { note in
                    guard let token = note.object as? String else { return }
                    Task { await store.didReceive(deviceToken: token) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .pushOpened)) { _ in
                    Task { await store.openedNotification() }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Approvals made while the app was in the background show up on return.
                    if phase == .active, !store.isLoading { Task { await store.refreshUser() } }
                }
        }
    }

    /// Uses Firebase once GoogleService-Info.plist is added to the HAINTEL folder; sample data until then.
    private static func makeBackend() -> SaleBackend {
        #if canImport(FirebaseCore)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            return FirebaseBackend()
        }
        #endif
        return SampleBackend()
    }
}
