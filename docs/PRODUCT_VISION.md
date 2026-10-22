# Relay product vision and UX contract

Last reviewed: 2026-10-22. Status: accepted intent; implementation is not yet built.

## Meaning
Like Flick captures game clips, Derive derives personalized skincare recommendations and Manifest converts BCI signals into output, Relay receives a question, locates the right context and relays relevant information back in the moment.

## Objective and users
A personalized macOS assistant intended to improve real job interview performance, in settings where assistance is authorized. It is not a study app. Priority is low latency, accurate technical information, verified personal experiences and immediately scannable answers. It should not promise being hidden in every screen-share mode.

Initial target roles: Epic Software Developer, and junior AI/BI/data analytics/data visualization. Job descriptions, actual interview stages and verified personal data override generic internet question lists. Do not invent direct Power BI or Tableau experience.

## Core capabilities
1. Live question recognition from permitted mic and system audio with sensible speaker attribution, multi-part question handling, interruption and corrected-question cancellation.
2. Role Packs with technical topic priorities, edge cases, jargon, credible likely questions and the real job posting.
3. Personal Brain with resume, selected Drive/GitHub content, imported chat exports where approved, and conversational follow-up questions to complete experience stories. Do not assume existing ChatGPT memory or connector access transfers automatically.
4. Fast response and selective review: first useful talking point, up to two supporting details, expand for code/SQL/example. Favor meaningful partial answer over lengthy full generation.
5. Continuous learning: track repeated question concepts, assistant errors, explicit user corrections, and preferred answer style; improve retrieval and formatting between sessions.
6. Optional adaptive mock interviewer to stress-test the assistant with realistic follow-up and edge-case questions, NOT mandatory lessons.
7. Debrief and personalized continuity, if session recording/retention is authorized.

## Three primary experiences
- Before interview: choose exact job role, posting, interview round, resume and approved personal context; ensure auth permissions and consent are clear; prefetch bounded likely context.
- During permitted session: surface direct answer first in minimal overlay, keep relevant context across follow-ups, update on changed constraints, show honest uncertainty if data missing, let user expand.
- After session: summarize observed topics and explicit quality feedback, queue candidate memory facts for user approval, improve future answers; avoid speculative interviewer-sentiment or hiring predictions.

## Answer contract
- Lead with short direct explanation, in natural conversational voice.
- Technical: include assumptions and most relevant edge cases, avoid fabricated execution results.
- SQL/analytics: reason about grain, joins/fanout, filters, denominator, date boundaries and dialect; example only when useful.
- Code: approach, correctness, complexity and edge cases; never pretend missing code is visible.
- Personal/behavioral: use source-confirmed actual contribution, story structure and honest limitations; no fabricated work history.
- Multi-part: cover all parts, prioritize clarity over exhaustive detail.
- Make low-confidence or unanswerable cases explicit and never put a guessed personal story in the user's mouth.

## Quality gate
The first validation stage is cheap: unsupported personal-claim detection, topic/parts coverage, readability, deterministic code/SQL checks when executable inputs exist. Use a targeted second AI review for complex or high-risk answers, not for every simple definition. Measure whether the review improves accuracy enough to justify time and usage. Quality suggestions are not independent ground truth.

## Continuous learning policy
- Personal Brain and Learning Memory are distinct and reversible.
- Real questions may improve role-topic weights; a few interviews cannot establish overall company patterns.
- Corrections that assistant misunderstood terminology, used too many words or omitted an SQL edge case may adjust future outputs.
- Only confirmed autobiographical facts are promoted into Personal Brain, not utterances that could be hypotheticals or transcription errors.
- Adapt without overfitting, and evaluate against held-out question cases.

## Scope boundaries
Not a credential-faking assistant, unauthorized interview cheating or undetectable screen-share product. Not an ongoing coursework platform, course quiz engine, job-application CRM, emotion detector, employment-outcome predictor, or blanket all-documents data collector.

## Success targets, not observed results
Initial first useful response goal: around 2 to 4 seconds after complete question, with p50 target <= 4 seconds; measure p95 and end-to-end performance. Zero invented personal claims on negative tests. Stable on the user's 16 GB M2 Pro alongside everyday apps. Role-specific edge cases outperform a generic prompt baseline.
