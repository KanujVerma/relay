import json
import unittest

from relay_spike.conversation_context import ConversationContext
from relay_spike.generated_answer import CardError, parse_generated_card, make_prompt
from relay_spike.response_assembly import ResponseAssembler, ResponseProtocolError


def candidate(**changes):
    value = dict(lead='Ask about duplicates before choosing the data structure.', points=['Explain the invariant.'], detail=None, assumptions=['Input contract is not yet confirmed.'], coverage=['approach'], personal_fact_ids=[])
    value.update(changes)
    return json.dumps(value)


class ContextTests(unittest.TestCase):
    def test_coding_and_case_context_keeps_both_speakers_without_inventing_requirements(self):
        context = ConversationContext()
        context.observe('remote', 'Let us implement a cache. What questions would you ask first?')
        context.observe('microphone', 'I would ask about eviction and capacity.')
        context.observe('remote', 'Capacity is 3. Now discuss LRU improvements.')
        bundle = context.snapshot()
        self.assertEqual(bundle.task.kind, 'coding')
        self.assertIn('Capacity is 3', bundle.task.engineer_feedback[-1])
        self.assertIn('eviction', bundle.task.user_attempt[-1])
        prompt = make_prompt('How would you improve it?', bundle, None)
        self.assertIn('microphone', prompt)
        self.assertIn('LRU', prompt)
        self.assertIn('unresolved_assumptions', prompt)

    def test_bounded_history_and_case_study_stage(self):
        context = ConversationContext(max_utterances=4, max_bytes=1024)
        context.observe('remote', 'Case study: design a feature for nurses. Who are its users?')
        context.observe('microphone', 'Nurses need rapid handoffs.')
        context.observe('remote', 'How would you validate the workflow?')
        self.assertEqual(context.snapshot().task.kind, 'case_study')
        self.assertEqual(context.snapshot().task.stage, 'validation')
        for _ in range(20):
            context.observe('microphone', 'This is a bounded answer.')
        self.assertLessEqual(len(context.snapshot().dialogue), 4)
        self.assertLessEqual(len(json.dumps(context.snapshot().as_dict()).encode()), 8192)


class CardTests(unittest.TestCase):
    def test_strict_card_and_preserved_code(self):
        raw = candidate(detail={'kind':'code','language':'python','text':'def add(a, b):\n    return a + b\n'})
        card = parse_generated_card(raw, code_required=True)
        self.assertIn('\n    return', card.detail.text)
        self.assertEqual(card.checks, ('format_checked', 'python_syntax_checked'))

    def test_malformed_fabricated_authority_and_prose_only_code_reject(self):
        for raw in (candidate(personal_fact_ids=['invented']), candidate(lead='I built the pipeline at Acme.'), candidate(reviewed=True), '{"lead":"a","lead":"b"}'):
            with self.subTest(raw=raw), self.assertRaises(CardError):
                parse_generated_card(raw)
        with self.assertRaises(CardError):
            parse_generated_card(candidate(), code_required=True)
        with self.assertRaises(CardError):
            parse_generated_card(candidate(detail={'kind':'code','language':'python','text':'def bad('}))

    def test_personal_ids_never_grant_authority(self):
        with self.assertRaises(CardError):
            parse_generated_card(candidate(lead='I led a team of five.', personal_fact_ids=['known']), approved_fact_ids=('known',))


class AssemblyTests(unittest.TestCase):
    def test_completed_indexed_text_and_terminal_identity(self):
        a = ResponseAssembler()
        a.feed({'type':'response.created','sequence_number':0,'response':{'id':'r','status':'in_progress'}})
        a.feed({'type':'response.output_item.added','sequence_number':1,'output_index':0,'item':{'id':'m','type':'message','status':'in_progress','content':[]}})
        a.feed({'type':'response.content_part.added','sequence_number':2,'output_index':0,'item_id':'m','content_index':0,'part':{'type':'output_text','text':''}})
        a.feed({'type':'response.output_text.delta','sequence_number':3,'output_index':0,'item_id':'m','content_index':0,'delta':'hello'})
        item={'id':'m','type':'message','status':'completed','content':[{'type':'output_text','text':'hello'}]}
        a.feed({'type':'response.output_item.done','sequence_number':4,'output_index':0,'item':item})
        self.assertEqual(a.feed({'type':'response.completed','sequence_number':5,'response':{'id':'r','status':'completed','output':[item]}}), 'hello')
        with self.assertRaises(ResponseProtocolError):
            a.feed({'type':'response.completed','sequence_number':6,'response':{'id':'r','status':'completed','output':[item]}})

    def test_missing_terminal_refusal_unfinished_changed_identity_reject(self):
        for event in ({'type':'response.failed','sequence_number':1}, {'type':'response.refusal.delta','sequence_number':1,'delta':'private'}, {'type':'response.completed','sequence_number':1,'response':{'id':'different','status':'completed','output':[]}}):
            a=ResponseAssembler()
            a.feed({'type':'response.created','sequence_number':0,'response':{'id':'r','status':'in_progress'}})
            with self.subTest(event=event), self.assertRaises(ResponseProtocolError): a.feed(event)

class SupplementalContextTests(unittest.TestCase):
    def test_bounded_fresh_screen_or_pasted_text_cannot_grant_personal_authority(self):
        from relay_spike.conversation_context import ContextSnippet
        snippet=ContextSnippet(kind='screen_text',text='Implement LRUCache(capacity).',source='selected IDE',captured_uptime_ns=100,session_id='session',presentation_generation=2,provenance='local_ocr')
        self.assertTrue(snippet.current(session_id='session',presentation_generation=2,now_ns=101))
        self.assertFalse(snippet.current(session_id='session',presentation_generation=3,now_ns=101))
        self.assertFalse(snippet.current(session_id='session',presentation_generation=2,now_ns=20_000_000_101))
        with self.assertRaises(ValueError):
            ContextSnippet(kind='screen_text',text='x'*8193,source='IDE',captured_uptime_ns=1,session_id='session',presentation_generation=1,provenance='local_ocr')

class SDKLifecycleRegressions(unittest.TestCase):
    def test_null_completed_output_recovers_only_finished_indexed_items(self):
        a=ResponseAssembler();a.feed({'type':'response.created','sequence_number':0,'response':{'id':'r','status':'in_progress'}})
        a.feed({'type':'response.output_item.added','sequence_number':1,'output_index':3,'item':{'id':'m','type':'message','status':'in_progress','content':[]}})
        item={'id':'m','type':'message','status':'completed','content':[{'type':'output_text','text':'done'}]}
        a.feed({'type':'response.output_item.done','sequence_number':2,'output_index':3,'item':item})
        self.assertEqual(a.feed({'type':'response.completed','sequence_number':3,'response':{'id':'r','status':'completed','output':None}}),'done')

    def test_duplicate_created_and_duplicate_item_identity_reject(self):
        a=ResponseAssembler();created={'type':'response.created','sequence_number':0,'response':{'id':'r','status':'in_progress'}};a.feed(created)
        with self.assertRaises(ResponseProtocolError): a.feed({**created,'sequence_number':1})
        a=ResponseAssembler();a.feed(created)
        for index in (0,1):
            item={'type':'response.output_item.added','sequence_number':index+1,'output_index':index,'item':{'id':'same','type':'message','status':'in_progress','content':[]}}
            if index==0: a.feed(item)
            else:
                with self.assertRaises(ResponseProtocolError): a.feed(item)

class UnicodeControlTests(unittest.TestCase):
    def test_format_controls_and_escaped_surrogates_rejected(self):
        for lead in ('safe\u202eevil','safe\u200bevil','safe\u2028evil','\ud800'):
            with self.subTest(lead=repr(lead)),self.assertRaises(CardError):
                parse_generated_card(candidate(lead=lead))
