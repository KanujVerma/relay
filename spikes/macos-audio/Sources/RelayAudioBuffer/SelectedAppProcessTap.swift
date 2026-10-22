import AudioToolbox
import CoreAudio
import Foundation

// Select-app lifecycle and private tap/aggregate creation adapted from
// MIT SystemAudioKit's ProcessTapCapture.swift, pinned revision
// ccc6ab1e53b27e16b2eb4c01890560568a73d38c.
// Relay publishes owned in-memory PCM instead of AlignedTrackWriter WAV.
// See ../../THIRD_PARTY_NOTICES.md for the complete attribution.

public enum SelectedAppTapState: String, Sendable {
    case stopped
    case captureAttemptedPermissionUnverified
    case selectedAppUnavailable
    case captureError
}

/// Uses one serial control queue for all HAL lifecycle mutations. The Core Audio
/// IOProc never enters this queue or takes a lock. A separate callback queue
/// is a single producer for the remote audio SPSC ring. Listener callbacks
/// enqueue state reconciliation; their callbacks never modify HAL in place.
public final class SelectedAppProcessTap: @unchecked Sendable {
    private let audioQueue: OwnedPCMQueue
    private let control = DispatchQueue(label: "Relay.SelectedAppTap.control")
    private let controlKey = DispatchSpecificKey<UInt8>()
    private let callbacks = DispatchQueue(
        label: "Relay.SelectedAppTap.callbacks", qos: .userInitiated
    )
    private let notifications = DispatchQueue(
        label: "Relay.SelectedAppTap.notifications", qos: .utility
    )

    // Control queue only.
    private var desiredBundle: String?
    private var activeProcessIDs: [AudioObjectID] = []
    private var tapID = AudioObjectID.tapUnknown
    private var aggregateID = AudioObjectID.tapUnknown
    private var ioProc: AudioDeviceIOProcID?
    private var generation: UInt64 = 0
    private var currentState: SelectedAppTapState = .stopped
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var processesListener: AudioObjectPropertyListenerBlock?

    public init(queue: OwnedPCMQueue) {
        audioQueue = queue
        control.setSpecific(key: controlKey, value: 1)
    }

    private func onControl<T>(_ action: () throws -> T) rethrows -> T {
        // A listener callback may hold the final strong reference on the
        // control queue. Avoid sync-to-self deadlock during deinit/stop.
        if DispatchQueue.getSpecific(key: controlKey) != nil {
            return try action()
        }
        return try control.sync(execute: action)
    }

    public var status: SelectedAppTapState {
        onControl { currentState }
    }

    /// The caller must have explicitly requested a specific app and consented
    /// to system audio capture. The OS may prompt on AudioDeviceStart.
    ///
    /// There is NO public process-tap TCC preflight. Creating a tap or even
    /// receiving zeroed buffers is NOT proof of authorization.
    @discardableResult
    public func start(bundleID: String) throws -> UInt64 {
        try onControl {
            guard desiredBundle == nil else {
                throw ProcessTapError.alreadyCapturing
            }
            guard SelectedAppProcesses.isValidBundleID(bundleID) else {
                throw ProcessTapError.invalidBundleID
            }
            guard let message = Bundle.main.object(
                forInfoDictionaryKey: "NSAudioCaptureUsageDescription"
            ) as? String, !message.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                throw ProcessTapError.usageDescriptionMissing
            }
            let ids = SelectedAppProcesses.objectIDs(for: bundleID)
            guard !ids.isEmpty else {
                throw ProcessTapError.noMatchingProcesses
            }
            desiredBundle = bundleID
            do {
                try build(for: ids)
                installListeners()
                return generation
            } catch {
                removeListeners()
                teardown()
                desiredBundle = nil
                currentState = .captureError
                throw error
            }
        }
    }

    public func stop() {
        onControl {
            desiredBundle = nil
            removeListeners()
            teardown()
            currentState = .stopped
        }
    }

    deinit {
        // Owner must stop and join the producer BEFORE releasing the queue.
        stop()
    }

    private func build(for ids: [AudioObjectID]) throws {
        guard !ids.isEmpty else { throw ProcessTapError.noMatchingProcesses }
        // Selection is ONLY this group of process objects, never a global tap.
        let description = CATapDescription(monoMixdownOfProcesses: ids)
        description.uuid = UUID()
        description.name = "Relay Selected-App Output"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTap = AudioObjectID.tapUnknown
        try tapCheck(AudioHardwareCreateProcessTap(
            description, &newTap
        ), "Creating selected-app process tap")

        var newAggregate = AudioObjectID.tapUnknown
        var newProc: AudioDeviceIOProcID?
        var started = false
        var succeeded = false
        defer {
            if !succeeded {
                if newAggregate != .tapUnknown {
                    if started { _ = AudioDeviceStop(newAggregate, newProc) }
                    if let newProc {
                        AudioDeviceDestroyIOProcID(newAggregate, newProc)
                    }
                    AudioHardwareDestroyAggregateDevice(newAggregate)
                }
                AudioHardwareDestroyProcessTap(newTap)
                callbacks.sync {}
            }
        }

        let descriptionFormat = try newTap.tapRead(
            kAudioTapPropertyFormat, default: AudioStreamBasicDescription()
        )
        let format = try ProcessTapPCMFormat(descriptionFormat)

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Relay Selected-App Private Tap",
            kAudioAggregateDeviceUIDKey: "RelayTap-\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try tapCheck(AudioHardwareCreateAggregateDevice(
            aggregate as CFDictionary, &newAggregate
        ), "Creating private tap aggregate device")

        generation &+= 1
        let thisGeneration = generation
        let ring = audioQueue
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newProc, newAggregate, callbacks
        ) { _, input, inputTime, _, _ in
            let time = inputTime.pointee
            let hostTime = time.mFlags.contains(.hostTimeValid)
                ? time.mHostTime : 0
            _ = ProcessTapPCMBridge.publish(
                input,
                format: format,
                queue: ring,
                hostTime: hostTime,
                generation: thisGeneration
            )
        }
        try tapCheck(ioStatus, "Registering selected-app audio callback")
        guard let newProc else { throw ProcessTapError.unavailable }
        try tapCheck(
            AudioDeviceStart(newAggregate, newProc),
            "Starting selected-app audio callback"
        )
        started = true

        // This means the Core Audio tap started, NOT that TCC granted it.
        tapID = newTap
        aggregateID = newAggregate
        ioProc = newProc
        activeProcessIDs = ids
        currentState = .captureAttemptedPermissionUnverified
        succeeded = true
    }

    private func teardown() {
        let oldTap = tapID
        let oldAggregate = aggregateID
        let oldProc = ioProc
        tapID = .tapUnknown
        aggregateID = .tapUnknown
        ioProc = nil
        activeProcessIDs = []

        if oldAggregate != .tapUnknown {
            _ = AudioDeviceStop(oldAggregate, oldProc)
            if let oldProc {
                AudioDeviceDestroyIOProcID(oldAggregate, oldProc)
            }
            AudioHardwareDestroyAggregateDevice(oldAggregate)
        }
        if oldTap != .tapUnknown {
            AudioHardwareDestroyProcessTap(oldTap)
        }
        // Ensure no callbacks from the old producer remain before a new IOProc
        // starts using the same SPSC queue.
        callbacks.sync {}
    }

    private func installListeners() {
        let output: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.control.async { [weak self] in
                self?.reconcile(forceRebuild: true)
            }
        }
        let process: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.control.async { [weak self] in
                self?.reconcile(forceRebuild: false)
            }
        }
        var outputAddr = tapAddress(kAudioHardwarePropertyDefaultOutputDevice)
        if AudioObjectAddPropertyListenerBlock(
            .tapSystem, &outputAddr, notifications, output
        ) == noErr {
            outputListener = output
        }
        var processAddr = tapAddress(kAudioHardwarePropertyProcessObjectList)
        if AudioObjectAddPropertyListenerBlock(
            .tapSystem, &processAddr, notifications, process
        ) == noErr {
            processesListener = process
        }
    }

    private func removeListeners() {
        if let outputListener {
            var address = tapAddress(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(
                .tapSystem, &address, notifications, outputListener
            )
            self.outputListener = nil
        }
        if let processesListener {
            var address = tapAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(
                .tapSystem, &address, notifications, processesListener
            )
            self.processesListener = nil
        }
    }

    private func reconcile(forceRebuild: Bool) {
        guard let selected = desiredBundle else { return }
        let current = SelectedAppProcesses.objectIDs(for: selected)
        if !forceRebuild, current == activeProcessIDs { return }
        // App quit/relaunch or output changed. No global fallback.
        teardown()
        guard !current.isEmpty else {
            currentState = .selectedAppUnavailable
            return
        }
        do {
            try build(for: current)
        } catch {
            currentState = .captureError
            // Remain stopped until another hardware/process notification.
        }
    }
}
