"""Composable profile port for a native-owned inherited pipe.

The final app embeds ProfileBridge in the *same* helper as its answer engine
and gives that engine this object as PersonalContextProvider. The standalone
entry point is a preparation demo harness, not a second persistent database.
Messages are accepted only from the trusted host's owned descriptor. There is
no network listener, path importer, authorization boolean or model tool port.
This is an application boundary, not OS attestation of a physical click.
"""
from __future__ import annotations

import base64
from dataclasses import asdict
from datetime import datetime, timezone
from hashlib import sha256
import json
import re
import struct
import sys
import unicodedata
from typing import Callable

from .personal_brain import BrainError, BrainStore
from .personal_context import ContextBundle
from .profile_preparation import (MAX_SNAPSHOT_BYTES, ProfilePreparation,
                                  export_memory_snapshot, restore_memory_snapshot)

MAX_FRAME_BYTES = 16 * 1024
CHUNK_BYTES = 4096
_FIELDS = {
    "new": (), "lock": (), "state": (), "sources": (), "snapshot_begin": (), "snapshot_end": (),
    "snapshot_chunk": ("offset",),
    "load_begin": ("size", "sha256"), "load_commit": (),
    "select_begin": ("size", "sha256", "file_type", "purpose", "label", "role", "project_hint"),
    "select_commit": (), "transfer_chunk": ("offset", "data"), "transfer_abort": (),
    "decide": ("fact_id", "fingerprint", "decision", "actor", "claim_key", "replaces_fact_id"),
    "decide_v2": ("fact_id", "fingerprint", "decision", "actor", "claim_key", "replaces_fact_id", "card_version", "context_sha256"),
    "approve_job": ("source_id", "fingerprint"), "revoke": ("source_id",),
    "current_claim": ("claim_key",),
    "memories": ("after", "limit"),
}


class ProfileBridge:
    def __init__(self, *, on_change: Callable[[], None] = lambda: None) -> None:
        self.__cap = object()
        self._prep = ProfilePreparation(BrainStore(), host_capability=self.__cap)
        self._ready = False
        self._on_change = on_change
        self._transfer: dict | None = None
        self._snapshot: bytes | None = None

    def close(self) -> None:
        self._retire()
        self._ready = False
        self._transfer = None
        self._prep.store.close()

    def _retire(self) -> None:
        self._prep.provider._issued.clear()
        self._snapshot = None
        self._on_change()

    def retrieve(self, question: str, role: str, project_hint: str | None = None,
                 budget: int = 8) -> ContextBundle:
        if not self._ready:
            raise BrainError("Profile is not ready.")
        return self._prep.provider.retrieve(question, role, project_hint, budget)

    def validate_current(self, bundle: ContextBundle) -> bool:
        return self._ready and self._prep.provider.validate_current(bundle)

    def _state(self) -> dict:
        cards = self._prep.pending_cards()
        job = None
        if not cards:
            row = self._prep.store.db.execute(
                "SELECT j.source_id,j.text,j.fingerprint FROM profile_job_context j "
                "JOIN source s ON s.id=j.source_id WHERE j.confirmed_at IS NULL "
                "AND s.revoked_at IS NULL AND j.text IS NOT NULL ORDER BY j.rowid LIMIT 1"
            ).fetchone()
            job = dict(row) if row else None
        card = asdict(cards[0]) if cards else None
        if card is not None:
            locator = self._prep.store.db.execute("SELECT locator FROM profile_locator WHERE fact_id=?",
                                                   (card["fact_id"],)).fetchone()
            card["locator"] = locator[0] if locator else None
        return {"ok": True, "ready": self._ready, "card": card,
                "pending_count": len(cards), "job": job}

    def _finish_transfer(self, kind: str) -> tuple[bytes, dict]:
        transfer, self._transfer = self._transfer, None
        if transfer is None or transfer["kind"] != kind:
            raise BrainError("Profile transfer is unavailable.")
        data = bytes(transfer["bytes"])
        if len(data) != transfer["size"] or sha256(data).hexdigest() != transfer["sha256"]:
            raise BrainError("Profile transfer is incomplete or corrupt.")
        return data, transfer

    def _memory_page(self, message: dict) -> dict:
        after, limit = message.get("after"), message.get("limit")
        if (type(limit) is not int or not 1 <= limit <= 8 or
                (after is not None and
                 (not isinstance(after, str) or re.fullmatch(r"[A-Za-z0-9_.:-]{1,64}", after) is None))):
            raise BrainError("Invalid memory page.")
        # This is a read view of the existing authority filter. It cannot
        # confirm a candidate, issue a context bundle or retire one.
        active = sorted(self._prep.store.verified_claims(), key=lambda fact: fact.fact_id)
        remaining = [fact for fact in active if after is None or fact.fact_id > after]
        page = {"ok": True, "memories": [], "total_count": len(active), "next_after": None}
        for index, fact in enumerate(remaining):
            source = self._prep.store.db.execute(
                "SELECT label FROM profile_source WHERE source_id=?", (fact.source_id,)
            ).fetchone()
            row = {"fact_id": fact.fact_id, "claim_key": fact.claim_key,
                   "claim_text": fact.claim_text, "actor": fact.actor,
                   "source_id": fact.source_id,
                   "source_label": source[0][:64] if source and source[0] else "Saved source"}
            trial = {**page, "memories": [*page["memories"], row],
                     "next_after": fact.fact_id if index + 1 < len(remaining) else None}
            if len(json.dumps(trial, ensure_ascii=False, allow_nan=False).encode()) > 14 * 1024:
                if not page["memories"]:
                    raise BrainError("Memory cannot fit a bounded page.")
                break
            page = trial
            if len(page["memories"]) == limit:
                break
        return page

    def handle(self, message: dict) -> dict:
        if not isinstance(message, dict) or not isinstance(message.get("command"), str):
            raise BrainError("Invalid profile command.")
        command = message["command"]
        if command not in _FIELDS or set(message) - {"command", *_FIELDS[command]}:
            raise BrainError("Unsupported profile command fields.")
        if command == 'decide_v2' and set(message) != {'command', *_FIELDS[command]}:
            raise BrainError('Incomplete résumé review command.')
        if len(json.dumps(message, ensure_ascii=False).encode()) > MAX_FRAME_BYTES:
            raise BrainError("Profile frame exceeds its bound.")
        if command == "new":
            if self._ready or self._transfer or self._prep.store.db.execute("SELECT 1 FROM source LIMIT 1").fetchone():
                raise BrainError("Profile is already initialized.")
            self._ready = True
            return self._state()
        if command == "lock":
            self._retire()
            self._ready = False
            self._transfer = None
            self._prep.store.close()
            self._prep = ProfilePreparation(BrainStore(), host_capability=self.__cap)
            return {"ok": True, "locked": True, "ready": False}
        if command in ("load_begin", "select_begin"):
            if self._transfer is not None:
                raise BrainError("A profile transfer is already active.")
            if command == "select_begin" and not self._ready:
                raise BrainError("Open the protected profile first.")
            if command == "load_begin" and self._ready:
                raise BrainError("Lock the active profile before loading a snapshot.")
            size, digest = message.get("size"), message.get("sha256")
            limit = MAX_SNAPSHOT_BYTES if command == "load_begin" else 2 * 1024 * 1024
            if (type(size) is not int or not 0 < size <= limit or
                    not isinstance(digest, str) or re.fullmatch("[0-9a-f]{64}", digest) is None):
                raise BrainError("Invalid profile transfer manifest.")
            self._retire()
            if command == "load_begin":
                self._ready = False
            self._transfer = {**message, "kind": "load" if command == "load_begin" else "select", "bytes": bytearray()}
            return {"ok": True}
        if command == "transfer_chunk":
            transfer = self._transfer
            if transfer is None or type(message.get("offset")) is not int or message["offset"] != len(transfer["bytes"]):
                raise BrainError("Out-of-order profile chunk.")
            encoded = message.get("data")
            if not isinstance(encoded, str) or len(encoded) > 5500:
                raise BrainError("Invalid profile chunk.")
            try:
                part = base64.b64decode(encoded, validate=True)
            except (ValueError, TypeError):
                raise BrainError("Invalid profile chunk.") from None
            if not 0 < len(part) <= CHUNK_BYTES or len(transfer["bytes"]) + len(part) > transfer["size"]:
                raise BrainError("Profile chunk exceeds its bound.")
            transfer["bytes"].extend(part)
            return {"ok": True}
        if command == "transfer_abort":
            self._transfer = None
            return {"ok": True}
        if command == "load_commit":
            data, _ = self._finish_transfer("load")
            restored = restore_memory_snapshot(data)
            try:
                prep = ProfilePreparation(restored, host_capability=self.__cap)
            except Exception:
                restored.close()
                raise
            self._prep.store.close()
            self._prep = prep
            self._ready = True
            return self._state()
        if not self._ready:
            raise BrainError("Profile is not ready.")
        if command == "select_commit":
            data, fields = self._finish_transfer("select")
            self._prep.select_bytes(data, file_type=fields.get("file_type"), purpose=fields.get("purpose"),
                label=fields.get("label"), role=fields.get("role"), project_hint=fields.get("project_hint"),
                observed_at=datetime.now(timezone.utc).isoformat(), capability=self.__cap)
            return self._state()
        if command == "decide":
            self._retire()
            self._prep.decide(message.get("fact_id"), message.get("fingerprint"),
                decision=message.get("decision"), actor=message.get("actor"), claim_key=message.get("claim_key"),
                replaces_fact_id=message.get("replaces_fact_id"), capability=self.__cap)
            return self._state()
        if command == 'decide_v2':
            self._retire()
            self._prep.decide_v2(message['fact_id'], message['fingerprint'],
                decision=message['decision'], actor=message['actor'], claim_key=message['claim_key'],
                replaces_fact_id=message['replaces_fact_id'], card_version=message['card_version'],
                context_sha256=message['context_sha256'], capability=self.__cap)
            return self._state()
        if command == "approve_job":
            self._retire()
            self._prep.approve_job(message.get("source_id"), message.get("fingerprint"), capability=self.__cap)
            return self._state()
        if command == "revoke":
            self._retire()
            self._prep.revoke(message.get("source_id"), capability=self.__cap)
            return self._state()
        if command == "state":
            return self._state()
        if command == "sources":
            rows = self._prep.store.db.execute(
                "SELECT p.source_id,p.label,p.purpose FROM profile_source p JOIN source s ON s.id=p.source_id "
                "WHERE s.revoked_at IS NULL ORDER BY p.rowid")
            sources = []
            for row in rows:
                item = {'source_id': row[0], 'label': row[1][:64], 'purpose': row[2]}
                coverage = self._prep.store.db.execute('SELECT coverage_json FROM profile_resume_coverage WHERE source_id=?', (row[0],)).fetchone()
                if coverage is not None: item['resume_coverage'] = json.loads(coverage[0])
                sources.append(item)
            return {'ok': True, 'sources': sources}
        if command == "current_claim":
            key = message.get("claim_key")
            if not isinstance(key, str) or not 0 < len(key) <= 160:
                raise BrainError("Invalid current claim key.")
            normalize = lambda value: unicodedata.normalize("NFKC", value).casefold().strip()
            matches = [asdict(fact) for fact in self._prep.store.verified_claims()
                       if normalize(fact.claim_key) == normalize(key)]
            if len(matches) > 1:
                raise BrainError("Existing claim has unresolved collisions.")
            return {"ok": True, "fact": matches[0] if matches else None}
        if command == "memories":
            return self._memory_page(message)
        if command == "snapshot_begin":
            self._snapshot = export_memory_snapshot(self._prep.store)
            return {"ok": True, "size": len(self._snapshot), "sha256": sha256(self._snapshot).hexdigest()}
        if command == "snapshot_chunk":
            offset = message.get("offset")
            if self._snapshot is None or type(offset) is not int or offset < 0 or offset >= len(self._snapshot) or offset % CHUNK_BYTES:
                raise BrainError("Invalid snapshot chunk offset.")
            return {"ok": True, "offset": offset,
                    "data": base64.b64encode(self._snapshot[offset:offset+CHUNK_BYTES]).decode("ascii")}
        if command == "snapshot_end":
            self._snapshot = None
            return {"ok": True}
        raise BrainError("Unsupported profile command.")


def _read_exact(stream, size: int) -> bytes:
    parts = bytearray()
    while len(parts) < size:
        part = stream.read(size - len(parts))
        if not part:
            raise EOFError
        parts.extend(part)
    return bytes(parts)


def main() -> int:
    bridge = ProfileBridge()
    try:
        while header := sys.stdin.buffer.read(4):
            if len(header) != 4:
                return 2
            size, = struct.unpack(">I", header)
            if not 0 < size <= MAX_FRAME_BYTES:
                return 2
            try:
                def unique_pairs(pairs):
                    result = {}
                    for key, value in pairs:
                        if key in result:
                            raise ValueError("Duplicate field.")
                        result[key] = value
                    return result
                message = json.loads(_read_exact(sys.stdin.buffer, size), object_pairs_hook=unique_pairs)
                response = bridge.handle(message)
            except EOFError:
                return 2
            except Exception:
                response = {"ok": False, "error": "profile_request_rejected"}
            encoded = json.dumps(response, ensure_ascii=False, allow_nan=False).encode()
            if len(encoded) > MAX_FRAME_BYTES:
                return 2
            sys.stdout.buffer.write(struct.pack(">I", len(encoded)) + encoded)
            sys.stdout.buffer.flush()
        return 0
    finally:
        bridge.close()


if __name__ == "__main__":
    raise SystemExit(main())
