"""Content-free transport timings; never an answer/publication authority."""
from dataclasses import dataclass
from .answer_diagnostics import TransportObservation, TransportObservationAttempt


@dataclass(frozen=True)
class AnswerTransportTiming:
    request_index: int
    outcome: str
    token_ready_ms: float | None
    client_ready_ms: float | None
    request_started_ms: float | None
    response_headers_ms: float | None
    first_text_ms: float | None
    response_completed_ms: float | None
    finished_ms: float
    output_bytes: int
    started_uptime_nanoseconds: int
    provider_terminal: str | None
    # A valid delta, complete JSON or format check cannot establish usefulness.
    first_useful_verified_ms: None = None
    diagnostic: TransportObservation | None = None


class AnswerTimingAttempt:
    def __init__(self, request_index, clock):
        self.request_index, self.clock = request_index, clock
        self.start = clock()
        self.marks = {}
        self.output_bytes = 0
        self.provider_terminal = None
        self.diagnostic = TransportObservationAttempt()

    def mark(self, name):
        if name not in self.marks:
            self.marks[name] = (self.clock() - self.start) * 1000

    def finish(self, outcome):
        return AnswerTransportTiming(self.request_index, outcome,
            *(self.marks.get(name) for name in ('token_ready_ms', 'client_ready_ms',
                'request_started_ms', 'response_headers_ms', 'first_text_ms', 'response_completed_ms')),
            (self.clock() - self.start) * 1000, self.output_bytes, int(self.start * 1_000_000_000),
            self.provider_terminal, diagnostic=self.diagnostic.snapshot())


class HelperRequestTiming:
    """One original request's descriptive marks, never consulted by admission."""
    def __init__(self, received_ns):
        self.received_ns = received_ns
        self.marks = {}
        self.transport_outcome = None

    def mark(self, name, when_ns):
        self.marks.setdefault(name, when_ns)

    def note_transport(self, previous, current):
        if current is previous or not isinstance(current, AnswerTransportTiming):
            return
        self.transport_outcome = current.outcome
        for source, target in (('first_text_ms', 'firstTextUptimeNanoseconds'),
                               ('response_completed_ms', 'responseCompletedUptimeNanoseconds')):
            value = getattr(current, source)
            if value is not None:
                self.mark(target, current.started_uptime_nanoseconds + int(value * 1_000_000))

    def snapshot(self, emitted_ns):
        return dict(schemaVersion=1, helperReceivedUptimeNanoseconds=self.received_ns,
            **{name: self.marks.get(name) for name in ('generationStartedUptimeNanoseconds',
                'transportStartedUptimeNanoseconds', 'firstTextUptimeNanoseconds',
                'responseCompletedUptimeNanoseconds', 'validationFinishedUptimeNanoseconds')},
            helperEmittedUptimeNanoseconds=emitted_ns, transportOutcome=self.transport_outcome)
