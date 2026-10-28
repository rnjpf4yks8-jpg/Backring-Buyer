import SwiftUI
import WebKit

/// Equibase inside the app. You browse as in Safari (signed in to Equibase once, here); the app reads
/// a page only when you tap "Add this page": the horse's entries and results, or a chart.
struct EquibaseBrowser: View {
    let horse: Horse
    let start: URL
    @Environment(StableStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = BrowserModel()
    @State private var working = false
    @State private var message: String?
    @State private var good = false

    var body: some View {
        NavigationStack {
            BrowserView(webView: model.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if model.isLoading { ProgressView().padding(8) }
                }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .navigationTitle(model.title.isEmpty ? "Equibase" : model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { model.webView.goBack() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!model.canGoBack)
                        Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                        Link(destination: model.url ?? start) { Image(systemName: "safari") }
                    }
                }
                .onAppear { model.load(start) }
                .interactiveDismissDisabled(working)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(good ? Theme.good : working ? Theme.ink : Theme.bad)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await addPage() }
            } label: {
                HStack {
                    if working { ProgressView().tint(.white) }
                    Text(working ? "Claude is reading…" : model.isPDF ? "Add this chart to \(horse.name)" : "Add this page to \(horse.name)")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(primary: true))
            .disabled(working || model.isLoading)
            Text("Reads what's on screen: the horse's entries and results (with Equibase Speed Figures), or a chart.")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
        .background(.bar)
    }

    private func addPage() async {
        working = true
        good = false
        message = nil
        defer { working = false }
        do {
            if model.isPDF {
                guard let pdf = await model.pdfData() else {
                    message = "Couldn’t capture this chart. Tap the Safari button, then Share → Stable PPs."
                    return
                }
                message = "Reading the chart… about half a minute."
                let outcome = try await store.readChart(pdf: pdf, text: nil, horses: [horse])
                report(outcome)
                return
            }
            guard let text = await model.pageText(), text.trimmingCharacters(in: .whitespacesAndNewlines).count > 200 else {
                message = "There’s nothing to read on this page yet. Wait for it to finish loading."
                return
            }
            if Self.looksLikeChart(text) {
                message = "Reading the chart… about half a minute."
                report(try await store.readChart(pdf: nil, text: text, horses: [horse]))
                return
            }
            message = "Reading \(horse.name)'s page… about half a minute."
            let outcome = try await store.readEquibasePage(text: text, for: horse.id)
            var parts: [String] = []
            if let entry = outcome.entry {
                parts.append(Summary.entryShort(entry))
            } else {
                parts.append("No upcoming entry shown" + (outcome.noEntryReason.map { " (\($0))" } ?? ""))
            }
            if outcome.updated > 0 { parts.append("\(outcome.updated) result\(outcome.updated == 1 ? "" : "s") updated") }
            if outcome.added > 0 { parts.append("\(outcome.added) result\(outcome.added == 1 ? "" : "s") added") }
            if outcome.updated == 0 && outcome.added == 0 { parts.append("no new results") }
            good = true
            message = parts.joined(separator: " · ") + "."
        } catch {
            message = error.localizedDescription
        }
    }

    private func report(_ outcome: ChartOutcome) {
        if outcome.added.isEmpty {
            message = "Not added: " + (outcome.skipped.first ?? "\(horse.name) isn’t in this chart.")
        } else {
            good = true
            message = "Added " + outcome.added.joined(separator: "; ") + "."
        }
    }

    /// A race chart (rather than the horse's page): charts print the race's value and fractional times.
    static func looksLikeChart(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("value of race") && (t.contains("fractional times") || t.contains("final time"))
    }
}

/// The web view and what the browser bar shows about it.
@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var title = ""
    @Published var canGoBack = false
    @Published var isLoading = false
    @Published var isPDF = false
    @Published var url: URL?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // stays signed in to Equibase between visits
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    private var started = false

    func load(_ url: URL) {
        guard !started else { return }
        started = true
        webView.load(URLRequest(url: url))
    }

    private func update() {
        title = webView.title ?? ""
        canGoBack = webView.canGoBack
        isLoading = webView.isLoading
        url = webView.url
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        update()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        update()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        update()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame {
            isPDF = navigationResponse.response.mimeType == "application/pdf"
        }
        return .allow
    }

    /// The text on screen.
    func pageText() async -> String? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { result, _ in
                continuation.resume(returning: result as? String)
            }
        }
    }

    /// The page as PDF (for a chart PDF on screen).
    func pdfData() async -> Data? {
        await withCheckedContinuation { continuation in
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }
}

struct BrowserView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
