import SwiftUI

/// Staff only: every vet and agent opinion in the open sale that's waiting for approval.
/// Tapping one opens it, with Approve and Return buttons at the top.
struct ApprovalsSheet: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var path: [Route]

    var body: some View {
        NavigationStack {
            List {
                if store.approvalQueue.isEmpty {
                    Text("Nothing waiting. New vet and agent opinions show up here before buyers can see them.")
                        .font(Theme.sans(15)).foregroundStyle(Theme.slate)
                }
                ForEach(store.approvalQueue, id: \.key) { item in
                    Button {
                        store.currentHipNumber = item.hip.number
                        // Opens Vet Opinions or Bloodstock Opinions with this opinion picked in its menu.
                        store.selectedSlots[item.slot.field] = item.slot
                        path = [.sale(store.sale.id), .field(item.slot.field)]
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hip \(item.hip.number) · \(item.slot.title)")
                                    .font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink)
                                Text(store.sale.member(item.slot)?.name ?? "")
                                    .font(Theme.sans(14)).foregroundStyle(Theme.slate)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .navigationTitle("Approvals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await store.open(saleID: store.sale.id) }
        }
    }
}
