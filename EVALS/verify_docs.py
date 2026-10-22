#!/usr/bin/env python3
"""Validate Relay's durable documentation files and local Markdown links (offline)."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "AGENTS.md",
    "README.md",
    "HANDOFF.md",
    "PRODUCT.md",
    "ARCHITECTURE.md",
    "docs/PRODUCT_VISION.md",
    "docs/DECISIONS.md",
    "docs/WORKFLOWS.md",
    "docs/MEMORY_AND_EVALUATION.md",
    "docs/INFERENCE_AUTH.md",
    "docs/SLICES.md",
    "docs/REFERENCES.md",
    "ROLE_PACKS/epic-software-developer.md",
    "ROLE_PACKS/junior-data-analytics.md",
    "EVALS/interview-questions.jsonl",
]
MARKDOWN_LINK = re.compile(r"\[[^\]]+\]\(([^)]+)\)")

def main() -> None:
    errors = []
    for name in REQUIRED:
        if not (ROOT / name).is_file():
            errors.append(f"required file is missing: {name}")
    for md in ROOT.rglob("*.md"):
        if any(part.startswith(".") for part in md.relative_to(ROOT).parts):
            continue
        for line_num, line in enumerate(md.read_text(encoding="utf-8").splitlines(), start=1):
            for match in MARKDOWN_LINK.finditer(line):
                dest = match.group(1).strip().split("#", 1)[0]
                if not dest or dest.startswith(("https://", "http://", "mailto:")):
                    continue
                path = (md.parent / dest).resolve()
                if not path.is_relative_to(ROOT.resolve()) or not path.exists():
                    errors.append(f"{md.relative_to(ROOT)}:{line_num}: broken link {dest!r}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"OK: {len(REQUIRED)} required files and local Markdown links")

if __name__ == "__main__":
    main()
