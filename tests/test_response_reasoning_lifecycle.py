"""Strict new-lifecycle controls; the original compatibility fixtures stay frozen."""
from copy import deepcopy
import json
import unittest

from relay_spike.response_assembly import ResponseAssembler, ResponseProtocolError
from tests.test_response_reasoning_compatibility import ANSWER, REASONING, assemble, stream


def at(events, typ):
    return next(i for i, event in enumerate(events) if event['type'] == typ)


def numbered(events):
    for i, event in enumerate(events):
        event['sequence_number'] = i
    return events


def reasoning_text(text, *, initial=''):
    events = stream(reasoning_text=True)
    events[2]['part']['text'] = initial
    events[3]['delta'] = text[len(initial):]
    events[4]['text'] = text
    events[5]['part']['text'] = text
    events[6]['item']['content'][0]['text'] = text
    events[-1]['response']['output'][0]['content'][0]['text'] = text
    return events


class ReasoningLifecycleTests(unittest.TestCase):
    def rejected_at(self, events, index):
        assembler = ResponseAssembler()
        # Valid prefix MUST succeed, so unsupported reasoning cannot mask the
        # specific malformed event this negative control is intended to detect.
        for event in events[:index]:
            self.assertIsNone(assembler.feed(event))
        with self.assertRaises(ResponseProtocolError):
            assembler.feed(events[index])

    def test_null_optional_reasoning_status(self):
        events = stream()
        events[2]['item']['status'] = None
        events[-1]['response']['output'][0]['status'] = None
        self.assertEqual(assemble(events), ANSWER)

    def test_null_optional_reasoning_content_means_empty(self):
        events = stream()
        events[2]['item']['content'] = None
        events[-1]['response']['output'][0]['content'] = None
        self.assertEqual(assemble(events), ANSWER)

    def test_reasoning_part_initial_text_is_preserved_but_never_returned(self):
        self.assertEqual(assemble(reasoning_text(REASONING, initial=REASONING[:10])), ANSWER)

    def test_reasoning_utf8_exact_byte_budget(self):
        self.assertEqual(assemble(reasoning_text('\u00e9' * 4096)), ANSWER)

    def test_reasoning_requires_reasoning_item_kind(self):
        events = stream(reasoning_text=True)
        events[1]['item'].update(type='message', role='assistant')
        self.rejected_at(events, 2)

    def test_wrong_item_id_and_output_index(self):
        for field, value in (('item_id', 'rs_other'), ('output_index', 1), ('output_index', False)):
            with self.subTest(field=field, value=value):
                events = stream(reasoning_text=True); events[3][field] = value
                self.rejected_at(events, 3)

    def test_wrong_content_index(self):
        for value in (1, False, -1, 16):
            with self.subTest(index=value):
                events = stream(reasoning_text=True); events[3]['content_index'] = value
                self.rejected_at(events, 3)

    def test_wrong_part_type_at_add_and_completion(self):
        for index in (2, 5):
            for kind in ('output_text', 'refusal', 'synthetic_unknown'):
                with self.subTest(index=index, kind=kind):
                    events = stream(reasoning_text=True); events[index]['part']['type'] = kind
                    self.rejected_at(events, index)

    def test_output_text_delta_cannot_write_reasoning_part(self):
        events = stream(reasoning_text=True); events[3]['type'] = 'response.output_text.delta'
        self.rejected_at(events, 3)

    def test_reasoning_delta_cannot_write_message_part(self):
        events = stream()
        index = at(events, 'response.output_text.delta')
        events[index]['type'] = 'response.reasoning_text.delta'
        self.rejected_at(events, index)

    def test_delta_after_text_done_and_part_done(self):
        for index in (5, 6):
            with self.subTest(index=index):
                events = stream(reasoning_text=True)
                events.insert(index, deepcopy(events[3])); numbered(events)
                self.rejected_at(events, index)

    def test_part_done_before_text_done(self):
        events = stream(reasoning_text=True); del events[4]; numbered(events)
        self.rejected_at(events, 4)

    def test_item_done_before_part_done(self):
        events = stream(reasoning_text=True); del events[5]; numbered(events)
        self.rejected_at(events, 5)

    def test_duplicate_text_done_and_part_done(self):
        for index in (4, 5):
            with self.subTest(index=index):
                events = stream(reasoning_text=True)
                events.insert(index + 1, deepcopy(events[index])); numbered(events)
                self.rejected_at(events, index + 1)

    def test_mismatched_text_and_final_item_content(self):
        for index in (4, 5, 6):
            with self.subTest(index=index):
                events = stream(reasoning_text=True)
                if index == 4: events[index]['text'] = 'different'
                elif index == 5: events[index]['part']['text'] = 'different'
                else: events[index]['item']['content'][0]['text'] = 'different'
                self.rejected_at(events, index)

    def test_unobserved_extra_final_reasoning_part(self):
        events = stream(reasoning_text=True)
        events[6]['item']['content'].append(dict(type='reasoning_text', text='unobserved'))
        self.rejected_at(events, 6)

    def test_null_final_content_cannot_discard_observed_reasoning(self):
        events = stream(reasoning_text=True); events[6]['item']['content'] = None
        self.rejected_at(events, 6)

    def test_explicit_unfinished_or_unknown_reasoning_status(self):
        for value in ('in_progress', 'incomplete', 'unknown', False):
            with self.subTest(status=value):
                events = stream(reasoning_text=True); events[6]['item']['status'] = value
                self.rejected_at(events, 6)

    def test_message_completion_and_content_are_not_optional(self):
        for field, value in (('status', None), ('status', 'in_progress'), ('content', None)):
            with self.subTest(field=field, value=value):
                events = stream(reasoning_text=True); events[-2]['item'][field] = value
                self.rejected_at(events, len(events) - 2)

    def test_reasoning_part_byte_limit_and_global_limit(self):
        events = reasoning_text('\u00e9' * 4097)
        self.rejected_at(events, 3)
        events = stream(reasoning_text=True); events[3]['padding'] = 'x' * 524288
        self.rejected_at(events, 3)

    def test_refusal_event_still_rejects(self):
        events = stream(reasoning_text=True); events[3]['type'] = 'response.refusal.delta'
        self.rejected_at(events, 3)

    def test_completed_response_must_match_exact_reasoning_item(self):
        events = stream(reasoning_text=True)
        events[-1]['response']['output'][0]['content'][0]['text'] = 'different'
        self.rejected_at(events, len(events) - 1)

    def test_nonobject_parts_and_nontext_deltas_reject_at_their_event(self):
        for index in (2, 5):
            for value in (None, [], 'wrong'):
                with self.subTest(index=index, value=value):
                    events = stream(reasoning_text=True); events[index]['part'] = value
                    self.rejected_at(events, index)
        for value in (None, False, 3, []):
            with self.subTest(delta=value):
                events = stream(reasoning_text=True); events[3]['delta'] = value
                self.rejected_at(events, 3)


class ReasoningTransportTests(unittest.IsolatedAsyncioTestCase):
    async def test_actual_adapter_assembles_reasoning_stream_without_returning_reasoning(self):
        import httpx
        from relay_spike.oauth_answer_stream import OAuthAnswerStream
        requests = []
        rows = stream(reasoning_text=True)
        wire = b''.join(b'data: ' + json.dumps(event).encode() + b'\n\n' for event in rows)
        def handler(request):
            requests.append(request)
            return httpx.Response(200, headers={'content-type': 'text/event-stream'}, stream=httpx.ByteStream(wire))
        transport = OAuthAnswerStream(token_provider=lambda: 'synthetic-only',
            client_factory=lambda **kw: httpx.AsyncClient(transport=httpx.MockTransport(handler), **kw))
        try:
            answer = await transport.complete('Synthetic question.', 'Synthetic instructions.')
            self.assertEqual(answer, ANSWER)
            self.assertNotIn(REASONING, answer)
            self.assertEqual(len(requests), 1)
            self.assertEqual(transport.last_timing.provider_terminal, 'completed')
        finally:
            await transport.aclose()
