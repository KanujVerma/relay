import Foundation
import RelayNativeSession
import RelayScreenContext
import RelayControls

/// Host-owned description of the context actually supplied to generation.
public struct TaskContextUse: Sendable, Equatable {
    public let provenance: String
    public let source: String
    public let capturedUptimeNanoseconds: UInt64
    public init(provenance:String,source:String,capturedUptimeNanoseconds:UInt64) {
        self.provenance=provenance;self.source=source;self.capturedUptimeNanoseconds=capturedUptimeNanoseconds
    }
}

/// Reuses the reviewed selection/OCR ports. It never enables either capability.
/// Automatic questions use OCR; an explicit Help action may prefer selected text.
@MainActor public final class QuestionContextComposer {
    private enum Observation { case screen(ScreenSnapshot), selection(SelectedTextSnapshot) }
    private let authority:SessionPresentationAuthority
    private let screen:ScreenContextCoordinator
    private let selection:SelectedTextService
    public private(set) var binding:PanelRequestBinding?
    public private(set) var contextUse:TaskContextUse?
    private var observation:Observation?
    private var reobservedSelection:SelectedTextSnapshot?
    public init(authority:SessionPresentationAuthority,screen:ScreenContextCoordinator,selection:SelectedTextService) {
        self.authority=authority;self.screen=screen;self.selection=selection
    }
    public func retire() {
        binding=nil;contextUse=nil;observation=nil;reobservedSelection=nil
        selection.invalidate();screen.retireCurrentRequest()
    }
    public func capture(for request:PanelRequestBinding,readSelectedText:Bool) async -> [Data] {
        retire();binding=request
        guard current(request),!Task.isCancelled else { return [] }
        if readSelectedText,selection.isEnabled {
            do {
                let selected=try await selection.read(request:selectionRequest(request))
                guard !Task.isCancelled,current(request),selection.validateCurrent(selected) else { return [] }
                let frame=try Self.selectionFrame(selected)
                observation = .selection(selected)
                contextUse=TaskContextUse(provenance:selected.provenance,source:"Selected text: "+selected.application.bundleID,capturedUptimeNanoseconds:selected.capturedUptimeNanoseconds)
                return [frame]
            } catch { if Task.isCancelled || !current(request) { return [] } }
        }
        guard screen.isEnabled,!Task.isCancelled,current(request) else { return [] }
        let screenRequest=screenRequest(request)
        guard screen.supersede(with:screenRequest) else { return [] }
        let outcome=await screen.capture(for:screenRequest)
        guard !Task.isCancelled,current(request),case .captured(let observed)=outcome,screen.owns(observed,for:screenRequest) else { return [] }
        do {
            guard !observed.source.label.unicodeScalars.contains(where:{
                switch $0.properties.generalCategory {
                case .control,.format,.lineSeparator,.paragraphSeparator:true
                default:false
                }
            }) else { return [] }
            let frame=try ScreenContextWire.textFrame(observed)
            observation = .screen(observed)
            contextUse=TaskContextUse(provenance:"local_ocr",source:observed.source.label,capturedUptimeNanoseconds:observed.capturedUptimeNanoseconds)
            return [frame]
        } catch { return [] }
    }
    /// Bounded by the caller's terminal gate. A second read does not replace the
    /// original prompt capture's source/time; it supplies current matching proof.
    public func validateForPublication(_ request:PanelRequestBinding) async -> Bool {
        guard current(request),let observation else { return false }
        switch observation {
        case .screen(let observed):
            let valid=await screen.validateCurrent(observed,for:screenRequest(request),budgetNanoseconds:500_000_000)
            return !Task.isCancelled && valid && ownsCurrent(request)
        case .selection(let original):
            guard selection.validateCurrent(reobservedSelection ?? original) else { return false }
            do {
                let checked=try await selection.read(request:selectionRequest(request))
                guard !Task.isCancelled,current(request),original.text==checked.text,
                      original.application==checked.application,original.consentGeneration==checked.consentGeneration,
                      selection.validateCurrent(checked) else { return false }
                reobservedSelection=checked
                return ownsCurrent(request)
            } catch { return false }
        }
    }
    public func ownsCurrent(_ request:PanelRequestBinding) -> Bool {
        guard current(request),let observation else { return false }
        switch observation {
        case .screen(let observed):return screen.owns(observed,for:screenRequest(request))
        case .selection(let original):return selection.validateCurrent(reobservedSelection ?? original)
        }
    }
    private func current(_ request:PanelRequestBinding)->Bool { binding==request && authority.snapshot()==request.lease }
    private func screenRequest(_ r:PanelRequestBinding)->ScreenRequest {
        ScreenRequest(sessionID:r.lease.captureSessionID,sessionEpoch:r.lease.sessionEpoch,presentationGeneration:r.lease.presentationGeneration,requestID:r.requestID)
    }
    private func selectionRequest(_ r:PanelRequestBinding)->SelectionRequestIdentity {
        SelectionRequestIdentity(sessionID:r.lease.captureSessionID,sessionEpoch:r.lease.sessionEpoch,presentationGeneration:r.lease.presentationGeneration,requestID:r.requestID)
    }
    private static func selectionFrame(_ snapshot:SelectedTextSnapshot)throws->Data {
        let launch=snapshot.application.launchDate.timeIntervalSince1970*1000
        guard launch.isFinite,launch>0,launch<Double(UInt64.max),snapshot.application.processID>0,snapshot.application.bundleID.utf8.count<=120 else { throw SelectionError.applicationNotAllowed }
        let r=snapshot.request
        let value:WireValue = .object([
            "schemaVersion":.uint(1),"kind":.string("selected_text_context"),
            "captureSessionID":.string(r.sessionID.uuidString.lowercased()),"sessionEpoch":.uint(r.sessionEpoch),
            "presentationGeneration":.uint(r.presentationGeneration),"requestID":.string(r.requestID.uuidString.lowercased()),
            "source":.object(["bundleID":.string(snapshot.application.bundleID),"processID":.uint(UInt64(snapshot.application.processID)),"launchTimeMilliseconds":.uint(UInt64(launch))]),
            "consentGeneration":.string(snapshot.consentGeneration.uuidString.lowercased()),"observationID":.string(UUID().uuidString.lowercased()),
            "capturedUptimeNanoseconds":.uint(snapshot.capturedUptimeNanoseconds),"provenance":.string(snapshot.provenance),"text":.string(snapshot.text)])
        let data=try JSONEncoder().encode(value)
        guard data.count<=16_384 else { throw SelectionError.tooLarge }
        return data
    }
}
