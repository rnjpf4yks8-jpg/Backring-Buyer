import SwiftUI

/// The app's one navigation stack: the sales list, then a sale's hip screen, then one of its 10 buttons.
struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            SalesIndexView { path = [.sale($0)] }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .sale(let id): SaleView(saleID: id, path: $path)
                    case .field(let field): FieldScreen(field: field, path: $path)
                    }
                }
        }
    }
}

/// Every sale HAINTEL covers, newest first. Tapping one opens its hips.
struct SalesIndexView: View {
    @Environment(SaleStore.self) private var store
    @State private var showAccount = false
    let open: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Sales")
                if store.sales.isEmpty {
                    if store.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        Text("No sales yet. HAINTEL staff add each sale before its catalog is loaded.")
                            .font(Theme.sans(15)).foregroundStyle(Theme.slate)
                    }
                }
                ForEach(store.sales, id: \.id) { sale in
                    Button { open(sale.id) } label: {
                        SaleRow(sale: sale, hipCount: store.hipCounts[sale.id],
                                featured: sale.id == store.featuredSaleID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .refreshable { await store.refreshSales() }
        .background(Theme.page)
        .overlay(alignment: .bottom) { ErrorBanner() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showAccount = true } label: {
                    Image(systemName: store.user == nil ? "person.crop.circle" : "person.crop.circle.fill")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Account")
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(Theme.amber)
                    Text("HAINTEL")
                        .font(Theme.sans(17, .bold))
                        .tracking(1)
                        .foregroundStyle(.white)
                }
            }
        }
        .toolbarBackground(Theme.navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showAccount) { AccountView() }
    }
}

private struct SaleRow: View {
    let sale: Sale
    let hipCount: Int?
    let featured: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(sale.company.uppercased())
                        .font(Theme.mono(11, .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.orange)
                    if featured {
                        Text("NOW")
                            .font(Theme.mono(10, .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.amber, in: Capsule())
                            .foregroundStyle(Theme.navy)
                    }
                }
                Text(sale.name)
                    .font(Theme.sans(18, .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text([sale.date, hipCount.map { "\($0.formatted()) hips" }].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.slate)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(featured ? Theme.amber : Theme.line))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let store = SaleStore(backend: SampleBackend())
    return RootView()
        .environment(store)
        .task { await store.start() }
}
