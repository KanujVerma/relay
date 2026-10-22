#!/usr/bin/env python3
"""Validate synthetic Slice 00 interview question fixtures (stdlib only)."""

from __future__ import annotations
import json
from collections import Counter
from pathlib import Path

SOURCE = Path(__file__).with_name("interview-questions.jsonl")
REQUIRED = {"id", "role", "category", "question", "expected_behavior", "error_to_avoid", "context"}
ROLES = {"epic", "analytics"}
CATEGORIES = {"coding", "sql", "edge_case", "ambiguity", "multi_part", "correction", "behavioral", "personal", "interruption", "metrics", "visualization"}

def main() -> None:
    ids = set()
    roles = Counter()
    categories = set()
    for line_number, line in enumerate(SOURCE.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{SOURCE}:{line_number}: invalid JSON: {exc}") from exc
        if not isinstance(entry, dict):
            raise SystemExit(f"{SOURCE}:{line_number}: must be a JSON object")
        if set(entry) != REQUIRED:
            missing = sorted(REQUIRED - set(entry))
            extra = sorted(set(entry) - REQUIRED)
            raise SystemExit(f"{SOURCE}:{line_number}: wrong fields: missing={missing} extra={extra}")
        if any(not isinstance(entry[k], str) or not entry[k].strip() for k in REQUIRED):
            raise SystemExit(f"{SOURCE}:{line_number}: all fields must be nonempty strings")
        if entry["id"] in ids:
            raise SystemExit(f"{SOURCE}:{line_number}: duplicate id {entry['id']}")
        ids.add(entry["id"])
        if entry["role"] not in ROLES:
            raise SystemExit(f"{SOURCE}:{line_number}: invalid role {entry['role']}")
        if entry["category"] not in CATEGORIES:
            raise SystemExit(f"{SOURCE}:{line_number}: invalid category {entry['category']}")
        roles[entry["role"]] += 1
        categories.add(entry["category"])

    if any(roles[role] < 10 for role in ROLES):
        raise SystemExit(f"at least ten questions required per role; got {dict(roles)}")
    needed = {"coding", "sql", "edge_case", "ambiguity", "multi_part", "correction", "behavioral", "personal", "interruption"}
    if needed - categories:
        raise SystemExit(f"missing question families: {sorted(needed - categories)}")
    print(f"OK: {len(ids)} synthetic questions, roles={dict(roles)}, categories={len(categories)}")

if __name__ == "__main__":
    main()
