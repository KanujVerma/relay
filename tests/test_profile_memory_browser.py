import base64
from hashlib import sha256
import json
import unittest

from relay_spike.personal_brain import BrainError
from relay_spike.profile_bridge import ProfileBridge


class ProfileMemoryBrowserTests(unittest.TestCase):
    def setUp(self):
        self.changes = []
        self.bridge = ProfileBridge(on_change=lambda: self.changes.append(True))
        self.bridge.handle({'command': 'new'})

    def tearDown(self):
        self.bridge.close()

    def add(self, index, actor='self', text=None, claim_key=None, replaces=None):
        text = text or f'{"We" if actor == "team" else "I"} implemented Atlas SQL tests for case {index}.'
        data = text.encode()
        self.bridge.handle({'command': 'select_begin', 'size': len(data), 'sha256': sha256(data).hexdigest(),
                            'file_type': 'txt', 'purpose': 'project', 'label': f'Atlas {index}',
                            'role': 'developer', 'project_hint': 'Atlas'})
        for offset in range(0, len(data), 4096):
            self.bridge.handle({'command': 'transfer_chunk', 'offset': offset,
                                'data': base64.b64encode(data[offset:offset + 4096]).decode()})
        card = self.bridge.handle({'command': 'select_commit'})['card']
        self.assertIsNotNone(card)
        decision = {'command': 'decide', 'fact_id': card['fact_id'],
                    'fingerprint': card['card_fingerprint'], 'decision': 'approve',
                    'actor': actor, 'claim_key': claim_key or f'atlas.case.{index}'}
        if replaces is not None:
            decision['replaces_fact_id'] = replaces
        self.bridge.handle(decision)
        return card

    def page(self, after=None, limit=8):
        return self.bridge.handle({'command': 'memories', 'after': after, 'limit': limit})

    def test_only_approved_current_memories_are_returned_without_mutating_authority(self):
        card = self.add(1)
        bundle = self.bridge.retrieve('Atlas SQL tests?', 'developer')
        change_count = len(self.changes)
        page = self.page()
        self.assertEqual(len(page['memories']), 1)
        memory = page['memories'][0]
        self.assertEqual(memory['fact_id'], card['fact_id'])
        self.assertEqual(memory['claim_text'], card['snippet'])
        self.assertEqual(memory['actor'], 'self')
        self.assertEqual(memory['source_label'], 'Atlas 1')
        self.assertEqual(page['total_count'], 1)
        self.assertIsNone(page['next_after'])
        self.assertEqual(len(self.changes), change_count)
        self.assertTrue(self.bridge.validate_current(bundle))
        self.bridge.handle({'command': 'revoke', 'source_id': card['source_id']})
        self.assertEqual(self.page()['memories'], [])
        self.assertEqual(self.page()['total_count'], 0)
        self.bridge.handle({'command': 'lock'})
        with self.assertRaises(BrainError):
            self.page()

    def test_pages_are_bounded_complete_and_keep_team_ownership(self):
        cards = [self.add(i, actor='team' if i % 2 else 'self') for i in range(11)]
        collected, after = [], None
        for _ in range(5):
            page = self.page(after, 3)
            self.assertLessEqual(len(page['memories']), 3)
            self.assertEqual(page['total_count'], 11)
            collected += page['memories']
            after = page['next_after']
            if after is None:
                break
        self.assertIsNone(after)
        self.assertEqual([m['fact_id'] for m in collected], sorted(c['fact_id'] for c in cards))
        self.assertEqual(len({m['fact_id'] for m in collected}), 11)
        self.assertEqual(sum(m['actor'] == 'team' for m in collected), 5)

    def test_utf8_response_budget_does_not_truncate_claims(self):
        cards = [self.add(i, text='I implemented ' + '🧠' * 500 + f' for Atlas case {i}.') for i in range(9)]
        collected, after = [], None
        for _ in range(6):
            page = self.page(after)
            self.assertLessEqual(len(json.dumps(page, ensure_ascii=False).encode()), 14 * 1024)
            collected += page['memories']
            after = page['next_after']
            if after is None:
                break
        self.assertEqual({m['claim_text'] for m in collected}, {c['snippet'] for c in cards})
        self.assertEqual(len(collected), 9)

    def test_malformed_paging_and_unknown_fields_are_rejected(self):
        for limit in [None, True, False, 0, 9, -1, 1.0, '2']:
            with self.subTest(limit=limit), self.assertRaises(BrainError):
                self.page(limit=limit)
        for after in [True, 12, [], '', 'x' * 65]:
            with self.subTest(after=after), self.assertRaises(BrainError):
                self.page(after=after)
        with self.assertRaises(BrainError):
            self.bridge.handle({'command': 'memories', 'after': None, 'limit': 2, 'approve': True})

    def test_corrected_memory_replaces_the_old_read_view(self):
        original = self.add(1)
        replacement = self.add(2, claim_key='atlas.case.1', replaces=original['fact_id'])
        page = self.page()
        self.assertEqual(page['total_count'], 1)
        self.assertEqual([m['fact_id'] for m in page['memories']], [replacement['fact_id']])
        self.assertEqual(page['memories'][0]['claim_text'], replacement['snippet'])

    def test_pending_source_text_never_appears_as_approved_memory(self):
        data = b'I chose SQLite for Atlas.'
        self.bridge.handle({'command': 'select_begin', 'size': len(data), 'sha256': sha256(data).hexdigest(),
                            'file_type': 'txt', 'purpose': 'project', 'label': 'Pending notes',
                            'role': 'developer', 'project_hint': 'Atlas'})
        self.bridge.handle({'command': 'transfer_chunk', 'offset': 0, 'data': base64.b64encode(data).decode()})
        state = self.bridge.handle({'command': 'select_commit'})
        self.assertIsNotNone(state['card'])
        self.assertEqual(self.page()['memories'], [])
        self.assertEqual(self.page()['total_count'], 0)
