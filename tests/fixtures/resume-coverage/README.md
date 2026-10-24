# Fictional résumé fixtures

Every institution, company, qualification, project, date and statement here is
fabricated test data. None comes from a person's résumé or private file.

`tests/support/generate_resume_fixtures.py` generates the canonical UTF-8 TXT,
one-column selectable PDF and plain body-paragraph DOCX, plus exact byte hashes
in `manifest.json`. The PDF uses original minimal PDF text commands and the
built-in Helvetica font reference; no embedded assets or copied template.
DOCX uses existing pinned python-docx1.2.0 and fixed ZIP/core metadata times.
Importing the generator is inert; writing requires explicit `--output`.

These exercise completed/Expected education and literal GPA, two employers,
multiple projects, self/team/teammate claims, listed Python/SQL/C++/R and actual tool
use, certification issuer/status, and an exact summary. They prove only this
simple linear layout. Columns/tables/headers and arbitrary template reading
order remain outside increment1 acceptance.
