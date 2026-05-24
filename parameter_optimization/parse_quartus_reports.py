import argparse
import json
import re
from pathlib import Path


REPORT_SUFFIXES = {".rpt", ".summary", ".sta", ".fit", ".map", ".txt", ".log"}


def read_reports(path):
    path = Path(path)
    if not path.exists():
        return "", []

    if path.is_file():
        return path.read_text(encoding="utf-8", errors="ignore"), [path]

    files = [
        candidate for candidate in path.rglob("*")
        if candidate.is_file() and candidate.suffix.lower() in REPORT_SUFFIXES
    ]
    chunks = []
    for report_file in files:
        try:
            chunks.append(report_file.read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            continue
    return "\n".join(chunks), files


def as_number(value):
    if value is None:
        return None
    try:
        number = float(str(value).replace(",", "").replace("%", ""))
    except ValueError:
        return None
    if number.is_integer():
        return int(number)
    return number


def first_match(text, patterns, group=1):
    for pattern in patterns:
        regex_match = re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE)
        if regex_match:
            return regex_match.group(group).strip()
    return None


def resource_triple(text, patterns):
    for pattern in patterns:
        regex_match = re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE)
        if regex_match:
            return {
                "used": as_number(regex_match.group(1)),
                "total": as_number(regex_match.group(2)),
                "pct": as_number(regex_match.group(3)),
            }
    return {"used": None, "total": None, "pct": None}


def max_mhz_from_fmax_tables(text):
    values = []
    for regex_match in re.finditer(r";\s*([0-9]+(?:\.[0-9]+)?)\s*MHz\s*;\s*([0-9]+(?:\.[0-9]+)?)\s*MHz\s*;\s*clk\s*;", text, flags=re.IGNORECASE):
        values.append(float(regex_match.group(1)))
    if values:
        return max(values)

    values = [float(match.group(1)) for match in re.finditer(r"Fmax[^0-9]+([0-9]+(?:\.[0-9]+)?)\s*MHz", text, flags=re.IGNORECASE)]
    return max(values) if values else None


def parse_quartus_reports(reports_dir):
    reports_dir = Path(reports_dir)
    text, files = read_reports(reports_dir)
    warnings = []

    if not text:
        warnings.append(f"nenhum relatorio encontrado em {reports_dir}")

    flow_status = first_match(text, [r";\s*Flow Status\s*;\s*([^;\n]+?)\s*;", r"Flow Status\s*:\s*(.+)"])
    top_entity = first_match(text, [r";\s*Top-level Entity Name\s*;\s*([^;\n]+?)\s*;", r"Top-level Entity Name\s*:\s*(.+)"])
    device = first_match(text, [r";\s*Device\s*;\s*([^;\n]+?)\s*;", r"Device\s*:\s*([A-Z0-9]+)"])
    quartus_version = first_match(text, [r";\s*Quartus Prime Version\s*;\s*([^;\n]+?)\s*;", r"Quartus Prime Version\s+([0-9][^\n]+)", r"Version\s+([0-9][^\n]+)"])

    alms = resource_triple(text, [
        r"Logic utilization \(in ALMs\)\s*;?\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)",
        r"Total ALMs\s*:\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)",
    ])
    pins = resource_triple(text, [r"Total pins\s*;?\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)"])
    dsps = resource_triple(text, [r"Total DSP Blocks\s*;?\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)"])
    memory = resource_triple(text, [r"Total block memory bits\s*;?\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)"])

    aluts = as_number(first_match(text, [r"Combinational ALUTs\s*;?\s*([0-9,]+)", r"Total combinational functions\s*;?\s*([0-9,]+)"]))
    registers = as_number(first_match(text, [r"Total registers\s*;?\s*([0-9,]+)", r"Dedicated logic registers\s*;?\s*([0-9,]+)"]))

    max_fanout = as_number(first_match(text, [r"Maximum Fan-Out\s*;?\s*([0-9.]+)", r"Max fanout\s*[:;]\s*([0-9.]+)"]))
    avg_fanout = as_number(first_match(text, [r"Average Fan-Out\s*;?\s*([0-9.]+)", r"Avg fanout\s*[:;]\s*([0-9.]+)"]))

    parsed = {
        "flow_status": flow_status,
        "alms": alms["used"],
        "alms_total": alms["total"],
        "alms_pct": alms["pct"],
        "aluts": aluts,
        "registers": registers,
        "pins": pins["used"],
        "pins_total": pins["total"],
        "pins_pct": pins["pct"],
        "dsps": dsps["used"],
        "dsps_total": dsps["total"],
        "dsps_pct": dsps["pct"],
        "block_memory_bits": memory["used"],
        "block_memory_bits_total": memory["total"],
        "block_memory_bits_pct": memory["pct"],
        "fmax_mhz": max_mhz_from_fmax_tables(text),
        "max_fanout": max_fanout,
        "avg_fanout": avg_fanout,
        "top_entity": top_entity,
        "device": device,
        "quartus_version": quartus_version,
        "report_files": [str(path) for path in files],
        "warnings": warnings,
    }

    required = [
        "flow_status",
        "alms",
        "pins",
        "dsps",
        "block_memory_bits",
        "fmax_mhz",
    ]
    for key in required:
        if parsed.get(key) is None:
            warnings.append(f"campo nao encontrado: {key}")

    return parsed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reports-dir", type=Path)
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--output", type=Path)
    parsed_args = parser.parse_args()

    reports_dir = parsed_args.reports_dir
    if reports_dir is None:
        if parsed_args.run_dir is None:
            raise SystemExit("Use --reports-dir ou --run-dir.")
        reports_dir = parsed_args.run_dir

    parsed = parse_quartus_reports(reports_dir)

    output = parsed_args.output
    if output is None:
        if parsed_args.run_dir is not None:
            output = parsed_args.run_dir / "parsed_quartus.json"
        else:
            output = Path("parsed_quartus.json")

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(parsed, indent=2, ensure_ascii=False), encoding="utf-8")
    if parsed["warnings"]:
        for warning in parsed["warnings"]:
            print(f"WARNING: {warning}")
    print(f"parsed_quartus.json: {output}")


if __name__ == "__main__":
    main()
