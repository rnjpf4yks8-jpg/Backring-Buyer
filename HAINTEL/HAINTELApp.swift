import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct HAINTELApp: App {
    @State private var store = SaleStore(backend: HAINTELApp.makeBackend())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.blue)
                .preferredColorScheme(.light)
                .task { await store.start() }
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
