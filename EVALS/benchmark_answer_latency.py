"""Bounded synthetic prompt comparison for an explicitly supplied product stream.

The executable only prints the plan. It never obtains credentials or constructs
an inference client. The owner-run account gate supplies the already authorized
protected_answer_stream and baseline instructions to compare_prompt_variants().
"""
from __future__ import annotations
import asyncio
from dataclasses import asdict
import json
import re

from relay_spike.conversation_context import ConversationContext
from relay_spike.generated_answer import (INSTRUCTIONS, CardError, make_prompt,
    parse_generated_card, requires_personal_evidence)
from relay_spike.oauth_answer_stream import OAuthAnswerStream, AnswerTransportError


CASES = (
    ('D07', 'Compare a SQL CTE and a subquery. Discuss readability and performance without assuming a database engine.',
     ('cover both readability and performance', 'avoid universal materialization or speed claims')),
    ('E09', 'Provide Python code for iterative binary search in an ascending list. Return -1 when absent. Handle empty input and explain complexity.',
     ('preserve explicit executable code and absent/empty behavior', 'verify boundaries and O(log n) time, O(1) extra space')),
    ('F01', 'Design a patient handoff feature. Identify users, the smallest useful workflow, a success measure, and one safety tradeoff.',
     ('cover all four requested parts', 'avoid invented user research or clinical claims')),
    ('P00', 'Tell me about yourself and the project you led.',
     ('missing confirmed personal evidence must avoid a model request',)),
)


def plan():
    return {'schemaVersion': 1, 'syntheticOnly': True, 'variants': ['baseline', 'compact'],
            'maximumModelRequests': 6, 'cases': [{'caseID': key, 'question': question,
                'rubric': list(rubric)} for key, question, rubric in CASES]}


async def compare_prompt_variants(stream, baseline_instructions, *, include_answers=False):
    if not isinstance(stream, OAuthAnswerStream) or stream._token_provider is None:
        raise ValueError('explicit_product_stream_required')
    if not isinstance(baseline_instructions, str) or not baseline_instructions:
        raise ValueError('baseline_instructions_required')
    instructions = {'baseline': baseline_instructions, 'compact': INSTRUCTIONS}
    results = []
    for index, (case, question, rubric) in enumerate(CASES):
        # Alternate order to expose first-request/setup and simple ordering bias.
        order = ('baseline', 'compact') if index % 2 == 0 else ('compact', 'baseline')
        for variant in order:
            row = {'caseID': case, 'variant': variant, 'model': stream.model,
                   'requestedEffort': stream.effort or 'default', 'correctness': 'unreviewed',
                   'firstUsefulVerifiedMs': None}
            if requires_personal_evidence(question):
                row.update(outcome='personal_context_missing', modelAttempts=0, qa='host_withheld')
                results.append(row)
                continue
            context = ConversationContext(); context.observe('remote', question)
            prompt = make_prompt(question, context.snapshot(), None)
            previous = stream.last_timing
            # This counts complete() attempts, never claims provider receipt.
            row['modelAttempts'] = 1
            try:
                raw = await stream.complete(prompt, instructions[variant])
                code_required = bool(re.search(r'\b(?:write|show|provide)\b.{0,30}\b(?:code|function|query|sql)\b', question, re.I))
                card = parse_generated_card(raw, code_required=code_required)
                row.update(outcome='completed', qa='format_checked',
                    outputBytes=len(raw.encode()), spokenWords=len(' '.join((card.lead, *card.points)).split()),
                    detailBytes=len(card.detail.text.encode()) if card.detail else 0)
                if include_answers: row['card'] = card.as_dict()
            except asyncio.CancelledError:
                raise
            except CardError:
                row.update(outcome='withheld', qa='card_rejected')
            except AnswerTransportError:
                row.update(outcome='failed', qa='transport_failed')
            finally:
                timing = stream.last_timing
                if timing is not previous and timing is not None:
                    row['transport'] = asdict(timing)
            results.append(row)
    return {'schemaVersion': 1, 'syntheticOnly': True, 'results': results,
            'scope': 'model transport plus deterministic format checks; excludes native audio, capture and display'}


if __name__ == '__main__':
    print(json.dumps(plan(), indent=2))
