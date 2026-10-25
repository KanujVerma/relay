"""Original fictional streams from documented Responses event/type schemas.

Reference only: openai-python v3.37.0, Apache-2.0,
e8a0fd28bbdc1699c97ff0f602b1af3dd378382d. No SDK code is copied or installed.
These tests establish compatibility, not which events any live request emitted.
"""
from copy import deepcopy
import unittest

from relay_spike.response_assembly import ResponseAssembler, ResponseProtocolError


ANSWER = 'A synthetic final answer.'
REASONING = 'Synthetic reasoning sentinel, excluded from the final answer.'


def response(status, output):
    return dict(id='resp_synthetic', created_at=0.0, model='synthetic-model',
                object='response', output=deepcopy(output), parallel_tool_calls=False,
                tool_choice='auto', tools=[], status=status)


def stream(*, reasoning_text=False, reasoning_status=True):
    events = []
    def event(typ, **fields):
        events.append(dict(type=typ, sequence_number=len(events), **deepcopy(fields)))
    event('response.created', response=response('in_progress', []))
    initial = dict(id='rs_synthetic', type='reasoning', summary=[], status='in_progress')
    if reasoning_text:
        initial['content'] = []
    event('response.output_item.added', output_index=0, item=initial)
    done = dict(id='rs_synthetic', type='reasoning', summary=[])
    if reasoning_status:
        done['status'] = 'completed'
    if reasoning_text:
        identity = dict(item_id='rs_synthetic', output_index=0, content_index=0)
        event('response.content_part.added', **identity, part=dict(type='reasoning_text', text=''))
        event('response.reasoning_text.delta', **identity, delta=REASONING)
        event('response.reasoning_text.done', **identity, text=REASONING)
        event('response.content_part.done', **identity, part=dict(type='reasoning_text', text=REASONING))
        done['content'] = [dict(type='reasoning_text', text=REASONING)]
    event('response.output_item.done', output_index=0, item=done)
    event('response.output_item.added', output_index=1,
          item=dict(id='msg_synthetic', type='message', role='assistant', status='in_progress', content=[]))
    identity = dict(item_id='msg_synthetic', output_index=1, content_index=0)
    event('response.content_part.added', **identity,
          part=dict(type='output_text', text='', annotations=[], logprobs=[]))
    event('response.output_text.delta', **identity, delta=ANSWER, logprobs=[])
    event('response.output_text.done', **identity, text=ANSWER, logprobs=[])
    text = dict(type='output_text', text=ANSWER, annotations=[], logprobs=[])
    event('response.content_part.done', **identity, part=text)
    message = dict(id='msg_synthetic', type='message', role='assistant', status='completed', content=[text])
    event('response.output_item.done', output_index=1, item=message)
    event('response.completed', response=response('completed', [done, message]))
    return events


def assemble(events):
    assembler = ResponseAssembler()
    answer = None
    for event in events:
        try:
            current = assembler.feed(event)
        except ResponseProtocolError as error:
            raise ResponseProtocolError(f"Rejected synthetic event {event['sequence_number']} {event['type']}") from error
        if current is not None:
            answer = current
    assembler.finish()
    return answer


class ReasoningCompatibilityTests(unittest.TestCase):
    def test_completed_reasoning_with_explicit_status_control(self):
        self.assertEqual(assemble(stream()), ANSWER)

    def test_schema_optional_reasoning_item_status_does_not_reject_completed_response(self):
        self.assertEqual(assemble(stream(reasoning_status=False)), ANSWER)

    def test_reasoning_text_parts_and_deltas_are_separate_from_final_message(self):
        answer = assemble(stream(reasoning_text=True))
        self.assertEqual(answer, ANSWER)
        self.assertNotIn(REASONING, answer)

    def test_changed_reasoning_item_identity_rejects(self):
        events = stream()
        events[2]['item']['id'] = 'rs_different'
        with self.assertRaises(ResponseProtocolError):
            assemble(events)

    def test_changed_response_identity_rejects(self):
        events = stream()
        events[-1]['response']['id'] = 'resp_different'
        with self.assertRaises(ResponseProtocolError):
            assemble(events)

    def test_reasoning_item_done_before_add_rejects(self):
        events = stream()
        del events[1]
        with self.assertRaises(ResponseProtocolError):
            assemble(events)

    def test_duplicate_sequence_rejects(self):
        events = stream()
        events[2]['sequence_number'] = events[1]['sequence_number']
        with self.assertRaises(ResponseProtocolError):
            assemble(events)

    def test_incomplete_reasoning_item_rejects(self):
        events = stream()
        events[2]['item']['status'] = 'incomplete'
        with self.assertRaises(ResponseProtocolError):
            assemble(events)

    def test_incomplete_response_rejects(self):
        events = stream()
        events[-1]['type'] = 'response.incomplete'
        events[-1]['response']['status'] = 'incomplete'
        with self.assertRaises(ResponseProtocolError):
            assemble(events)

    def test_missing_completed_response_rejects(self):
        with self.assertRaises(ResponseProtocolError):
            assemble(stream()[:-1])

    def test_missing_message_done_rejects(self):
        events = stream()
        del events[-2]
        with self.assertRaises(ResponseProtocolError):
            assemble(events)

    def test_unknown_event_is_not_authorized_by_reasoning_compatibility(self):
        events = stream()
        events[2]['type'] = 'response.synthetic_unknown_event'
        with self.assertRaises(ResponseProtocolError):
            assemble(events)
