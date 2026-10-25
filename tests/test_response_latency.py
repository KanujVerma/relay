"""Request-bound stage telemetry, synthetic data and clocks only."""
import json
import unittest

from relay_spike.session_host import SessionHost
from tests.test_session_host import start, speech, end, final


CARD = json.dumps({'lead': 'Explain FIFO ordering.', 'points': [], 'detail': None,
                   'assumptions': [], 'coverage': ['current_request'], 'personal_fact_ids': []})


class ResponseLatencyTests(unittest.IsolatedAsyncioTestCase):
    async def test_reviewed_route_records_ingress_and_emit_without_invented_model_timings(self):
        out = []
        host = SessionHost(emit=out.append)
        await host.handle(start())
        await host.handle(speech(2))
        await host.handle(end(3))
        await host.handle(final(4, 'What is the difference between WHERE and HAVING?'))
        row = out[-1]
        self.assertEqual(row['answerKind'], 'reviewed_reference')
        self.assertEqual(host.model_requests, 0)
        timing = row['timing']
        self.assertLessEqual(timing['helperReceivedUptimeNanoseconds'], timing['helperEmittedUptimeNanoseconds'])
        self.assertIsNone(timing['generationStartedUptimeNanoseconds'])
        self.assertIsNone(timing['firstTextUptimeNanoseconds'])
        self.assertIsNone(timing['responseCompletedUptimeNanoseconds'])
        self.assertIsNone(timing['transportOutcome'])

    async def test_generated_fixture_has_real_host_stages_and_no_fake_provider_timestamps(self):
        out = []
        async def complete(*_): return CARD
        host = SessionHost(complete=complete, emit=out.append)
        await host.handle(start()); await host.handle(speech(2)); await host.handle(end(3))
        await host.handle(final(4, 'Explain queues.')); await host.drain()
        pending, answer = out
        self.assertEqual((pending['disposition'], answer['disposition']), ('pending', 'answer'))
        timing = answer['timing']
        self.assertLessEqual(timing['helperReceivedUptimeNanoseconds'], timing['generationStartedUptimeNanoseconds'])
        self.assertLessEqual(timing['generationStartedUptimeNanoseconds'], timing['transportStartedUptimeNanoseconds'])
        self.assertLessEqual(timing['transportStartedUptimeNanoseconds'], timing['validationFinishedUptimeNanoseconds'])
        self.assertLessEqual(timing['validationFinishedUptimeNanoseconds'], timing['helperEmittedUptimeNanoseconds'])
        self.assertIsNone(timing['firstTextUptimeNanoseconds'])
        self.assertIsNone(timing['responseCompletedUptimeNanoseconds'])

    async def test_disabled_inference_terminal_is_measured_without_generation(self):
        out = []
        host = SessionHost(emit=out.append)
        await host.handle(start()); await host.handle(speech(2)); await host.handle(end(3))
        await host.handle(final(4, 'Explain queues.'))
        self.assertEqual(out[-1]['reasonCode'], 'inference_disabled')
        self.assertIn('timing', out[-1])
        self.assertIsNone(out[-1]['timing']['transportStartedUptimeNanoseconds'])

    async def test_real_transport_stage_times_attach_only_to_that_attempt(self):
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX transport dependency')
        from relay_spike.oauth_answer_stream import OAuthAnswerStream
        from tests.test_answer_transport_lifetime import events, wire
        async def handler(_):
            return httpx.Response(200, headers={'content-type': 'text/event-stream'},
                                  stream=httpx.ByteStream(wire(events(CARD))))
        stream = OAuthAnswerStream(token_provider=lambda: 'synthetic', client_factory=lambda **kw:
            httpx.AsyncClient(transport=httpx.MockTransport(handler), **kw))
        self.addAsyncCleanup(stream.aclose)
        out = []
        host = SessionHost(complete=stream.complete, emit=out.append)
        await host.handle(start()); await host.handle(speech(2)); await host.handle(end(3))
        await host.handle(final(4, 'Explain queues.')); await host.drain()
        timing = out[-1]['timing']
        self.assertEqual(timing['transportOutcome'], 'completed')
        self.assertLessEqual(timing['transportStartedUptimeNanoseconds'], timing['firstTextUptimeNanoseconds'])
        self.assertLessEqual(timing['firstTextUptimeNanoseconds'], timing['responseCompletedUptimeNanoseconds'])
        self.assertLessEqual(timing['responseCompletedUptimeNanoseconds'], timing['validationFinishedUptimeNanoseconds'])
        # A later denied request must not borrow the successful earlier times.
        stream._spent = 60
        await host.handle(speech(5, activity=2, generation=3)); await host.handle(end(6, activity=2, generation=3))
        await host.handle(final(7, 'Explain stacks.', activity=2, generation=3)); await host.drain()
        self.assertEqual(out[-1]['disposition'], 'abstain')
        self.assertIsNone(out[-1]['timing']['responseCompletedUptimeNanoseconds'])
        self.assertIsNone(out[-1]['timing']['transportOutcome'])

    async def test_format_failure_keeps_completion_observation_but_never_succeeds(self):
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX transport dependency')
        from relay_spike.oauth_answer_stream import OAuthAnswerStream
        from tests.test_answer_transport_lifetime import events, wire
        async def handler(_):
            return httpx.Response(200, headers={'content-type': 'text/event-stream'},
                                  stream=httpx.ByteStream(wire(events('invalid card'))))
        stream = OAuthAnswerStream(token_provider=lambda: 'synthetic', client_factory=lambda **kw:
            httpx.AsyncClient(transport=httpx.MockTransport(handler), **kw))
        self.addAsyncCleanup(stream.aclose)
        out = []
        host = SessionHost(complete=stream.complete, emit=out.append)
        await host.handle(start()); await host.handle(speech(2)); await host.handle(end(3))
        await host.handle(final(4, 'Explain queues.')); await host.drain()
        self.assertEqual(out[-1]['disposition'], 'abstain')
        self.assertIsNotNone(out[-1]['timing']['responseCompletedUptimeNanoseconds'])
        self.assertIsNone(out[-1]['timing']['validationFinishedUptimeNanoseconds'])


if __name__ == '__main__': unittest.main()
