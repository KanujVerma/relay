import SwiftUI
import RelayPanelState

// An ordinary visible window. There is intentionally no always-on-top,
// non-activating, click-through, screen-share or recording behavior.
@main
struct RelayPanelPrototypeApp: App {
    var body: some Scene {
        Window("Relay — Offline Demo", id: "relay-panel-demo") {
            RelayPanelView()
        }
        .defaultSize(width: 520, height: 470)
    }
}

private struct RelayPanelView: View {
    @State private var state = PanelState()
    @State private var generation: UInt64 = 0
    @State private var showExample = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Relay").font(.title2.bold())
                Spacer()
                Text("OFFLINE DEMO")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("Offline demonstration only")
            }
            HStack(spacing: 14) {
                Label("Audio OFF", systemImage: "mic.slash")
                Label("No AI request", systemImage: "network.slash")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            Text("Current question").font(.caption).foregroundStyle(.secondary)
            Text(state.question ?? "No active question")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Divider()
            Label(statusText, systemImage: statusIcon)
                .font(.subheadline.bold())
            if let card = state.card, state.status == .finalUnverified {
                Text(card.lead)
                    .font(.body)
                    .textSelection(.enabled)
                    .accessibilityLabel("Sample unverified talking point: " + card.lead)
                ForEach(card.points, id: \.self) { point in
                    Text("• " + point)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                if let detail = card.detail {
                    DisclosureGroup("Illustrative SQL example", isExpanded: $showExample) {
                        Text(detail)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if let reason = state.reason {
                Text(reason.label).foregroundStyle(.secondary)
            } else if state.status == .waiting {
                Text("Waiting for a completed, approved sample card.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No answer is available to display.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Divider()
            HStack {
                Button("New question") { startQuestion(corrected: false) }
                    .disabled(state.isStopped)
                Button("Correction") { startQuestion(corrected: true) }
                    .disabled(state.isStopped)
                Button("Show sample card") { publishSample() }
                    .disabled(state.status != .waiting)
            }
            HStack {
                Button("Withhold") { withholdCurrent() }
                    .disabled(state.currentTurn == nil || state.status == .needsReview)
                Button("Stop") {
                    _ = state.apply(.stop)
                    showExample = false
                }
                .disabled(state.isStopped)
                Button("Resume") {
                    _ = state.apply(.resume)
                }
                .disabled(!state.isStopped)
                Spacer()
                Text("No transcript or answer is stored")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 390)
        .onAppear {
            if state.currentTurn == nil && !state.isStopped && generation == 0 {
                startQuestion(corrected: false)
            }
        }
    }

    private var statusText: String {
        switch state.status {
        case .idle: "Idle — no active turn"
        case .waiting: "Waiting for sample answer"
        case .finalUnverified: "Sample answer — technical correctness unverified"
        case .needsReview: "Withheld — review required"
        case .unavailable: "Stopped — assistance unavailable"
        }
    }

    private var statusIcon: String {
        switch state.status {
        case .idle: "circle.dotted"
        case .waiting: "hourglass"
        case .finalUnverified: "text.bubble"
        case .needsReview: "exclamationmark.shield"
        case .unavailable: "stop.circle"
        }
    }

    private func startQuestion(corrected: Bool) {
        generation += 1
        let keyName = corrected ? "demo-correction-\(generation)" : "demo-question-\(generation)"
        guard let key = TurnKey(identifier: keyName, revision: 1, generation: generation) else { return }
        let question = corrected
            ? "Actually, how do WHERE and HAVING differ when aggregation is involved?"
            : "What is the difference between SQL WHERE and HAVING?"
        _ = state.apply(.begin(turn: key, question: question))
        showExample = false
    }

    private func publishSample() {
        guard let key = state.currentTurn,
              let sample = PanelCard(
                lead: "WHERE filters rows before grouping; HAVING filters groups after aggregation.",
                points: [
                    "Use WHERE for row conditions before GROUP BY.",
                    "Use HAVING for aggregate conditions such as COUNT(*) > 1."
                ],
                detail: "SELECT region, COUNT(*) FROM orders WHERE status = 'paid' GROUP BY region HAVING COUNT(*) > 1;"
              ) else { return }
        _ = state.apply(.publish(turn: key, card: sample))
    }

    private func withholdCurrent() {
        guard let key = state.currentTurn else { return }
        _ = state.apply(.withhold(turn: key, reason: .validationRequired))
        showExample = false
    }
}
