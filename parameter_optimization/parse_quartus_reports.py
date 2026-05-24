"""Extract Quartus resource/timing fields from a report directory.

The parser is intentionally tolerant: Quartus report formatting changes between
versions and editions, so missing fields become null and a warning is recorded.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


FIELDS = [
    "flow_status",
    "alms",
    "alms_total",
    "alms_pct",
    "aluts",
    "registers",
    "pins",
    "pins_total",
    "pins_pct",
    "dsps",
    "dsps_total",
    "dsps_pct",
    "block_memory_bits",
    "block_memory_bits_total",
    "block_memory_bits_pct",
    "fmax_mhz",
    "max_fanout",
    "avg_fanout",
    "top_entity",
    "device",
    "quartus_version",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Parse Quartus .rpt/.summary files into JSON.")
    parser.add_argument(
        "--reports-dir",
        type=Path,
        required=True,
        help="Directory containing Quartus output reports, usually output_files/.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="JSON file to write.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    parsed = parse_reports(args.reports_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(parsed, indent=2), encoding="utf-8")
    print(f"Parsed Quartus reports: {args.output}")


def parse_reports(reports_dir: Path) -> dict[str, Any]:
    files = find_report_files(reports_dir)
    text_by_name = {str(path): path.read_text(encoding="utf-8", errors="ignore") for path in files}
    text = "\n".join(text_by_name.values())
    warnings: list[str] = []

    result: dict[str, Any] = {field: None for field in FIELDS}
    result["reports_dir"] = str(reports_dir)
    result["report_files"] = [str(path) for path in files]

    if not files:
        warnings.append(f"No Quartus reports found in {reports_dir}")

    result["flow_status"] = first_match(
        text,
        [
            r"Flow\s+Status\s*:\s*([^\n\r]+)",
            r"Flow\s+Summary.*?Status\s*:\s*([^\n\r]+)",
        ],
    )
    result["top_entity"] = first_match(
        text,
        [
            r"Top[-\s]*level\s+entity\s+name\s*:\s*([A-Za-z0-9_]+)",
            r"Top\s+Entity\s*:\s*([A-Za-z0-9_]+)",
            r"TOP_LEVEL_ENTITY\s+([A-Za-z0-9_]+)",
        ],
    )
    result["device"] = first_match(
        text,
        [
            r"Device\s*:\s*([A-Za-z0-9_]+)",
            r"Part\s+Name\s*:\s*([A-Za-z0-9_]+)",
            r"\b5C[A-Z0-9]+\b",
        ],
    )
    result["quartus_version"] = first_match(
        text,
        [
            r"Quartus(?:\s+Prime)?\s+Version\s*:\s*([^\n\r]+)",
            r"Version\s+([0-9][^\n\r]*Quartus[^\n\r]*)",
            r"Quartus(?:\s+Prime)?\s+([0-9][^\n\r]+)",
        ],
    )

    apply_resource(result, text, "alms", ["total alms", "adaptive logic modules", "logic utilization (in alms)"])
    apply_resource(result, text, "pins", ["total pins", "pins"])
    apply_resource(result, text, "dsps", ["total dsp blocks", "variable precision dsp blocks", "dsp blocks", "dsp block"])
    apply_resource(
        result,
        text,
        "block_memory_bits",
        ["total block memory bits", "block memory bits", "memory bits"],
    )

    result["aluts"] = find_single_number(
        text,
        ["combinational aluts", "total combinational functions", "combinational functions"],
    )
    result["registers"] = find_single_number(
        text,
        ["dedicated logic registers", "total registers", "registers"],
    )
    result["fmax_mhz"] = find_fmax(text_by_name)
    result["max_fanout"] = find_single_number(text, ["maximum fan-out", "max fanout", "max fan-out"])
    result["avg_fanout"] = find_single_number(text, ["average fan-out", "avg fanout", "avg fan-out"])

    for field in FIELDS:
        if result.get(field) is None:
            warnings.append(f"Field not found: {field}")

    result["warnings"] = warnings
    return result


def find_report_files(reports_dir: Path) -> list[Path]:
    if not reports_dir.exists():
        return []
    suffixes = {".rpt", ".summary", ".sta", ".fit", ".map"}
    return sorted(path for path in reports_dir.rglob("*") if path.is_file() and path.suffix.lower() in suffixes)


def first_match(text: str, patterns: list[str]) -> str | None:
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE | re.DOTALL | re.MULTILINE)
        if match:
            if match.lastindex:
                return clean_text(match.group(1))
            return clean_text(match.group(0))
    return None


def clean_text(value: str) -> str:
    return value.strip().strip(";").strip()


def parse_number(value: str) -> float | int | None:
    cleaned = value.strip().replace(",", "").replace("%", "").replace("<", "").replace("~", "")
    if not cleaned:
        return None
    try:
        number = float(cleaned)
    except ValueError:
        return None
    if number.is_integer():
        return int(number)
    return number


def number_tokens(line: str) -> list[str]:
    return re.findall(r"[<~]?\d[\d,]*(?:\.\d+)?\s*%?", line)


def line_has_label(line: str, label: str) -> bool:
    normalized_line = normalize_label(line)
    normalized_label = normalize_label(label)
    return normalized_label in normalized_line


def normalize_label(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace(";", " ").replace(":", " ").lower()).strip()


def find_resource_line(text: str, labels: list[str]) -> tuple[float | int | None, float | int | None, float | int | None] | None:
    for line in text.splitlines():
        for label in labels:
            if not line_has_label(line, label):
                continue

            tokens = number_tokens(line)
            pct_match = re.search(r"([0-9]+(?:\.[0-9]+)?)\s*%", line)
            if len(tokens) >= 2:
                used = parse_number(tokens[0])
                total = parse_number(tokens[1])
                pct = parse_number(pct_match.group(1)) if pct_match else None
                if pct is None and len(tokens) >= 3:
                    pct = parse_number(tokens[2])
                return used, total, pct
    return None


def apply_resource(result: dict[str, Any], text: str, field_prefix: str, labels: list[str]) -> None:
    values = find_resource_line(text, labels)
    if values is None:
        result[field_prefix] = None
        result[f"{field_prefix}_total"] = None
        result[f"{field_prefix}_pct"] = None
        return

    result[field_prefix], result[f"{field_prefix}_total"], result[f"{field_prefix}_pct"] = values


def find_single_number(text: str, labels: list[str]) -> float | int | None:
    for line in text.splitlines():
        for label in labels:
            if not line_has_label(line, label):
                continue
            tokens = number_tokens(line)
            if tokens:
                return parse_number(tokens[0])
    return None


def find_fmax(text_by_name: dict[str, str]) -> float | None:
    candidates: list[float] = []
    preferred_text = "\n".join(
        text for name, text in text_by_name.items() if name.lower().endswith((".sta.rpt", ".sta.summary"))
    )
    search_text = preferred_text or "\n".join(text_by_name.values())

    for line in search_text.splitlines():
        if "mhz" not in line.lower():
            continue
        for match in re.finditer(r"([0-9]+(?:\.[0-9]+)?)\s*MHz", line, re.IGNORECASE):
            candidates.append(float(match.group(1)))

    if not candidates:
        return None
    return max(candidates)


if __name__ == "__main__":
    main()
