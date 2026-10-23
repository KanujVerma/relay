import Foundation
import RelayAudioBuffer
import RelayNativeSession

public struct NativeCaptureConfiguration: Sendable {
    public let microphoneEnabled: Bool
    public let selectedBundleID: String?
    public let asrModelRoot: URL
    public let vadCompiledModel: URL
    public let authorizedConversation: Bool
    public let localModelLicensesAcknowledged: Bool
    public init(microphoneEnabled: Bool, selectedBundleID: String?, asrModelRoot: URL,
                vadCompiledModel: URL, authorizedConversation: Bool, localModelLicensesAcknowledged: Bool) {
        self.microphoneEnabled = microphoneEnabled; self.selectedBundleID = selectedBundleID
        self.asrModelRoot = asrModelRoot; self.vadCompiledModel = vadCompiledModel
        self.authorizedConversation = authorizedConversation
        self.localModelLicensesAcknowledged = localModelLicensesAcknowledged
    }
    public func validate() throws {
        guard authorizedConversation, localModelLicensesAcknowledged else { throw NativeSessionError.notAuthorized }
        guard microphoneEnabled || selectedBundleID != nil else { throw NativeSessionError.invalidConfiguration }
        if let selectedBundleID, !SelectedAppProcesses.isValidBundleID(selectedBundleID) {
            throw NativeSessionError.invalidConfiguration
        }
        guard asrModelRoot.isFileURL, vadCompiledModel.isFileURL,
              vadCompiledModel.pathExtension == "mlmodelc" else { throw NativeSessionError.invalidConfiguration }
    }
    public func validateLocalModels() throws {
        try validate()
        let asr = asrModelRoot.appendingPathComponent("parakeet-eou-streaming/320ms")
        let required = ["streaming_encoder.mlmodelc", "decoder.mlmodelc", "joint_decision.mlmodelc", "vocab.json"]
        guard FileManager.default.fileExists(atPath: vadCompiledModel.path), required.allSatisfy({
            FileManager.default.fileExists(atPath: asr.appendingPathComponent($0).path)
        }) else { throw NativeSessionError.modelUnavailable }
    }
}
