# Live answer readiness, 2026-10-25

Source: `04fdee09f7541c52f9292fca2370b985c0233f9d`, integration branch. Main remains unmerged. This is a runtime observation, not full product acceptance.

The corrected stock Release app was built with retained offline inputs, moved as one complete app, and signed with the owner-approved existing development profile. The observed repeat stock build exited zero in 80.63 seconds; the preceding resource-monitor failure is retained separately with its original stock exit unknown. Strict signatures and 100 native-file audits pass. Nine frozen-helper checks pass without skips or failures in 9.111 seconds. The earlier source replay collected 863 Python tests: 831 passed and 32 optional skips, with no failures.

Normal saved-account restore now succeeds. A fresh content-free catalog record reports HTTP 200, 653,033 decoded bytes, 11 raw model rows, eight visible rows and `valid`. Native Settings shows Connected, plan AI enabled, and Automatic model GPT-6.1-Sol. This proves the catalog correction in the signed app; it does not prove answer generation.

One new declared synthetic Release UI question was submitted after that success:

> Compare a SQL CTE and a subquery. Discuss readability and performance without assuming a database engine.

The app entered its actual assistant window and showed Thinking. The next observation showed Answer unavailable and No reliable answer available. No answer card appeared. The first observation was approximately 1.02 seconds after Send; the failed state was observed approximately 25.99 seconds after Send, including time between observations. Neither number establishes provider latency or the exact failure time. The actual provider POST count and rejection stage remain unobserved. No automatic retry occurred.

History saving, Learning, saved response guides, screen and image context were off. Personal context was temporarily locked without deleting facts, then restored through the ordinary My Context UI after ending the failed test session. No résumé, private transcript, credentials, raw response, account identifiers or signing identity is included here. The app was left idle, with recording consent unchecked and Start disabled.

Next: distinguish transport rejection/timeout, stream validation and card validation using bounded content-free diagnostics or the authorized normal app test host. Preserve currentness, one-call ownership, protected storage and all publication checks. Do not change model, effort, deadlines or output guards on the basis of this undifferentiated failure. The missing-personal-context control, successful live answers, useful-answer timing, physical capture and full mock interview acceptance remain open.
