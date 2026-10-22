"""Verify a probe_v3_uart.ps1 journal without claiming a board acceptance pass."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

QUERIES = (
    "STATUS CACHE FAULT LEVEL INTEGRITY PRESENTATION RECOVERY RETRIES REJECTED "
    "BADERROR BADID IDLOW IDHIGH WAVFALLBACK VUNDERFLOW UNDERFLOW OVERFLOW "
    "EVENTDROP UARTREJECT UARTFRAME UARTOVERRUN UARTDROP"
).split()
FRAME = re.compile(rb"\$([^$\r\n]*)\*([0-9A-F]{2})\r\n")
ACK = re.compile(r"C:ACK=([0-9A-F]{2}),([0-9A-F]{8})")
EVT = re.compile(r"C:EVT=([0-9A-F]{2}),([0-9A-F]{2}),([0-9A-F]{8})")
STATES = "IDLE INIT MBR BPB SCAN INDEX PICK READY STREAM SWAP ERROR INITR REJECT CLEAN".split()


def checksum(body: bytes) -> int:
    result = 0
    for byte in body:
        result ^= byte
    return result


def frames(raw: bytes) -> list[dict]:
    result = []
    for match in FRAME.finditer(raw):
        body, expected = match.groups()
        item = {"offset": match.start(), "end": match.end(),
                "body": body.decode("ascii", errors="replace"),
                "checksum_ok": checksum(body) == int(expected, 16)}
        result.append(item)
    return result


def analyze(capture: Path, expected_identity: int = 0x26101714) -> dict:
    journal = capture / "capture.jsonl"
    records = [json.loads(line) for line in journal.read_text(encoding="utf-8-sig").splitlines() if line]
    raw = (capture / "rx.bin").read_bytes()
    errors, values, transactions, events = [], {}, [], []
    joined = b"".join(bytes.fromhex(r["hex"]) for r in records if r["kind"] == "rx")
    if joined != raw:
        errors.append("rx.bin does not match the RX journal")
    pending = None
    receive = bytearray()
    for record in records:
        kind = record["kind"]
        if kind == "tx":
            if pending is not None:
                errors.append("a new query was sent before the previous one completed")
            pending = record
            receive.clear()
            sent = bytes.fromhex(record["hex"])
            parsed = frames(sent)
            wanted_body = "B:" + record["query"] + "?"
            if re.fullmatch(r"DIAG[0-9]{2}", record["query"]):
                wanted_body = "B:DIAG=" + str(int(record["query"][4:]))
            if (len(parsed) != 1 or not parsed[0]["checksum_ok"] or
                    parsed[0]["end"] != len(sent) or parsed[0]["offset"] != 0 or
                    parsed[0]["body"] != wanted_body):
                errors.append("invalid or non-query TX frame")
        elif kind == "rx":
            receive.extend(bytes.fromhex(record["hex"]))
        elif kind == "ack":
            found = [f for f in frames(bytes(receive)) if f["checksum_ok"] and ACK.fullmatch(f["body"])]
            if pending is None or record["query"] != pending["query"] or len(found) != 1:
                errors.append("ACK is missing, duplicated, or cannot be assigned to one outstanding query")
                continue
            match = ACK.fullmatch(found[0]["body"])
            assert match is not None
            if record["frame"] != "$" + found[0]["body"] + f"*{checksum(found[0]['body'].encode()):02X}":
                errors.append("ACK journal entry does not match actual received bytes")
            code, value = (int(x, 16) for x in match.groups())
            name = pending["query"]
            transactions.append({"query": name, "reply_code": code, "value": value,
                                 "hex": f"{value:08X}", "sent_ms": pending["elapsed_ms"],
                                 "received_ms": record["elapsed_ms"]})
            if code != 0:
                errors.append(f"{name}: board rejected query with ACK code {code:02X}")
            else:
                values[name] = value
            pending = None
    parsed = frames(raw)
    cursor = 0
    unframed = bytearray()
    for frame in parsed:
        unframed.extend(raw[cursor:frame["offset"]])
        cursor = frame["end"]
        if not frame["checksum_ok"]:
            errors.append(f"bad RX checksum at offset {frame['offset']}")
        match = EVT.fullmatch(frame["body"])
        if match and frame["checksum_ok"]:
            source, code, timestamp = (int(x, 16) for x in match.groups())
            events.append({"source": source, "code": code, "timestamp_ms": timestamp})
        elif not ACK.fullmatch(frame["body"]):
            errors.append(f"unrecognized RX frame at offset {frame['offset']}")
    unframed.extend(raw[cursor:])
    fatal_signature = b"FATAL SYSPLL\r\n"
    fatal_reports = bytes(unframed).count(fatal_signature)
    unknown = bytes(unframed).replace(fatal_signature, b"")
    if unknown:
        errors.append("RX includes unframed bytes; inspect rx.bin (wrong baud/firmware or damaged stream possible)")
    if pending is not None:
        errors.append(f"{pending['query']}: query did not complete")
    expected_queries = QUERIES.copy()
    if any(r["kind"] == "tx" and r["query"].startswith("DIAG") for r in records):
        expected_queries += [f"DIAG{i:02d}" for i in range(16)]
    if [t["query"] for t in transactions] != expected_queries:
        errors.append("the full ordered read-only query set did not complete")
    if "DIAG00" in values and values["DIAG00"] != expected_identity:
        errors.append("unexpected reported diagnostic build ID")
    closed = [r for r in records if r["kind"] == "closed"]
    if len(closed) != 1 or closed[0]["exit_code"] != 0:
        errors.append("capture did not close successfully")
    notes = []
    if fatal_reports:
        notes.append("Observed FATAL SYSPLL text from the independent REF-clock reporter; SYS-domain query replies may be unavailable.")
    if "STATUS" in values:
        state = values["STATUS"]
        notes.append("Player state: " + (STATES[state] if state < len(STATES) else f"unknown {state:X}"))
    if "CACHE" in values:
        notes.append(f"Resident cache mask: {values['CACHE']:X}; F is required for all four slots.")
    if values.get("INTEGRITY", 0):
        notes.append("A real memory/display integrity flag is set. This alone does not identify a clock phase or wiring cause.")
    if values.get("REJECTED", 0):
        notes.append(f"Rejected BMP candidates: {values['REJECTED']}; BADERROR/BADID describe only the latest rejection.")
    if values.get("RECOVERY") == 5:
        notes.append("Recovery is locked after bounded attempts; capture the evidence before a global reset.")
    if values.get("FAULT", 0):
        notes.append(f"Latched fault {values['FAULT']:02X}, level {values.get('LEVEL', -1)}. Correlate event source and player state.")
    return {"capture_complete": not errors, "hardware_acceptance_passed": False,
            "firmware_identity_proven": False, "github_upload_performed": False,
            "expected_self_reported_id": f"{expected_identity:08X}",
            "self_reported_id_matches_expected": values.get("DIAG00") == expected_identity if "DIAG00" in values else None,
            "rx_bytes": len(raw), "rx_sha256": hashlib.sha256(raw).hexdigest(),
            "fatal_syspll_reports": fatal_reports, "unframed_preview_hex": bytes(unframed[:256]).hex(),
            "unframed_preview_text": bytes(unframed[:256]).decode("ascii", errors="replace"),
            "queries_are_sequential_not_atomic": True, "values": values,
            "transactions": transactions, "events": events, "errors": errors, "notes": notes}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-id", type=lambda value: int(value, 0), default=0x26101714,
                        help="expected self-reported hexadecimal ID, e.g. 0x26101717; archived default is 0x26101714")
    args = parser.parse_args()
    if not 0 <= args.expected_id <= 0xFFFFFFFF:
        parser.error("--expected-id must fit32 bits")
    protected = {(args.capture / name).resolve() for name in ("capture.jsonl", "rx.bin")}
    if args.output.resolve() in protected:
        parser.error("the report must not overwrite raw capture evidence")
    result = analyze(args.capture, expected_identity=args.expected_id)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result["capture_complete"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
