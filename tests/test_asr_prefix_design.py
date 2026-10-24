"""Design-only cutoff invariant, no app/ASR/model/network/runtime acceptance.

Three probability classes exhaust the pinned state machine's branch choices.
Bounded exhaustive enumeration uses the standard library, no new dependency.
"""
from itertools import product
import json
from pathlib import Path
import unittest

from EVALS.asr_prefix_design import observations, submitted_activities


class ASRPrefixDesignTests(unittest.TestCase):
    def test_named_original_cutoffs_and_leading_padding(self):
        fixture = json.loads((Path(__file__).parent/'fixtures'/'asr-prefix-design.json').read_text())
        self.assertEqual(len(fixture['cases']), 6)
        for case in fixture['cases']:
            sequence = [value for value, count in case['groups'] for _ in range(count)]
            rows = submitted_activities(observations(sequence))
            with self.subTest(case=case['id']):
                self.assertEqual([r['start'] for r in rows], case['starts'])
                self.assertEqual([r['end'] for r in rows], case['ends'])
                for row in rows: self.assert_complete_prefix(row)

    def assert_complete_prefix(self, row):
        cursor = row['start']
        for start, end in row['prefix']:
            self.assertEqual(start, cursor)
            self.assertEqual(end-start, 5120)
            cursor = end
        if row['end'] is not None:
            self.assertLessEqual(cursor, row['end'])
            self.assertEqual(row['tail'], (cursor, row['end']))
            self.assertLess(row['end']-cursor, 5120)
        else:
            self.assertIsNone(row['tail'], 'Open VAD activity cannot finalize ASR')

    def test_fixed_lag_has_a_retained_hysteresis_counterexample(self):
        sequence = ['speech']*4 + ['silence'] + ['band']*12 + ['silence']
        steps = observations(sequence)
        end = next(s['end'] for s in steps if s['end'] is not None)
        # A fixed 1.024 s lag advances while the old candidate end stays frozen.
        fixed_lag_submitted = max(s['processed']-16_384 for s in steps[:-1])
        self.assertGreater(fixed_lag_submitted, end)
        rows = submitted_activities(steps)
        self.assertLessEqual(rows[0]['prefix'][-1][1], end)

    def test_all_short_band_sequences_preserve_future_cutoffs_and_partition(self):
        checked = 0
        for length in range(9):
            for tail in product(('speech', 'band', 'silence'), repeat=length):
                sequence = ['speech', *tail, *(['silence']*4)]
                rows = submitted_activities(observations(sequence))
                self.assertTrue(rows)
                for row in rows: self.assert_complete_prefix(row)
                checked += 1
        self.assertEqual(checked, 9841)

    def test_pending_end_cap_does_not_advance_through_middle_band(self):
        sequence = ['speech']*4 + ['silence'] + ['band']*40
        steps = observations(sequence)
        candidate = steps[4]['candidate']
        self.assertTrue(all(s['candidate']==candidate for s in steps[4:]))
        self.assertTrue(all(s['safe_end']<=candidate+1600-4096 for s in steps[4:]))
        self.assertTrue(all(s['end'] is None for s in steps))


if __name__ == '__main__': unittest.main()
