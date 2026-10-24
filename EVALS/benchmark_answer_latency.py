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
from relay_spike.stream import validated_reasoning_effort


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
_NO_REPORT = object()


def plan():
    return {'schemaVersion': 1, 'syntheticOnly': True, 'variants': ['baseline', 'compact'],
            'maximumModelRequests': 6, 'cases': [{'caseID': key, 'question': question,
                'rubric': list(rubric)} for key, question, rubric in CASES],
            'effortComparison': {'model':'gpt-6-luna','variants':['default','none'],
                'maximumModelAttempts':6,'prompt':'identical compact instructions'}}


def _require_dedicated_stream(stream):
    if not isinstance(stream, OAuthAnswerStream) or stream._token_provider is None:
        raise ValueError('explicit_product_stream_required')
    if stream._active:
        raise ValueError('benchmark_stream_busy')


async def compare_prompt_variants(stream, baseline_instructions, *, include_answers=False, report=_NO_REPORT):
    _require_dedicated_stream(stream)
    if not isinstance(baseline_instructions, str) or not baseline_instructions:
        raise ValueError('baseline_instructions_required')
    variants={'baseline':(baseline_instructions,stream.effort),'compact':(INSTRUCTIONS,stream.effort)}
    return await _compare(stream,variants,comparison='prompt',include_answers=include_answers,report=report)


async def compare_effort_variants(stream, *, include_answers=False, report=_NO_REPORT):
    """Evaluation only: an isolated caller-owned product stream, never a session.

    Validate every requested combination before token/client access. Both paths
    use the same compact prompt; literal none is distinct from field omission.
    Original per-instance configuration is restored even on cancellation. Pass
    an empty report dict to retain partial evidence when CancelledError escapes.
    """
    _require_dedicated_stream(stream)
    validated_reasoning_effort(stream.model,'none')
    if stream.model!='gpt-6-luna':raise ValueError('explicit_luna_stream_required')
    variants={'default':(INSTRUCTIONS,None),'none':(INSTRUCTIONS,'none')}
    return await _compare(stream,variants,comparison='reasoning_effort',include_answers=include_answers,report=report)


async def _compare(stream, variants, *, comparison, include_answers, report):
    if report is _NO_REPORT:report={}
    elif type(report) is not dict or report:raise ValueError('empty_report_required')
    results = []
    report.update(schemaVersion=1,syntheticOnly=True,comparison=comparison,status='running',
        maximumModelAttempts=6,declaredModelAttempts=0,results=results,
        scope='model transport plus deterministic format checks; excludes native audio, capture and display')
    original_effort=stream.effort
    attempts=0
    try:
        for index, (case, question, rubric) in enumerate(CASES):
            # Alternate order to expose first-request/setup and simple ordering bias.
            names=tuple(variants)
            order=names if index%2==0 else tuple(reversed(names))
            for variant in order:
                instructions,effort=variants[variant]
                row = {'caseID': case, 'variant': variant, 'model': stream.model,
                       'requestedEffort': effort or 'default', 'serverReportedEffort':None,
                       'correctness': 'unreviewed','firstUsefulVerifiedMs': None}
                if requires_personal_evidence(question):
                    row.update(outcome='personal_context_missing', modelAttempts=0, qa='host_withheld')
                    results.append(row);continue
                if attempts>=6:
                    row.update(outcome='request_cap_reached',modelAttempts=0,qa='host_withheld')
                    results.append(row);continue
                context = ConversationContext(); context.observe('remote', question)
                prompt = make_prompt(question, context.snapshot(), None)
                previous = stream.last_timing
                # This counts complete() attempts, never claims provider receipt.
                attempts+=1;report['declaredModelAttempts']=attempts;row['modelAttempts'] = 1;stream.effort=effort
                try:
                    raw = await stream.complete(prompt, instructions)
                    code_required = bool(re.search(r'\b(?:write|show|provide)\b.{0,30}\b(?:code|function|query|sql)\b', question, re.I))
                    card = parse_generated_card(raw, code_required=code_required)
                    row.update(outcome='completed', qa='format_checked',
                        outputBytes=len(raw.encode()), spokenWords=len(' '.join((card.lead, *card.points)).split()),
                        detailBytes=len(card.detail.text.encode()) if card.detail else 0)
                    if include_answers: row['card'] = card.as_dict()
                except asyncio.CancelledError:
                    row.update(outcome='cancelled',qa='request_cancelled')
                    results.append(row)
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
    except asyncio.CancelledError:
        report['status']='cancelled'
        raise
    except BaseException:
        report['status']='interrupted'
        raise
    else:
        report['status']='finished'
    finally:
        stream.effort=original_effort
    return report


if __name__ == '__main__':
    print(json.dumps(plan(), indent=2))
