import Foundation
import RelayNativeSession

/// An optional app-owned readiness boundary. Eligibility is a pure read. The
/// asynchronous operation must clean partial failure before throwing; a ready
/// lease that goes unused is closed and joined through its original intent.
@MainActor public struct TypedSessionPreparationPorts {
    public let canPrepareSession:()->Bool
    public let prepareSession:(UUID,@escaping @MainActor ()->Bool)async throws->PresentationLease
    public let retireUnusedSession:(UUID,PresentationLease)async->Void
    public init(canPrepareSession:@escaping()->Bool,
                prepareSession:@escaping(UUID,@escaping @MainActor ()->Bool)async throws->PresentationLease,
                retireUnusedSession:@escaping(UUID,PresentationLease)async->Void) {
        self.canPrepareSession=canPrepareSession;self.prepareSession=prepareSession
        self.retireUnusedSession=retireUnusedSession
    }
}
