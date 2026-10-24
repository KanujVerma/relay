# Résumé backend relevance correction review

Exactbackendf353253 plus08201bc9e8c1d8d3cd9b63f7f45875ee646c300b andc04388739329fbf0ba582b74717fe5559962a104, PR90. Independently reviewed in clean immutable clones. Finalc043 accepted at backend review/restore/retrieval/renderer boundary; native/formats/app remain separately attributed.

Original [P2 report](review-resume-backend-f353253.md) showed real restored Host output for Birch Labs also containing Cedar Labs. Correction082 binds complete reviewed entry aliases and residual topic terms. The exact original proof then produced only its requested entry, but a same-root-cause prefix variant still mixed Harbor with Harbor Labs when only Harbor Labs was asked. Actual Host proof confirmed both points and zero model requests. Correctionc043 resolves maximal nonoverlapping full-name occurrences, preserving a separately mentioned short name. Equal normalized aliases owned by different entry IDs withhold instead of silently merging authority. Lookup normalization never rewrites stored evidence/qualifiers.

Independent final64focused Python pass1.126s. The original actual approved→snapshot/restore→Host probe now emits one correct point in both Birch/Cedar directions; the unchanged Harbor/Harbor Labs variant also emits one correct point in both directions. Expected2027 remains intact, no model calls. Actual Host tests additionally cover projects, explicit short+long requests, shared/unknown partial names, broad contribution requests, NFC/NFD/case ambiguity and unique normalized lookup.

## Narrow variant search

The violated invariant is named-entry relevance: an explicitly named reviewed entry must not admit another solely through common or embedded name text. Whole-repository ripgrep calibrated the exact question_terms intersection, then traced mentions_entry/named_entries to the provider and helper renderer. One provider implementation and its pure alias helper are the active path; no second copied implementation was found. This is a logic/answer relevance review, not a security scan.

| Probe family | Final result | Verdict |
| --- | --- | --- |
| Birch Labs / Cedar Labs, either direction | One requested entry | Original P2 closed |
| Harbor / Harbor Labs and Atlas / Atlas Monitor | Embedded short name excluded for long-only occurrence | P2 variant closed |
| Explicit separate short and long names | Both honest units retained | Positive control |
| Equal normalized aliases in distinct entries | No mixed structured facts | Ambiguity withheld |
| Unrelated Swift use, team-only self biography, listed skill versus actual use | Existing withholding preserved | Negative controls |

Earlier any-overlap pattern and then whole-name-only pattern both had concrete failing examples; neither alone was accepted. Existing discoverable unittest cases provide the regression guard. No new name/technology registry, generated biography, actor promotion, field truncation or model call is introduced. First-increment layout/long-unit limitations remain. The API review and native/formats gates do not imply universal natural-language or template recognition.
