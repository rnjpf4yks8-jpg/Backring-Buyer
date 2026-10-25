import SwiftUI

/// One sale's hip screen: a short header and all 10 buttons, sized to fit one iPhone screen without scrolling.
struct SaleView: View {
    @Environment(SaleStore.self) private var store
    let saleID: String
    @Binding var path: [Route]
    @State private var addingHip = false
    @State private var editingPanel = false
    @State private var showApprovals = false

    var body: some View {
        VStack(spacing: 0) {
            if store.sale.id == saleID, let hip = store.currentHip {
                HipHeader(hip: hip)
                FieldGrid(hip: hip) { path.append(.field($0)) }
                    .padding(16)
            } else {
                EmptySale(isLoading: store.isLoading || store.sale.id != saleID, canAdd: store.isStaff) { addingHip = true }
            }
        }
        .background(Theme.page)
        .overlay(alignment: .bottom) { ErrorBanner() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { SaleSwitcher(path: $path) }
            if store.isStaff {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showApprovals = true } label: {
                        Image(systemName: store.approvalQueue.isEmpty ? "checkmark.seal" : "checkmark.seal.fill")
                            .foregroundStyle(store.approvalQueue.isEmpty ? .white : Theme.amber)
                    }
                    .accessibilityLabel("Approvals, \(store.approvalQueue.count) waiting")
                    Button { editingPanel = true } label: {
                        Image(systemName: "person.2").foregroundStyle(.white)
                    }
                    .accessibilityLabel("Panel: vets and agents")
                    Button { addingHip = true } label: {
                        Image(systemName: "plus").foregroundStyle(.white)
                    }
                    .accessibilityLabel("Add hip")
                }
            }
        }
        .toolbarBackground(Theme.navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: saleID) { await store.open(saleID: saleID) }
        .sheet(isPresented: $editingPanel) { PanelSheet() }
        .sheet(isPresented: $showApprovals) { ApprovalsSheet(path: $path) }
        .sheet(isPresented: $addingHip) {
            EditSheet(field: .hipNumber, hip: Hip(number: (store.hips.last?.number ?? 0) + 1), isNew: true)
        }
    }
}

/// The title in a sale's bar. Tapping it lists every sale, so you can jump straight to another one.
private struct SaleSwitcher: View {
    @Environment(SaleStore.self) private var store
    @Binding var path: [Route]

    var body: some View {
        Menu {
            ForEach(store.sales, id: \.id) { sale in
                Button {
                    path = [.sale(sale.id)]
                } label: {
                    if sale.id == store.sale.id {
                        Label("\(sale.name) · \(sale.date)", systemImage: "checkmark")
                    } else {
                        Text("\(sale.name) · \(sale.date)")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(store.sale.name)
                    .font(Theme.sans(16, .bold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.amber)
            }
        }
        .accessibilityLabel("Switch sale, current: \(store.sale.name)")
    }
}

private struct EmptySale: View {
    let isLoading: Bool
    let canAdd: Bool
    let add: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            if isLoading {
                ProgressView()
            } else {
                Text("No hips in this sale yet").font(Theme.sans(18, .semibold)).foregroundStyle(Theme.ink)
                Text(canAdd ? "Add the first hip, or import the catalog spreadsheet." : "Backring Buyer staff are loading the catalog.")
                    .font(Theme.sans(15)).foregroundStyle(Theme.slate).multilineTextAlignment(.center)
                if canAdd {
                    Button("Add hip", action: add).buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct ErrorBanner: View {
    @Environment(SaleStore.self) private var store

    var body: some View {
        if let message = store.errorMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                Text(message).font(Theme.sans(14)).foregroundStyle(.white)
                Spacer(minLength: 0)
                Button { store.errorMessage = nil } label: { Image(systemName: "xmark").foregroundStyle(Theme.mist) }
                    .accessibilityLabel("Dismiss")
            }
            .padding(14)
            .background(Theme.navyCard, in: RoundedRectangle(cornerRadius: 12))
            .padding(16)
        }
    }
}

private struct HipHeader: View {
    @Environment(SaleStore.self) private var store
    let hip: Hip
    @State private var showGoTo = false
    @State private var goTo = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "\(store.sale.company) · \(store.sale.name)" + (hip.session.isEmpty ? "" : " · \(hip.session)"), color: Theme.amber)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .center, spacing: 8) {
                Button { goTo = ""; showGoTo = true } label: {
                    HStack(spacing: 8) {
                        Text("Hip \(hip.number)")
                            .font(Theme.mono(34, .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .contentTransition(.numericText())
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.amber)
                    }
                }
                .layoutPriority(1)
                .accessibilityLabel("Hip \(hip.number). Go to another hip")
                HipGrades(hip: hip)
                Spacer(minLength: 0)
                HipStepButton(symbol: "chevron.left", enabled: store.hasPreviousHip) { store.stepHip(-1) }
                    .accessibilityLabel("Previous hip")
                HipStepButton(symbol: "chevron.right", enabled: store.hasNextHip) { store.stepHip(1) }
                    .accessibilityLabel("Next hip")
            }
            Text("\(hip.title) · \(hip.cross)")
                .font(Theme.sans(15, .medium))
                .foregroundStyle(Theme.mist)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(hip.consignor) · \(hip.barn)")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.navy)
        .animation(.snappy, value: hip.number)
        .alert("Go to hip", isPresented: $showGoTo) {
            TextField("Hip number", text: $goTo)
                .keyboardType(.numberPad)
            Button("Go") { store.goToHip(goTo) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(store.sale.name) has \(store.hips.count.formatted()) hips.")
        }
    }
}

/// Backring Buyer's two grades beside the hip number: "8.0 · 4.5" (C · P), with their ranks in the sale under it.
/// Shows nothing until the hip is graded.
private struct HipGrades: View {
    @Environment(SaleStore.self) private var store
    let hip: Hip

    var body: some View {
        if hip.isGraded {
            let cRank = store.conformationRank(hip)
            let pRank = store.pedigreeRank(hip)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(text(hip.conformationGrade)) · \(text(hip.pedigreeGrade))")
                    .font(Theme.mono(15, .bold))
                    .foregroundStyle(Theme.amber)
                Text(ranks(c: cRank, p: pRank))
                    .font(Theme.sans(11, .medium))
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(cRank: cRank, pRank: pRank))
        }
    }

    private func text(_ grade: Double?) -> String {
        grade.map(Hip.gradeText) ?? "–"
    }

    private func ranks(c: Int?, p: Int?) -> String {
        "C \(c.map { "#\($0)" } ?? "–") · P \(p.map { "#\($0)" } ?? "–")"
    }

    private func spoken(cRank: Int?, pRank: Int?) -> String {
        let conformation = hip.conformationGrade.map {
            "Conformation \(Hip.gradeText($0)) of 10, rank \(cRank ?? 0) of \(store.conformationGradedCount)"
        } ?? "Conformation not graded"
        let pedigree = hip.pedigreeGrade.map {
            "pedigree \(Hip.gradeText($0)) of 5, rank \(pRank ?? 0) of \(store.pedigreeGradedCount)"
        } ?? "pedigree not graded"
        return "\(conformation); \(pedigree)"
    }
}

private struct HipStepButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(enabled ? .white : Theme.navyBorder)
                .overlay(Circle().stroke(enabled ? Color(hex: 0x3A4C72) : Theme.navyBorder))
        }
        .disabled(!enabled)
    }
}

/// 2 columns × 5 rows. Rows stretch to share the space left under the header, so nothing scrolls.
private struct FieldGrid: View {
    @Environment(SaleStore.self) private var store
    let hip: Hip
    let open: (HipField) -> Void

    private static let columns = 2

    // min() keeps the last row safe if the number of buttons is ever odd.
    private let rows: [[HipField]] = stride(from: 0, to: HipField.allCases.count, by: FieldGrid.columns).map {
        Array(HipField.allCases[$0..<min($0 + FieldGrid.columns, HipField.allCases.count)])
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row) { field in
                        let state = store.tileState(field, hip: hip)
                        FieldTile(field: field, summary: state.summary, locked: state.locked) {
                            open(field)
                        }
                    }
                }
            }
        }
    }
}

private struct FieldTile: View {
    let field: HipField
    let summary: String
    let locked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: field.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                    Spacer()
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.amber)
                    }
                    Text(String(format: "%02d", field.rawValue + 1))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 6)
                Text(field.title)
                    .font(Theme.sans(14, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(summary)
                    .font(Theme.sans(12, locked ? .semibold : .regular))
                    .foregroundStyle(locked ? Theme.orange : Theme.slate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("\(field.title), \(summary)")
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
