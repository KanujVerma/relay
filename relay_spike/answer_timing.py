"""Content-free transport timings; never an answer/publication authority."""
from dataclasses import dataclass


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
    # A valid delta, complete JSON or format check cannot establish usefulness.
    first_useful_verified_ms: None = None


class AnswerTimingAttempt:
    def __init__(self, request_index, clock):
        self.request_index, self.clock = request_index, clock
        self.start = clock()
        self.marks = {}
        self.output_bytes = 0

    def mark(self, name):
        if name not in self.marks:
            self.marks[name] = (self.clock() - self.start) * 1000

    def finish(self, outcome):
        return AnswerTransportTiming(self.request_index, outcome,
            *(self.marks.get(name) for name in ('token_ready_ms', 'client_ready_ms',
                'request_started_ms', 'response_headers_ms', 'first_text_ms', 'response_completed_ms')),
            (self.clock() - self.start) * 1000, self.output_bytes)
