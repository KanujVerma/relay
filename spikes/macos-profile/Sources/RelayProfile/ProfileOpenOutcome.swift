/// Actual protected-profile open result. Missing never means an empty profile
/// was created; callers must not treat unavailable or stale as ready.
public enum ProfileOpenOutcome:Sendable,Equatable {
    case opened,missing,unavailable,stale
}
