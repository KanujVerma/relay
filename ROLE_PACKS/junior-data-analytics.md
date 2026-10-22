# Role Pack: junior BI / analytics / data visualization

Status: initial role profile; specialize further from the exact vacancy and hiring team's requirements. Do not claim Power BI or Tableau hands-on experience unless confirmed.

## Focus areas, in priority order
- SQL: joins and cardinality, GROUP BY/HAVING, CTEs, window functions, nulls, aggregate grain, deduplication and filters.
- Reporting correctness: revenue double-counting from joins, denominator changes under filters, dates/timezones, missing data and conflicting metric definitions.
- Data visualization: choosing chart types, interpreting trends, communicating uncertainty, dashboard filters and chart accessibility.
- Analytics/business reasoning: meaningful KPIs, cohort definitions, conversion, retention, north-star vs supporting metrics, stakeholders and trade-offs.
- Python/data tasks: basic pandas or SQL alternatives, cleaning, testing assumptions, traceability of transformations.
- Honest professional experience: strengths in transferable skills without falsely claiming specific dashboard-tool proficiency.

## Interview answer contract
- Direct one-sentence explanation first; show a concrete SQL/data example when helpful.
- Before computing a business metric, define grain, numerator, denominator, filters, time window and source-of-truth table.
- For dialect-sensitive SQL, state assumptions or ask which database is in use.
- Distinguish correct-looking SQL from verified execution and test results.
- Admit lack of direct tool experience if asked, while explaining verified related skills.

## Edge cases to test
Join fanout; missing rows and NULLs; inclusive vs exclusive date boundaries; window vs group aggregation; ties in ranking; COUNT(*) vs COUNT(col) vs COUNT(DISTINCT); percentages with changing denominator; metric leakage; contradictory dashboards; noisy interview audio.

## Context to load before a session
Exact job description, SQL dialect, job-specific tooling, verified projects/experience, actual technical skills, and relevant personal stories.

## Success measure
Accurate metric reasoning, concise SQL explanation, sensible business framing and zero invented tool experience.
