import SwiftUI

/// One button's content on its own pushed screen. Back returns to the sale's hip screen;
/// the bar at the bottom moves to the previous or next button's screen.
struct FieldScreen: View {
    @Environment(SaleStore.self) private var store
    let field: HipField
    @Binding var path: [Route]
    @State private var editing = false

    var body: some View {
        Group {
            if let hip = store.currentHip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(text: "Hip \(hip.number) · \(hip.title)")
                            Text(hip.cross)
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.slate)
                        }
                        FieldContent(field: field, hip: hip)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .task(id: "\(hip.number)-\(field.rawValue)-\(store.purchases.count)") {
                    if let slot = field.slot { await store.loadOpinion(slot, hip: hip) }
                }
                .sheet(isPresented: $editing) {
                    EditSheet(field: field, hip: hip, isNew: false)
                }
            } else {
                ContentUnavailableView("No hip selected", systemImage: "number")
            }
        }
        .background(Theme.page)
        .overlay(alignment: .bottom) { ErrorBanner() }
        .navigationTitle(field.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if store.canEdit(field) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editLabel) { editing = true }
                        .foregroundStyle(Theme.amber)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { pager }
    }

    private var editLabel: String {
        guard let slot = field.slot, let hip = store.currentHip else { return "Edit" }
        return hip.opinionsIn.contains(slot) ? "Edit" : "Post"
    }

    private var pager: some View {
        HStack {
            pagerButton(field.previous, leading: true)
            Spacer()
            Text("\(field.rawValue + 1) / \(HipField.allCases.count)")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.muted)
            Spacer()
            pagerButton(field.next, leading: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    @ViewBuilder
    private func pagerButton(_ target: HipField?, leading: Bool) -> some View {
        Button {
            guard let target, !path.isEmpty else { return }
            path[path.count - 1] = .field(target)
        } label: {
            HStack(spacing: 6) {
                if leading { Image(systemName: "chevron.left") }
                Text(target?.title ?? "")
                if !leading { Image(systemName: "chevron.right") }
            }
            .font(Theme.sans(15, .semibold))
            .frame(minWidth: 110, minHeight: 44, alignment: leading ? .leading : .trailing)
        }
        .disabled(target == nil)
        .opacity(target == nil ? 0 : 1)
    }
}
