import FirebaseCore
import SwiftUI

@main
struct StablePPsApp: App {
    @State private var store: StableStore

    init() {
        // Firebase is set up from GoogleService-Info.plist (the same Firebase project as Backring Buyer).
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        _store = State(initialValue: StableStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.turf)
                .preferredColorScheme(.light)
                .onAppear { store.start() }
                // A chart PDF shared from Safari (Share → Stable PPs) or opened from Files.
                .onOpenURL { url in store.receive(url) }
        }
    }
}

struct RootView: View {
    @Environment(StableStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            switch store.phase {
            case .starting:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.page)
            case .notConfigured:
                ContentUnavailableView("Firebase isn’t set up",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("This build has no GoogleService-Info.plist. See StablePPs/README.md."))
            case .signedOut:
                SignInView()
            case .signedIn:
                NavigationStack {
                    HorseListView()
                        .navigationDestination(for: String.self) { id in HorseView(horseID: id) }
                }
            }
        }
        .sheet(item: $store.incoming) { batch in
            ChartImportSheet(batch: batch)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
