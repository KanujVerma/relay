"""Standalone 03B-B1A Swift EOU wire/timing validator, no application routing.

Pure standard-library parser for a PROPOSED local host-to-Python envelope.
Swift FinalTranscriptEvent and PCMSource provide the source fields, but do
not yet emit this JSON or its required trusted native-host time calibration.
This module is not proof of authorization or of ASR/speaker correctness.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import math
from typing import Literal

MAX_WIRE_BYTES = 8192
MAX_TEXT_CHARS = 1200
UINT64_MAX = (1 << 64) - 1
MAX_UTTERANCE_NS = 120 * 1_000_000_000
MAX_FINAL_LAG_NS = 30 * 1_000_000_000
MAX_CALIBRATION_AGE_NS = 10 * 60 * 1_000_000_000

_TOP_KEYS = frozenset((
    "version", "status", "sourceCode", "streamGeneration", "segmentID",
    "revision", "startHostTime", "endHostTime",
    "finalizedUptimeNanoseconds", "receivedUptimeNanoseconds",
    "text", "confidence", "timebase",
))
_TIMEBASE_KEYS = frozenset((
    "hostTicksAtAnchor", "uptimeNsAtAnchor", "nsNumer", "nsDenom",
))
Status = Literal["final", "blank_final", "unavailable", "discontinuity"]
SourceChannel = Literal["microphone", "remote"]


class NativeEOUWireError(ValueError):
    """Sanitized, bounded contract error. Never echo untrusted text or IDs."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class NormalizedNativeEOU:
    """Schema-valid input, NOT trusted OS consent, voice ID or model answer."""

    status: Status
    source_channel: SourceChannel
    stream_generation: int
    segment_id: str
    revision: int
    text: str | None
    confidence: float | None
    start_ms: int | None
    end_ms: int | None
    finalized_ms: int
    received_ms: int

    @property
    def is_text_final(self) -> bool:
        """Not an authorization/intent verdict; only nonblank terminal text."""
        return self.status == "final"

    @property
    def can_auto_route(self) -> bool:
        """Always false until the separate host/consent/intent gates run."""
        return False


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    out: dict[str, object] = {}
    for key, value in pairs:
        if key in out:
            raise NativeEOUWireError("duplicate_field")
        out[key] = value
    return out


def _reject_json_constant(_: str) -> object:
    raise NativeEOUWireError("nonfinite_number")


def _u64(value: object) -> int:
    if type(value) is not int or not 0 <= value <= UINT64_MAX:
        raise NativeEOUWireError("invalid_unsigned_integer")
    return value


def _exact_keys(value: object, expected: frozenset[str]) -> dict:
    if type(value) is not dict or frozenset(value) != expected:
        raise NativeEOUWireError("invalid_field_set")
    return value


def _calibrate_ticks(host_ticks: int, *, anchor_ticks: int,
                     anchor_uptime_ns: int, ns_numer: int, ns_denom: int) -> int:
    # Native host MUST obtain the clock ratio and a near-simultaneous anchor
    # using public platform timebase APIs. Raw host ticks are NOT nanoseconds.
    offset = host_ticks - anchor_ticks
    result = anchor_uptime_ns + (offset * ns_numer // ns_denom)
    if result < 0 or result > UINT64_MAX:
        raise NativeEOUWireError("calibrated_clock_out_of_range")
    return result


def decode_native_eou_wire(payload: bytes) -> NormalizedNativeEOU:
    """Parse the proposed local, one-clock EOU envelope.

    Safe only for explicitly host-calibrated synthetic wire bytes here.
    Does not read files, contact a model, attest macOS consent, or call the
    question state machine. Future native writer must be audited separately.
    """
    if type(payload) is not bytes or not 0 < len(payload) <= MAX_WIRE_BYTES:
        raise NativeEOUWireError("invalid_wire_size")
    try:
        decoded = json.loads(payload.decode("utf-8"),
                             object_pairs_hook=_unique_object,
                             parse_constant=_reject_json_constant)
    except NativeEOUWireError:
        raise
    except (UnicodeError, ValueError, TypeError, RecursionError):
        raise NativeEOUWireError("invalid_json") from None

    raw = _exact_keys(decoded, _TOP_KEYS)
    if type(raw["version"]) is not int or raw["version"] != 1:
        raise NativeEOUWireError("unsupported_schema_version")

    status = raw["status"]
    if type(status) is not str or status not in ("final", "unavailable", "discontinuity"):
        raise NativeEOUWireError("invalid_status")
    code = raw["sourceCode"]
    if type(code) is not int or code not in (1, 2):
        raise NativeEOUWireError("invalid_source_code")

    generation = _u64(raw["streamGeneration"])
    segment = _u64(raw["segmentID"])
    revision = _u64(raw["revision"])
    start_ticks, end_ticks = raw["startHostTime"], raw["endHostTime"]
    if start_ticks is not None:
        start_ticks = _u64(start_ticks)
    if end_ticks is not None:
        end_ticks = _u64(end_ticks)
    if (start_ticks is None) != (end_ticks is None):
        raise NativeEOUWireError("incomplete_host_span")
    if start_ticks is not None and start_ticks > end_ticks:
        raise NativeEOUWireError("reverse_host_span")

    finalized_ns = _u64(raw["finalizedUptimeNanoseconds"])
    received_ns = _u64(raw["receivedUptimeNanoseconds"])
    if received_ns < finalized_ns:
        raise NativeEOUWireError("receive_before_finalized")

    text = raw["text"]
    if status != "final":
        if text is not None:
            raise NativeEOUWireError("text_on_control_event")
    elif text is None:
        # A successful EOU with no recognized words is still a terminal.
        text = ""
    if text is not None:
        if (type(text) is not str or len(text) > MAX_TEXT_CHARS or
                "\x00" in text or any(0xD800 <= ord(c) <= 0xDFFF for c in text)):
            raise NativeEOUWireError("invalid_text")
    score = raw["confidence"]
    if score is not None:
        if (type(score) not in (int, float) or not math.isfinite(score)
                or not 0 <= score <= 1):
            raise NativeEOUWireError("invalid_confidence")
        score = float(score)
    if status != "final" and score is not None:
        raise NativeEOUWireError("score_on_control_event")

    start_ms: int | None = None
    end_ms: int | None = None
    clock = raw["timebase"]
    if status == "final":
        # A final is not eligible for even tentative question classification
        # without both raw sample boundaries AND host-supplied calibration.
        if start_ticks is None:
            raise NativeEOUWireError("missing_final_host_span")
        timebase = _exact_keys(clock, _TIMEBASE_KEYS)
        anchor_ticks = _u64(timebase["hostTicksAtAnchor"])
        anchor_ns = _u64(timebase["uptimeNsAtAnchor"])
        numer = timebase["nsNumer"]
        denom = timebase["nsDenom"]
        if (type(numer) is not int or type(denom) is not int
                or not 0 < numer <= 1_000_000_000
                or not 0 < denom <= 1_000_000_000):
            raise NativeEOUWireError("invalid_host_clock_ratio")
        if abs(finalized_ns - anchor_ns) > MAX_CALIBRATION_AGE_NS:
            raise NativeEOUWireError("stale_host_clock_anchor")
        start_ns = _calibrate_ticks(
            start_ticks, anchor_ticks=anchor_ticks,
            anchor_uptime_ns=anchor_ns, ns_numer=numer, ns_denom=denom,
        )
        end_ns = _calibrate_ticks(
            end_ticks, anchor_ticks=anchor_ticks,
            anchor_uptime_ns=anchor_ns, ns_numer=numer, ns_denom=denom,
        )
        if not start_ns <= end_ns <= finalized_ns:
            raise NativeEOUWireError("invalid_calibrated_time_order")
        if end_ns - start_ns > MAX_UTTERANCE_NS:
            raise NativeEOUWireError("utterance_duration_limit")
        if finalized_ns - end_ns > MAX_FINAL_LAG_NS:
            raise NativeEOUWireError("finalization_lag_limit")
        start_ms, end_ms = start_ns // 1_000_000, end_ns // 1_000_000
    elif clock is not None:
        # No invented dates/host span for unavailable/discontinuity.
        # They must remain nontext terminal controls, not future questions.
        _exact_keys(clock, _TIMEBASE_KEYS)
        raise NativeEOUWireError("control_event_timebase_not_supported")

    return NormalizedNativeEOU(
        status=("blank_final" if status == "final" and not text.strip()
                else status),
        source_channel=("microphone" if code == 1 else "remote"),
        stream_generation=generation, segment_id="native:" + str(segment),
        revision=revision, text=text, confidence=score,
        start_ms=start_ms, end_ms=end_ms,
        finalized_ms=finalized_ns // 1_000_000,
        received_ms=received_ns // 1_000_000,
    )
