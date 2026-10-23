import Foundation
import SwiftUI

/// Optional composition seam. Constructing this model never activates the system picker.
@available(macOS 15.2, *)
@MainActor public final class ScreenContextModel: ObservableObject {
    public let coordinator: ScreenContextCoordinator
    private let capture: SystemSelectedWindowCapture
    @Published public private(set) var selectedSource: ScreenSource?
    @Published public private(set) var snapshot: ScreenSnapshot?
    @Published public private(set) var preview: CGImage?
    @Published public private(set) var status = "Screen context is off"
    @Published public private(set) var isEnabled = false
    /// Connect to native presentation-lease retirement, then helper context invalidation.
    public var onInvalidation: (@MainActor (ScreenFailure) -> Void)?
    public init() {
        let capture = SystemSelectedWindowCapture()
        self.capture = capture
        coordinator = ScreenContextCoordinator(provider: capture, recognizer: LocalVisionTextRecognizer())
        capture.onInvalidation = { [weak self] reason in
            self?.coordinator.sourceUnavailable(reason)
            self?.refresh()
        }
        capture.onSelection = { [weak self] source in
            self?.coordinator.select(source)
            self?.status = "Selected \(source.label)"
            self?.refresh()
        }
        coordinator.onInvalidation = { [weak self] reason in
            self?.refresh()
            self?.onInvalidation?(reason)
        }
    }
    public func enableAndSelect() {
        coordinator.enable(); isEnabled = true
        status = "Choose a window in the system picker"
        capture.presentSelection()
        refresh()
    }
    public func disable() {
        coordinator.disable(); capture.disable()
        isEnabled = false; status = "Screen context is off"
        refresh()
    }
    public func retireCurrentRequest() {
        coordinator.retireCurrentRequest()
        refresh()
    }
    public func supersede(with request: ScreenRequest) {
        coordinator.supersede(with: request)
        refresh()
    }
    /// Call at the authorized question boundary. A timeout produces no late context attachment.
    public func captureContext(for request: ScreenRequest, budgetNanoseconds: UInt64 = 1_500_000_000) async -> ScreenSnapshot? {
        coordinator.supersede(with: request)
        let result = await coordinator.capture(for: request, budgetNanoseconds: budgetNanoseconds)
        refresh()
        switch result {
        case .captured(let observed) where coordinator.owns(observed, for: request):
            status = "Text captured from \(observed.source.label)"
            return observed
        case .unavailable(let reason):
            if coordinator.isEnabled { status = reason.screenContextMessage }
            return nil
        default: return nil
        }
    }
    /// One bounded observation recheck on answer-ready. Caller rechecks its native lease after await.
    public func validateForPublication(_ observed: ScreenSnapshot, for request: ScreenRequest,
                                       budgetNanoseconds: UInt64 = 500_000_000, requiringImageIdentity: Bool = false) async -> Bool {
        let valid = await coordinator.validateCurrent(observed, for: request, budgetNanoseconds: budgetNanoseconds, requiringImageIdentity: requiringImageIdentity)
        refresh()
        return valid && coordinator.owns(observed, for: request)
    }
    private func refresh() {
        selectedSource = coordinator.selectedSource
        snapshot = coordinator.snapshot
        preview = coordinator.preview
        isEnabled = coordinator.isEnabled
    }
}

@available(macOS 15.2, *)
@MainActor public struct ScreenContextSettingsView: View {
    @ObservedObject private var model: ScreenContextModel
    public init(model: ScreenContextModel) { self.model = model }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optional screen context").font(.headline)
            Text("Choose one window to include its coding problem or visible text in this session.")
            HStack {
                Button(model.isEnabled ? "Choose another window" : "Enable and choose window") { model.enableAndSelect() }
                if model.isEnabled { Button("Disable") { model.disable() } }
            }
            Text(model.status).font(.caption)
            if let snapshot = model.snapshot {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let now = DispatchTime.now().uptimeNanoseconds
                    let age = now >= snapshot.capturedUptimeNanoseconds ? (now - snapshot.capturedUptimeNanoseconds) / 1_000_000_000 : 0
                    Text("\(snapshot.source.label) · captured \(age)s ago · local OCR").font(.caption)
                }
            }
            if let image = model.preview {
                Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 220)
                    .accessibilityLabel("Selected window capture preview")
            }
            if let text = model.snapshot?.text {
                ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 160)
            }
            Text("OCR may misread code symbols or omit diagram connections. Images stay in memory. Image understanding requires a supported model and separate enablement.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding()
    }
}

private extension ScreenFailure {
    var screenContextMessage: String {
        switch self {
        case .noSelection: "Choose a window to add screen context"
        case .denied: "Screen access was denied. Choose a window again."
        case .closed: "The selected window closed"
        case .timedOut: "Screen context took too long for this question"
        case .busy: "Screen context is finishing the previous capture"
        default: "Screen context is unavailable for this question"
        }
    }
}
