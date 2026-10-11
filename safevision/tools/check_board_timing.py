#!/usr/bin/env python3
"""Fail-closed TD routed-STA gate; outputs an auditable JSON in the run folder.

The experimental exception classifies only reported SDRAM-boundary setup paths.
It does not prove SDRAM AC correctness, identify a vendor defect, or close STA.
"""
import argparse
import hashlib
import json
import math
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

NUMBER = r"[-+]?\d+(?:\.\d+)?"
PATH_RE = re.compile(
    rf"^Slack\s*:\s*({NUMBER})ns\s*\n"
    r"Begin Point\s*:\s*(.*?)\nEnd Point\s*:\s*(.*?)\n"
    r"Check Type\s*:\s*(\S+)", re.MULTILINE)
# Match this actual hierarchy, including synthesized boundary cells. A substring
# such as core/fake_memory_ip/sdram is deliberately not eligible.
SDRAM_POINT = re.compile(r"^memory_ip/sdram(?:[./\[]|_syn_\d+(?:[./\[]|$))")
HEALTH_REQUIRED = (
    "no clock", "invalid constraint", "pll/clock buffer clock constraints",
    "combinational loops", "soft fifo timing exception constraints",
    "no path constraints", "shadowed/ignored timing exception constraints",
)


def read_report(path):
    raw = path.read_bytes()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return raw.decode("utf-16")
    return raw.decode("utf-8-sig", errors="strict")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def point_name(value):
    return value.strip().split(" (", 1)[0]


def one_number(text, expression, label, errors):
    found = re.findall(expression, text, re.MULTILINE)
    if len(found) != 1:
        errors.append(f"Missing or ambiguous {label} ({len(found)} matches)")
        return None
    value = float(found[0])
    if not math.isfinite(value):
        errors.append(f"Non-finite {label}")
        return None
    return value


def assess(timing, check, experimental=False, unclosed_bound=0.0):
    errors = []
    if not re.search(r"^Confidence\s*:\s*Routed\s*$", timing, re.MULTILINE):
        errors.append("Report is not final routed timing")
    if not re.search(r"^Check Corner\s*:\s*Both \(Slow and Fast\)\s*$", timing, re.MULTILINE):
        errors.append("Both slow and fast corners were not reported")
    for corner in ("Slow", "Fast"):
        if not re.search(rf"^{corner}\s*\|\s*yes\s+yes\s*$", timing, re.MULTILINE):
            errors.append(f"Missing {corner} max/min check")
    setup = one_number(timing, rf"^\s*SWNS:\s*({NUMBER})ns,", "global SWNS", errors)
    hold = one_number(timing, rf"^\s*HWNS:\s*({NUMBER})ns,", "global HWNS", errors)
    setup_tns = one_number(timing, rf"^\s*SWNS:\s*{NUMBER}ns,\s*STNS:\s*({NUMBER})ns", "global STNS", errors)
    hold_tns = one_number(timing, rf"^\s*HWNS:\s*{NUMBER}ns,\s*HTNS:\s*({NUMBER})ns", "global HTNS", errors)
    period = one_number(timing, rf"^\s*Period Check WNS:\s*({NUMBER})ns", "period WNS", errors)
    health = {}
    for name, count in re.findall(r"^\d+\. checking (.*?)\((\d+)\) \((?:HIGH|MEDIUM)\)\s*$", check, re.MULTILINE):
        if name in health:
            errors.append(f"Duplicate health count: {name}")
        health[name] = int(count)
    for name in HEALTH_REQUIRED:
        if name not in health:
            errors.append(f"Missing health check: {name}")
        elif health[name] != 0:
            errors.append(f"Health check {name} = {health[name]}")
    # Check detailed diagnostics too, so disagreement with the table of
    # contents fails closed instead of concealing a PLL/constraint problem.
    health_details = (
        ("invalid constraints", r"invalid constraints?"),
        ("combinational loops", r"combinational loops?"),
        ("clock pins without constraints", r"clock pins? that (?:have|has) no clock constraints"),
        ("PLL frequency mismatch", r"clocks? whose clock frequency (?:do|does) not match the PLL setting"),
    )
    for description, expression in health_details:
        counts = re.findall(rf"There (?:are|is) (\d+) {expression}\.", check)
        if not counts:
            errors.append(f"Missing health detail: {description}")
        elif any(int(value) != 0 for value in counts):
            errors.append(f"Nonzero health detail: {description} = {','.join(counts)}")
    # Local/standalone PLL clocks are reported separately by TD. They are not
    # silently reclassified as PLL-frequency errors; reject real ambiguity.
    for description in ("leaf clock pins driven by multiple clocks",
                        "clocks created on internal clock network",
                        "unexpandable clock sets"):
        found = re.search(rf"There are (\d+) {re.escape(description)}\.", check)
        if not found:
            errors.append(f"Missing clock definition detail: {description}")
        elif int(found[1]) != 0:
            errors.append(f"Clock definition {description} = {found[1]}")
    paths = []
    for match in PATH_RE.finditer(timing):
        slack, begin, end, kind = match.groups()
        begin, end = point_name(begin), point_name(end)
        paths.append({"slack_ns": float(slack), "begin": begin, "end": end,
                      "check_type": kind.lower(),
                      "sdram_boundary": bool(SDRAM_POINT.match(begin) or SDRAM_POINT.match(end)),
                      "offset": match.start()})
    if not paths:
        errors.append("No detailed timing paths were parsed")
    # A malformed path block must not disappear from classification.
    blocks = len(re.findall(r"^Slack\s*:", timing, re.MULTILINE))
    if blocks != len(paths):
        errors.append(f"Incomplete path parsing: {len(paths)}/{blocks} blocks")
    negative = [p for p in paths if p["slack_ns"] < 0]
    for p in paths:
        if p["check_type"] not in ("setup", "hold", "recovery", "removal"):
            errors.append(f"Unsupported timing check type: {p['check_type']}")
            break
    # Verify group summaries against details. This also rejects truncated
    # violation lists: every reported violating endpoint must appear in detail.
    groups = []
    sections = list(re.finditer(r"^Path Group\s*:\s*(.*?)\s*$", timing, re.MULTILINE))
    if not sections:
        errors.append("No path group summaries")
    for index, section in enumerate(sections):
        end_offset = sections[index + 1].start() if index + 1 < len(sections) else len(timing)
        text = timing[section.end():end_offset]
        group = {"name": section[1], "summaries": []}
        for direction, prefix, kinds in (("Max", "S", ("setup", "recovery")),
                                          ("Min", "H", ("hold", "removal"))):
            stat = re.search(rf"^{direction}\s*:\s*{prefix}WNS\s+({NUMBER})ns,\s*"
                             rf"{prefix}TNS\s+({NUMBER})ns,\s*(\d+) Viol Endpoints", text, re.MULTILINE)
            if not stat:
                errors.append(f"Missing {direction} summary: {section[1]}")
                continue
            wns, tns, endpoint_count = float(stat[1]), float(stat[2]), int(stat[3])
            group["summaries"].append({"direction": direction, "wns_ns": wns,
                                        "tns_ns": tns, "violating_endpoints": endpoint_count})
            detail = [p for p in paths if section.end() <= p["offset"] < end_offset
                      and p["check_type"] in kinds]
            bad = [p for p in detail if p["slack_ns"] < 0]
            if wns < 0:
                if not bad or abs(min(p["slack_ns"] for p in bad) - wns) > 0.0011:
                    errors.append(f"Unexplained negative {direction} WNS: {section[1]}")
                if len({p["end"] for p in bad}) < endpoint_count:
                    errors.append(f"Truncated negative endpoints: {section[1]} {direction}")
            elif bad or endpoint_count > 0 or tns < 0:
                errors.append(f"Inconsistent {direction} group summary: {section[1]}")
        groups.append(group)
    if setup is not None and setup < 0:
        max_bad = [p for p in negative if p["check_type"] in ("setup", "recovery")]
        if not max_bad or abs(min(p["slack_ns"] for p in max_bad) - setup) > 0.0011:
            errors.append("Global negative SWNS is not explained by detailed max paths")
    elif setup is not None:
        if any(p["check_type"] in ("setup", "recovery") for p in negative) or (setup_tns is not None and setup_tns < 0):
            errors.append("Nonnegative global SWNS disagrees with max path/TNS violations")
    if hold is not None and hold < 0:
        errors.append(f"Global hold/removal WNS is negative: {hold} ns")
    elif hold is not None and (any(p["check_type"] in ("hold", "removal") for p in negative) or (hold_tns is not None and hold_tns < 0)):
        errors.append("Nonnegative global HWNS disagrees with min path/TNS violations")
    if period is not None and period < 0:
        errors.append(f"Global period WNS is negative: {period} ns")
    # Negative paths: an SDRAM-boundary setup path may be waived by the
    # experimental switch. Everything else needs the explicit, bounded
    # unclosed-setup waiver; hold/recovery/removal are never waivable.
    unclosed_setup = []
    for p in negative:
        if experimental and p["check_type"] == "setup" and p["sdram_boundary"]:
            continue
        if (unclosed_bound > 0 and p["check_type"] == "setup"
                and abs(p["slack_ns"]) <= unclosed_bound):
            unclosed_setup.append(p)
            continue
        errors.append(f"Negative {p['check_type']} {p['slack_ns']} ns: {p['begin']} -> {p['end']}")
    if setup is not None and setup < 0 and not experimental and not unclosed_setup:
        errors.append(f"Global setup/recovery WNS is negative: {setup} ns")
    minima = {}
    for kind in ("setup", "hold", "recovery", "removal"):
        values = [p["slack_ns"] for p in paths if p["check_type"] == kind]
        user_values = [p["slack_ns"] for p in paths if p["check_type"] == kind and not p["sdram_boundary"]]
        minima[kind] = {"reported_min_ns": min(values) if values else None,
                        "non_sdram_reported_min_ns": min(user_values) if user_values else None}
    experimental_only = not errors and bool(negative)
    if errors:
        status = "FAIL"
    elif unclosed_setup:
        status = "EXPERIMENTAL_UNCLOSED"
    elif experimental_only:
        status = "EXPERIMENTAL_SDRAM_UNCLOSED"
    else:
        status = "PASS"
    return {"status": status, "gate_accepted": not errors,
            "timing_passed": not errors and not negative and setup is not None and setup >= 0,
            "experimental_requested": experimental,
            "allow_unclosed_setup_ns": unclosed_bound,
            "unclosed_setup_worst_ns": min((p["slack_ns"] for p in unclosed_setup), default=None),
            "unclosed_setup_count": len(unclosed_setup),
            "global": {"swns_ns": setup, "stns_ns": setup_tns,
                       "hwns_ns": hold, "htns_ns": hold_tns, "period_wns_ns": period},
            "health": health, "reported_path_count": len(paths),
            "negative_path_count": len(negative), "minima": minima,
            "groups": groups, "negative_paths": [{k: v for k, v in p.items() if k != "offset"} for p in negative],
            "unclosed_setup": [{k: v for k, v in p.items() if k != "offset"} for p in unclosed_setup],
            "errors": errors,
            "limitation": ("Classification covers reported final routed paths. An experimental SDRAM "
                           "boundary exception is not timing closure, SDRAM AC validation, proof of a "
                           "vendor defect, or board/HDMI acceptance.")}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timing", type=Path, required=True)
    parser.add_argument("--check", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--experimental-sdram", action="store_true")
    parser.add_argument("--allow-unclosed-setup", type=float, default=0.0,
                        help="Waive setup violations up to this magnitude (ns). Bring-up trials only; "
                             "never applies to hold/recovery/removal.")
    args = parser.parse_args(argv)
    try:
        result = assess(read_report(args.timing), read_report(args.check), args.experimental_sdram,
                        max(0.0, args.allow_unclosed_setup))
        result["reports"] = [{"path": str(p.resolve()), "sha256": digest(p)} for p in (args.timing, args.check)]
    except (OSError, UnicodeError, ValueError) as exc:
        result = {"status": "FAIL", "gate_accepted": False, "timing_passed": False,
                  "errors": [f"Cannot validate reports: {exc}"]}
    result["checked_at_utc"] = datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BOARD TIMING {result['status']}: {args.output}")
    if "global" in result:
        print(f"SWNS={result['global']['swns_ns']} ns HWNS={result['global']['hwns_ns']} ns; "
              f"reported negative paths={result['negative_path_count']}")
    for error in result["errors"][:8]:
        print(f"REJECT: {error}")
    if result["status"] == "EXPERIMENTAL_SDRAM_UNCLOSED":
        print("WARNING: SDRAM setup is unresolved. This allows an experimental candidate only; timing has NOT passed.")
    if result["status"] == "EXPERIMENTAL_UNCLOSED":
        print(f"WARNING: {result['unclosed_setup_count']} setup path(s) waived by --allow-unclosed-setup "
              f"(worst {result['unclosed_setup_worst_ns']} ns, bound {result['allow_unclosed_setup_ns']} ns). "
              "Bring-up trial only; timing has NOT passed.")
    return 0 if result["gate_accepted"] else 1


if __name__ == "__main__":
    sys.exit(main())
