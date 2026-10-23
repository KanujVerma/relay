import Dispatch
import Foundation
import RelayAudioBuffer

/// Synchronous native session authority. The sink must enqueue bounded work and
/// return immediately; throwing fails the session closed. Never block it on a
/// helper read/write. The panel owns transport and calls retire on transport loss.
public final class NativeSessionController: @unchecked Sendable {
    public let authority: SessionPresentationAuthority
    private let lock = NSRecursiveLock()
    private let onEvent: @Sendable (NativeSessionEvent) throws -> Void
    private var sources: [UInt32: SourcePipeline] = [:]
    private var retiredSources: [SourcePipeline] = []
    private var sessionID: UUID?
    private var sequence: UInt64 = 0
    private var currentRequestID: UUID?
    private var segmentCounters: [UInt32: UInt64] = [:]
    private var stoppingLease: PresentationLease?
    private var stopReason: SessionReason = .userStop

    public init(authority: SessionPresentationAuthority = SessionPresentationAuthority(),
                onEvent: @escaping @Sendable (NativeSessionEvent) throws -> Void) {
        self.authority = authority; self.onEvent = onEvent
    }
    public func start(selectedBundleID: String?, microphoneEnabled: Bool,
                      components: [UInt32: SourceComponents]) throws {
        try lock.withLock {
            guard sessionID == nil, retiredSources.isEmpty else { throw NativeSessionError.alreadyRunning }
            var expected: Set<UInt32> = microphoneEnabled ? [1] : []
            if let selectedBundleID {
                guard SelectedAppProcesses.isValidBundleID(selectedBundleID) else { throw NativeSessionError.invalidConfiguration }
                expected.insert(2)
            }
            guard !expected.isEmpty, Set(components.keys) == expected else { throw NativeSessionError.invalidConfiguration }
            let lease = try authority.start()
            sessionID = lease.captureSessionID; sequence = 0; stoppingLease = nil; segmentCounters = [:]
            for (code, component) in components {
                guard let source = PCMSource(rawValue: code) else { throw NativeSessionError.invalidConfiguration }
                sources[code] = SourcePipeline(source: source, components: component,
                    onStart: { [weak self] activity, generation, ticks, clock in
                        self?.speechStarted(session: lease.captureSessionID, source: code,
                            activity: activity, generation: generation, ticks: ticks, clock: clock)
                    }, onEnd: { [weak self] activity in
                        self?.speechEnded(session: lease.captureSessionID, source: code, activity: activity)
                    }, onFinal: { [weak self] activity, text in
                        self?.finalized(session: lease.captureSessionID, source: code, activity: activity, text: text)
                    }, onFailure: { [weak self] reason, generation in
                        self?.sourceUnavailable(session: lease.captureSessionID, source: code, generation: generation, reason: reason)
                    })
            }
            emit(kind: .sessionStarted, lease: lease, payload: [
                "selectedBundleID": selectedBundleID.map(WireValue.string) ?? .null,
                "microphoneEnabled": .bool(microphoneEnabled)])
            guard sessionID != nil else { throw NativeSessionError.transportClosed }
        }
    }
    /// Atomically orders explicit Help after exactly the native events already
    /// forwarded by the app. A stamped but queued event makes the anchor stale.
    /// The bounded ingress callback must enqueue synchronously and never await
    /// helper IO. This method does not consume the global audio event sequence.
    public func issueManualHelp(expectedEventSequence: UInt64, expectedLease: PresentationLease,
                                question: String,
                                enqueue: @Sendable (NativeManualHelpRequest) throws -> Void) throws -> NativeManualHelpRequest {
        try lock.withLock {
            guard sessionID == expectedLease.captureSessionID,
                  sequence == expectedEventSequence, expectedEventSequence > 0,
                  authority.snapshot() == expectedLease,
                  !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  question.utf8.count <= 500,
                  !question.unicodeScalars.contains(where: {
                      switch $0.properties.generalCategory {
                      case .control, .format, .lineSeparator, .paragraphSeparator: true
                      default: false
                      }
                  }) else { throw NativeSessionError.notAuthorized }
            guard let lease = authority.invalidate() else { transportFailed(); throw NativeSessionError.notAuthorized }
            let issued = NativeManualHelpRequest(lease: lease, requestID: UUID(),
                anchorEventSequence: sequence, emittedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                question: question)
            currentRequestID=issued.requestID
            do { try enqueue(issued) }
            catch { transportFailed(); throw NativeSessionError.transportClosed }
            return issued
        }
    }
    /// Capture the actual native anchor and enqueue under the same source lock.
    public func issueUserQuestion(expectedLease:PresentationLease,intent:UserQuestionIntent,
                                  question:String?,baseRequestID:UUID?,
                                  enqueue:@Sendable(NativeUserQuestionRequest)throws->Void)throws->NativeUserQuestionRequest {
        try lock.withLock {
            guard sessionID==expectedLease.captureSessionID,sequence>0,authority.snapshot()==expectedLease else{throw NativeSessionError.notAuthorized}
            switch intent {
            case .ask:
                guard let question,!question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                      question.utf8.count<=500,!question.unicodeScalars.contains(where:{
                          switch $0.properties.generalCategory{case .control,.format,.lineSeparator,.paragraphSeparator:true;default:false}
                      }) else{throw NativeSessionError.notAuthorized}
            case .helpCurrent:
                guard question==nil,let baseRequestID,baseRequestID==currentRequestID else{throw NativeSessionError.notAuthorized}
            }
            guard let lease=authority.invalidate() else{transportFailed();throw NativeSessionError.notAuthorized}
            let request=NativeUserQuestionRequest(lease:lease,requestID:UUID(),anchorEventSequence:sequence,
                emittedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds,intent:intent,question:question,baseRequestID:baseRequestID)
            currentRequestID=request.requestID
            do{try enqueue(request)}catch{transportFailed();throw NativeSessionError.transportClosed}
            return request
        }
    }
    public func issueAnswerCancellation(expectedLease:PresentationLease,targetRequestID:UUID,
                                        enqueue:@Sendable(NativeAnswerCancelRequest)throws->Void)throws->NativeAnswerCancelRequest {
        try lock.withLock {
            guard sessionID==expectedLease.captureSessionID,sequence>0,authority.snapshot()==expectedLease,
                  currentRequestID==targetRequestID else{throw NativeSessionError.notAuthorized}
            guard let lease=authority.invalidate() else{transportFailed();throw NativeSessionError.notAuthorized}
            let request=NativeAnswerCancelRequest(lease:lease,requestID:UUID(),anchorEventSequence:sequence,
                emittedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds,targetRequestID:targetRequestID,targetLease:expectedLease)
            currentRequestID=nil
            do{try enqueue(request)}catch{transportFailed();throw NativeSessionError.transportClosed}
            return request
        }
    }
    public func isSourceActive(_ source: PCMSource) -> Bool {
        lock.withLock { sources[source.rawValue] != nil && authority.snapshot() != nil }
    }
    public func ingest(_ packet: SessionAudioPacket) {
        lock.withLock { sources[packet.source.rawValue]?.enqueue(packet) }
    }
    public func sourceUnavailable(source: PCMSource, generation: UInt64, reason: SessionReason) {
        lock.withLock {
            guard let sessionID else { return }
            sourceUnavailable(session: sessionID, source: source.rawValue, generation: generation, reason: reason)
        }
    }
    /// Close admission and paint authority BEFORE capture/model shutdown awaits.
    public func beginStop(reason: SessionReason = .userStop) {
        lock.withLock {
            guard sessionID != nil else { return }
            guard let lease = authority.snapshot() else {
                // A failed writer can withdraw the shared authority first.
                // Still cancel and retain all model/source owners for join.
                retireSources(); sessionID = nil; stoppingLease = nil
                return
            }
            stoppingLease = authority.invalidate() ?? lease; stopReason = reason
            authority.stop()
            retireSources()
            if let stoppingLease { emit(kind: .stopping, lease: stoppingLease,
                payload: ["reasonCode": .string(reason.rawValue)]) }
        }
    }
    /// quiesced is supplied only after actual producer, VAD and ASR ownership
    /// has returned. A UI deadline alone cannot supply true.
    public func finishStop(quiesced: Bool) {
        lock.withLock {
            guard let lease = stoppingLease, sessionID != nil else { return }
            emit(kind: .stopped, lease: lease, payload: ["reasonCode": .string(stopReason.rawValue), "quiesced": .bool(quiesced)])
            sessionID = nil; stoppingLease = nil
        }
    }
    public func stop(reason: SessionReason = .userStop) { beginStop(reason: reason); finishStop(quiesced: false) }
    /// Join cancelled source tasks before reusing this controller. The capture
    /// wrapper includes this in its bounded shutdown operation and keeps model
    /// owners alive after timeout until an uncancellable CoreML await returns.
    public func waitForQuiescence() async {
        let retired = lock.withLock { retiredSources }
        for source in retired { await source.waitForQuiescence() }
        lock.withLock { retiredSources.removeAll { source in retired.contains { $0 === source } } }
    }
    public func retire(reason: SessionReason = .transportClosed) { stop(reason: reason) }

    private func speechStarted(session: UUID, source: UInt32, activity: UInt64, generation: UInt64,
                               ticks: UInt64, clock: NativeClockCalibration) -> PresentationLease? {
        lock.withLock {
            guard sessionID == session, sources[source] != nil, authority.snapshot() != nil else { return nil }
            // User mic replies update conversation context while the remote
            // talking points stay visible. Only remote onset retires that lease.
            guard let lease = source == 2 ? authority.invalidate() : authority.snapshot() else { return nil }
            if source==2{currentRequestID=nil}
            emit(kind: .speechStarted, lease: lease, source: source, generation: generation, payload: [
                "activityID": .uint(activity), "startHostTime": .uint(ticks),
                "detectedUptimeNanoseconds": .uint(DispatchTime.now().uptimeNanoseconds), "timebase": clock.wire])
            return lease
        }
    }
    private func speechEnded(session: UUID, source: UInt32, activity: ClosedActivity) {
        lock.withLock {
            guard sessionID == session, sources[source] != nil, authority.snapshot() != nil else { return }
            emit(kind: .speechEnded, lease: activity.lease, source: source, generation: activity.generation, payload: [
                "activityID": .uint(activity.id), "endHostTime": .uint(activity.endHostTime),
                "lastSpeechInputSequence": .uint(activity.lastSequence), "timebase": activity.clock.wire])
        }
    }
    private func finalized(session: UUID, source: UInt32, activity: ClosedActivity, text: String) {
        lock.withLock {
            guard sessionID == session, sources[source] != nil, authority.snapshot() != nil else { return }
            let finalized = DispatchTime.now().uptimeNanoseconds
            do {
                let start = try activity.clock.uptimeNanoseconds(forHostTicks: activity.startHostTime)
                let end = try activity.clock.uptimeNanoseconds(forHostTicks: activity.endHostTime)
                guard start <= end, end <= finalized,
                      finalized >= activity.clock.uptimeNsAtAnchor,
                      finalized - activity.clock.uptimeNsAtAnchor <= 600_000_000_000,
                      text.count <= 1200, !text.contains("\0") else { throw NativeSessionError.invalidClock }
            } catch {
                sourceUnavailable(session: session, source: source, generation: activity.generation, reason: .clockInvalid)
                return
            }
            guard (segmentCounters[source] ?? 0) < UInt64.max else {
                sourceUnavailable(session: session, source: source, generation: activity.generation, reason: .asrUnavailable)
                return
            }
            // This final has consumed exactly the closed activity supplied to
            // recognize(). Segment identity is allocated here independently of
            // the VAD activity counter and explicitly associated in the payload.
            let segment = (segmentCounters[source] ?? 0) + 1
            segmentCounters[source] = segment
            let inner: [String: WireValue] = [
                "version": .uint(1), "status": .string("final"), "sourceCode": .uint(UInt64(source)),
                "streamGeneration": .uint(activity.generation), "segmentID": .uint(segment), "revision": .uint(1),
                "startHostTime": .uint(activity.startHostTime), "endHostTime": .uint(activity.endHostTime),
                "finalizedUptimeNanoseconds": .uint(finalized),
                "receivedUptimeNanoseconds": .uint(DispatchTime.now().uptimeNanoseconds),
                "text": .string(text), "confidence": .null, "timebase": activity.clock.wire]
            let requestID=source == 2 ? UUID():nil
            if source==2,authority.snapshot()==activity.lease{currentRequestID=requestID}
            emit(kind: .eou, lease: activity.lease, source: source, generation: activity.generation,
                 payload: ["event": .object(inner), "activityID": .uint(activity.id),
                    "firstInputSequence": .uint(activity.firstSequence), "lastInputSequence": .uint(activity.lastSequence),
                    "activityClosed": .bool(true), "lastSpeechInputSequence": .uint(activity.lastSequence)],
                 requestID: requestID)
        }
    }
    private func sourceUnavailable(session: UUID, source: UInt32, generation: UInt64, reason: SessionReason) {
        lock.withLock {
            guard sessionID == session, let pipeline = sources.removeValue(forKey: source) else { return }
            pipeline.stop(); retiredSources.append(pipeline)
            guard let lease = source == 2 ? authority.invalidate() : authority.snapshot() else { return }
            let kind: SessionEventKind = [.deviceChanged, .sequenceGap, .queueOverflow, .clockInvalid].contains(reason) ? .discontinuity : .sourceUnavailable
            emit(kind: kind, lease: lease, source: source, generation: generation,
                 payload: ["reasonCode": .string(reason.rawValue)])
        }
    }
    private func emit(kind: SessionEventKind, lease: PresentationLease, source: UInt32? = nil,
                      generation: UInt64? = nil, payload: [String: WireValue], requestID: UUID? = nil) {
        guard sequence < UInt64.max else { transportFailed(); return }
        sequence += 1
        do {
            try onEvent(NativeSessionEvent(captureSessionID: lease.captureSessionID, sessionEpoch: lease.sessionEpoch,
                eventSequence: sequence, presentationGeneration: lease.presentationGeneration, kind: kind,
                sourceCode: source, streamGeneration: generation, emittedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                payload: payload, requestID: requestID))
        } catch { transportFailed() }
    }
    private func retireSources() {
        currentRequestID=nil
        let retiring = Array(sources.values)
        sources.removeAll()
        retiring.forEach { $0.stop() }
        retiredSources.append(contentsOf: retiring)
    }
    private func transportFailed() {
        authority.stop(); retireSources()
        sessionID = nil; stoppingLease = nil
    }
}
