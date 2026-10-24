"""Source-derived design oracle, not production VAD/ASR or a runtime benchmark.

Reference: pinned FluidAudio c79c4106b954f81205113c3343e5a7e59a1089b5,
VadManager+Streaming.swift and VadTypes.swift. This uses three representative
probability classes and unchanged default sample/segmentation constants.
No upstream code copied, no model/framework/dependency imported.
"""


def observations(sequence):
    processed, triggered, candidate, active_start = 0, False, None, None
    rows = []
    for probability_class in sequence:
        if probability_class not in ('speech', 'band', 'silence'):
            raise ValueError('unknown_probability_class')
        processed += 4096
        start, end = None, None
        if probability_class == 'speech':
            candidate = None
            if not triggered:
                triggered = True
                start = active_start = max(0, processed-1600-4096)
        elif probability_class == 'silence' and triggered:
            if candidate is None: candidate = processed
            if processed-candidate >= 12000:
                end = max(0, candidate+1600-4096)
                triggered, candidate = False, None
        safe_end = None
        if triggered:
            safe_end = processed-4096
            if candidate is not None: safe_end = min(safe_end, candidate+1600-4096)
            safe_end = max(active_start, safe_end)
        rows.append(dict(processed=processed, start=start, end=end,
                         candidate=candidate, safe_end=safe_end))
        if end is not None: active_start = None
    return rows


def submitted_activities(steps):
    rows, active, submitted = [], None, None
    for step in steps:
        if step['start'] is not None:
            if active is not None: raise ValueError('overlapping_original_activity')
            submitted = step['start']
            active = dict(start=submitted, end=None, prefix=[], tail=None)
            rows.append(active)
        if active is not None and step['safe_end'] is not None:
            if step['safe_end'] < submitted: raise ValueError('backwards_watermark')
            while submitted+5120 <= step['safe_end']:
                active['prefix'].append((submitted, submitted+5120))
                submitted += 5120
        if step['end'] is not None:
            if active is None or submitted > step['end']:
                raise ValueError('prefix_past_final_cutoff')
            active.update(end=step['end'], tail=(submitted, step['end']))
            active, submitted = None, None
    return rows
