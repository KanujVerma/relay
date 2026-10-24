import Foundation
import RelayNativeSession

/// An optional app-owned readiness boundary. Eligibility is a pure read. The
/// asynchronous operation must clean partial failure before throwing; a ready
/// lease that goes unused is closed and joined through its original intent.
@MainActor public struct TypedSessionPreparationPorts {
    public let canPrepareSession:@MainActor ()->Bool
    public let prepareSession:@MainActor (UUID,@escaping @MainActor ()->Bool)async throws->PresentationLease
    public let retireUnusedSession:@MainActor (UUID,PresentationLease)async->Void
    public init(canPrepareSession:@escaping @MainActor ()->Bool,
                prepareSession:@escaping @MainActor (UUID,@escaping @MainActor ()->Bool)async throws->PresentationLease,
                retireUnusedSession:@escaping @MainActor (UUID,PresentationLease)async->Void) {
        self.canPrepareSession=canPrepareSession;self.prepareSession=prepareSession
        self.retireUnusedSession=retireUnusedSession
    }
}
