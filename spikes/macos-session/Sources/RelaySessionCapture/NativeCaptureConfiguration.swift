import Foundation
import RelayAudioBuffer
import RelayNativeSession

public struct NativeCaptureConfiguration: Sendable {
    private enum DependencyPolicy:Sendable {case explicitLocalAcknowledgment(Bool),reviewedManagedManifest(String)}
    public let microphoneEnabled: Bool
    public let selectedBundleID: String?
    public let asrModelRoot: URL
    public let vadCompiledModel: URL
    public let authorizedConversation: Bool
    public let localModelLicensesAcknowledged: Bool
    private let dependencyPolicy:DependencyPolicy
    public init(microphoneEnabled: Bool, selectedBundleID: String?, asrModelRoot: URL,
                vadCompiledModel: URL, authorizedConversation: Bool, localModelLicensesAcknowledged: Bool) {
        self.microphoneEnabled = microphoneEnabled; self.selectedBundleID = selectedBundleID
        self.asrModelRoot = asrModelRoot; self.vadCompiledModel = vadCompiledModel
        self.authorizedConversation = authorizedConversation
        self.localModelLicensesAcknowledged = localModelLicensesAcknowledged
        self.dependencyPolicy = .explicitLocalAcknowledgment(localModelLicensesAcknowledged)
    }
    /// Managed dependency review is established by the internally issued
    /// asset plan, never by file existence or a fabricated user attestation.
    public init(microphoneEnabled:Bool,selectedBundleID:String?,preparedSpeechAssets:PreparedSpeechAssets,authorizedConversation:Bool){
        self.microphoneEnabled=microphoneEnabled;self.selectedBundleID=selectedBundleID
        self.asrModelRoot=preparedSpeechAssets.asrModelRoot;self.vadCompiledModel=preparedSpeechAssets.vadCompiledModel
        self.authorizedConversation=authorizedConversation;self.localModelLicensesAcknowledged=false
        self.dependencyPolicy = .reviewedManagedManifest(preparedSpeechAssets.manifestID)
    }
    public func validate() throws {
        guard authorizedConversation else { throw NativeSessionError.notAuthorized }
        switch dependencyPolicy {
        case .explicitLocalAcknowledgment(let accepted):guard accepted else{throw NativeSessionError.notAuthorized}
        case .reviewedManagedManifest(let identity):guard !identity.isEmpty else{throw NativeSessionError.notAuthorized}
        }
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
