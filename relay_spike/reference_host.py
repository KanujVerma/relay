"""B3A-3: zero-network host publication of exact reviewed technical references.

This is a trusted HOST adapter over B3A-2's offline publication policy and
B1's existing ActiveTurns; it is NOT a native macOS bridge, speech pipeline,
general-purpose technical verifier, or model inference client.

No imports from auth, live_qa, model streams, ASR, private files or network.
All UI callbacks must commit synchronously or use render_queued_card at the
actual deferred paint boundary. Those callbacks must be short and nonreentrant.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from threading import Lock
from typing import Callable, Literal

from .publication_policy import (
    PolicyInput, PublicationDecision, _REFERENCES, _REASONS_BY_STATE,
    evaluate_publication,
)
from .streaming_qa import ActiveTurns, TurnToken

RouteState = Literal[
    "reviewed_reference", "model_suggestion_unverified", "needs_revision",
    "unavailable", "suppressed",
]
_FAIL_REASONS = frozenset(("permission_not_confirmed", "superseded_turn"))


@dataclass(frozen=True)
class ReferenceCard:
    """Pure reviewed local content. The token must still be checked at paint."""
    token: TurnToken
    text: str
    reference_id: str
    source_ref: str
    label: Literal["reviewed_reference"] = "reviewed_reference"

    def __post_init__(self) -> None:
        if not isinstance(self.token, TurnToken):
            raise TypeError("A host-generated TurnToken is required.")
        if self.label != "reviewed_reference" or not any(
            self.text == ref.answer and self.reference_id == ref.reference_id
            and self.source_ref == ref.source_ref
            for ref in _REFERENCES
        ):
            raise ValueError("Only independently reviewed local reference copy is displayable.")


@dataclass(frozen=True)
class ReferenceRoute:
    """No arbitrary model text, input question or host secrets in this result."""
    state: RouteState
    reason_code: str
    card: ReferenceCard | None = None
    model_requests: Literal[0] = 0
    first_useful_verified_ms: None = None

    def __post_init__(self) -> None:
        if self.model_requests != 0 or self.first_useful_verified_ms is not None:
            raise ValueError("Direct references never request models or claim useful latency.")
        if (type(self.reason_code) is not str
                or self.reason_code not in (
                    _FAIL_REASONS if self.state == "suppressed"
                    else _REASONS_BY_STATE.get(self.state, ())
                )):
            raise ValueError("Route reasons must be local, state-specific codes.")
        if self.state == "reviewed_reference":
            if not isinstance(self.card, ReferenceCard) or self.reason_code != "reviewed_full_question":
                raise ValueError("Only an authorized reviewed reference can be published.")
        elif self.card is not None:
            raise ValueError("Withheld/suppressed routes cannot expose cards.")
        if self.state == "suppressed" and self.reason_code not in _FAIL_REASONS:
            raise ValueError("Suppressed route must have a fixed local reason.")


class ReferencePermission:
    """Trusted host-owned permission lease bound to the SAME ActiveTurns.

    Lock order is always permission lock -> ActiveTurns lock, for both
    publication and revoke. This linearizes a synchronous publish callback
    against permission revocation and turn cancellation without introducing
    a second turn coordinator. The actual macOS host owns TCC/session checks.
    """

    def __init__(self, turns: ActiveTurns) -> None:
        if not isinstance(turns, ActiveTurns):
            raise TypeError("ReferencePermission requires shared ActiveTurns.")
        self._turns = turns
        self._lock = Lock()
        self._allowed = False

    @property
    def turns(self) -> ActiveTurns:
        return self._turns

    def grant(self) -> None:
        """Trusted host marks the local session authorized; no implicit auth."""
        with self._lock:
            self._allowed = True

    def authorized(self) -> bool:
        with self._lock:
            return self._allowed

    def revoke(self, *, on_clear: Callable[[], None] | None = None) -> None:
        """Invalidate in-flight turns and synchronously clear host-owned UI.

        A queued render always rechecks the gate; already painted UI requires
        the host to supply on_clear (or separately clear its native reducer).
        """
        if on_clear is not None and not callable(on_clear):
            raise TypeError("on_clear callback must be callable.")
        with self._lock:
            self._allowed = False
            self._turns.cancel()
            if on_clear is not None:
                on_clear()

    def _commit_if_current(self, token: TurnToken,
                           action: Callable[[], None]) -> bool:
        with self._lock:
            if not self._allowed:
                return False
            return self._turns._publish_if_current(token, action)


@dataclass(frozen=True)
class ReferencePreview:
    """Dry-run metadata only; never contains a displayable reference string."""
    state: Literal[
        "reviewed_reference", "model_suggestion_unverified",
        "needs_revision", "unavailable",
    ]
    would_publish: bool
    reason_code: str
    model_requests: Literal[0] = 0

    def __post_init__(self) -> None:
        if (self.would_publish != (self.state == "reviewed_reference")
                or type(self.reason_code) is not str
                or self.reason_code not in _REASONS_BY_STATE.get(self.state, ())
                or self.model_requests != 0):
            raise ValueError("Dry-run metadata must use fixed policy states.")


def _prepare_authorized(request: PolicyInput, *, consent: ReferencePermission,
                        turns: ActiveTurns, token: TurnToken) -> PublicationDecision:
    if not isinstance(request, PolicyInput):
        raise TypeError("PolicyInput required.")
    if not isinstance(turns, ActiveTurns) or not isinstance(token, TurnToken):
        raise TypeError("Host must supply active turn identity.")
    if not isinstance(consent, ReferencePermission) or consent.turns is not turns:
        raise TypeError("Permission and publication must share ActiveTurns.")
    return evaluate_publication(
        replace(request, host_authorized=request.host_authorized and consent.authorized()),
        turns=turns, token=token,
    )


def preview_reference(request: PolicyInput, *, turns: ActiveTurns,
                      token: TurnToken, consent: ReferencePermission
                      ) -> ReferencePreview:
    """Dry-run only: no callbacks, text, model or network use."""
    decision = _prepare_authorized(request, turns=turns, token=token, consent=consent)
    return ReferencePreview(
        decision.state, decision.state == "reviewed_reference", decision.reason_code
    )


def publish_reference(request: PolicyInput, *, turns: ActiveTurns,
                      token: TurnToken, consent: ReferencePermission,
                      on_present: Callable[[ReferenceCard], None]) -> ReferenceRoute:
    """Commit ONLY a complete reviewed local card, never model-authored text.

    Permission is checked both before evaluation and atomically inside the
    final shared-turn commit. This callback must paint synchronously; callers
    who only enqueue work MUST call render_queued_card on the UI thread.
    """
    if not callable(on_present):
        raise TypeError("A synchronous host presentation callback is required.")
    decision = _prepare_authorized(request, turns=turns, token=token, consent=consent)
    if (type(decision) is not PublicationDecision
            or type(decision.reason_code) is not str
            or decision.reason_code not in _REASONS_BY_STATE.get(decision.state, ())):
        return ReferenceRoute("needs_revision", "question_context_unresolved")
    if decision.state != "reviewed_reference":
        return ReferenceRoute(decision.state, decision.reason_code)

    # Defense in depth: a forged/malformed decision object cannot insert an
    # untrusted card or pointer, even if the policy is monkeypatched.
    if (
        type(decision) is not PublicationDecision
        or decision.reason_code != "reviewed_full_question"
        or not any(
            decision.displayed_text == ref.answer
            and decision.reviewed_reference_id == ref.reference_id
            and decision.reviewed_source_ref == ref.source_ref
            for ref in _REFERENCES
        )
    ):
        return ReferenceRoute("needs_revision", "question_context_unresolved")
    card = ReferenceCard(
        token=token, text=decision.displayed_text,
        reference_id=decision.reviewed_reference_id,
        source_ref=decision.reviewed_source_ref,
    )

    if not consent._commit_if_current(token, lambda: on_present(card)):
        reason = "permission_not_confirmed" if not consent.authorized() else "superseded_turn"
        return ReferenceRoute("suppressed", reason)
    return ReferenceRoute("reviewed_reference", "reviewed_full_question", card)


def render_queued_card(card: ReferenceCard, *, turns: ActiveTurns,
                       consent: ReferencePermission,
                       on_paint: Callable[[ReferenceCard], None]) -> bool:
    """Recheck CURRENT authorization and turn at the actual deferred UI paint.

    A token from a previous turn/permission revocation is never painted.
    Neither this function nor the original publisher queues UI work itself.
    """
    if not isinstance(card, ReferenceCard):
        raise TypeError("Only reviewed local reference cards may be painted.")
    if not isinstance(consent, ReferencePermission) or consent.turns is not turns:
        raise TypeError("Queued rendering needs the exact shared host session.")
    if not callable(on_paint):
        raise TypeError("A synchronous on_paint callback is required.")
    return consent._commit_if_current(card.token, lambda: on_paint(card))
