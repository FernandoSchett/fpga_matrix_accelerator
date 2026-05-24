"""Collect experiment configs, Quartus JSON, simulation/host logs, and CSV metrics."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_RESULTS_DIR = SCRIPT_DIR / "results"


CSV_COLUMNS = [
    "run_id",
    "top_entity",
    "N",
    "tile_size",
    "num_macs",
    "data_width",
    "acc_width",
    "mem_type",
    "dataflow",
    "buffering_mode",
    "memory_burst_len",
    "mac_pipeline_stages",
    "memory_banks_a",
    "memory_banks_b",
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
    "exec_cycles",
    "load_cycles",
    "compute_cycles",
    "store_cycles",
    "ops_exact",
    "ops_approx_2n3",
    "exec_time_us",
    "gops_eff_exact",
    "gops_eff_approx",
    "gops_peak",
    "peak_efficiency",
    "max_fanout",
    "avg_fanout",
    "validation_passed",
    "num_errors",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Collect all experiment run folders into metrics JSON and a CSV.")
    parser.add_argument(
        "--runs-dir",
        type=Path,
        default=DEFAULT_RESULTS_DIR / "runs",
        help="Directory containing per-run folders.",
    )
    parser.add_argument(
        "--output-csv",
        type=Path,
        default=DEFAULT_RESULTS_DIR / "experiment_results.csv",
        help="CSV output path.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rows, summary = collect(args.runs_dir)
    args.output_csv.parent.mkdir(parents=True, exist_ok=True)

    with args.output_csv.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow({column: csv_value(row.get(column)) for column in CSV_COLUMNS})

    summary["csv_path"] = str(args.output_csv)
    summary_path = args.output_csv.parent / "experiment_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print_summary(summary, args.output_csv)


def collect(runs_dir: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    run_dirs = sorted(path for path in runs_dir.glob("*") if path.is_dir())

    for run_dir in run_dirs:
        config_path = run_dir / "config.json"
        if not config_path.exists():
            continue

        config = load_json(config_path)
        parsed_quartus = load_json(run_dir / "parsed_quartus.json")
        validation = find_validation(run_dir)
        log_values = parse_logs(run_dir)

        row = build_row(run_dir, config, parsed_quartus, validation, log_values)
        warnings = build_run_warnings(row, parsed_quartus)
        row["warnings"] = warnings

        metrics_path = run_dir / "metrics.json"
        metrics_path.write_text(json.dumps(row, indent=2), encoding="utf-8")
        rows.append(row)

    apply_cross_run_warnings(rows)
    for row in rows:
        metrics_path = Path(row["_run_dir"]) / "metrics.json"
        metrics_path.write_text(json.dumps(row, indent=2), encoding="utf-8")

    summary = build_summary(rows)
    return rows, summary


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError:
        return {"warnings": [f"Invalid JSON: {path}"]}
    return data if isinstance(data, dict) else {}


def find_validation(run_dir: Path) -> dict[str, Any]:
    candidates = list(run_dir.rglob("validation.json"))
    if not candidates:
        return {}
    return load_json(candidates[0])


def parse_logs(run_dir: Path) -> dict[str, Any]:
    values: dict[str, Any] = {
        "exec_cycles": None,
        "load_cycles": None,
        "compute_cycles": None,
        "store_cycles": None,
    }
    texts: list[str] = []
    for directory_name in ["simulation_logs", "host_logs"]:
        directory = run_dir / directory_name
        if directory.exists():
            for path in directory.rglob("*"):
                if path.is_file() and path.suffix.lower() in {".log", ".txt", ".transcript"}:
                    texts.append(path.read_text(encoding="utf-8", errors="ignore"))

    full_text = "\n".join(texts)
    cycles = [int(value) for value in re.findall(r"Ciclos\s+de\s+execucao:\s*([0-9]+)", full_text, re.IGNORECASE)]
    if cycles:
        # If a testbench prints several small tests, the largest is the closest whole-run cycle count.
        values["exec_cycles"] = max(cycles)

    values["load_cycles"] = first_int(full_text, [r"load_cycles\s*[:=]\s*([0-9]+)", r"perf_load_cycles\s*[:=]\s*([0-9]+)"])
    values["compute_cycles"] = first_int(
        full_text, [r"compute_cycles\s*[:=]\s*([0-9]+)", r"perf_compute_cycles\s*[:=]\s*([0-9]+)"]
    )
    values["store_cycles"] = first_int(full_text, [r"store_cycles\s*[:=]\s*([0-9]+)", r"perf_store_cycles\s*[:=]\s*([0-9]+)"])
    return values


def first_int(text: str, patterns: list[str]) -> int | None:
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return int(match.group(1))
    return None


def build_row(
    run_dir: Path,
    config: dict[str, Any],
    parsed: dict[str, Any],
    validation: dict[str, Any],
    log_values: dict[str, Any],
) -> dict[str, Any]:
    n = number_or_none(config.get("N"))
    tile_size = number_or_none(config.get("tile_size"))
    num_macs = number_or_none(config.get("num_macs"))
    fmax_mhz = number_or_none(parsed.get("fmax_mhz"))
    exec_cycles = log_values.get("exec_cycles")

    simulation_n = number_or_none(config.get("simulation_n"))
    if simulation_n is not None and n is not None and simulation_n != n:
        exec_cycles = None

    ops_exact = n**3 + n**2 * (n - 1) if n is not None else None
    ops_approx = 2 * n**3 if n is not None else None
    exec_time_us = None
    gops_eff_exact = None
    gops_eff_approx = None
    gops_peak = None
    peak_efficiency = None

    if exec_cycles and fmax_mhz and fmax_mhz > 0:
        exec_time_s = exec_cycles / (fmax_mhz * 1_000_000)
        exec_time_us = exec_time_s * 1_000_000
        if ops_exact is not None:
            gops_eff_exact = ops_exact / exec_time_s / 1_000_000_000
        if ops_approx is not None:
            gops_eff_approx = ops_approx / exec_time_s / 1_000_000_000
        if num_macs:
            gops_peak = 2 * num_macs * fmax_mhz / 1000
            if gops_peak:
                peak_efficiency = gops_eff_approx / gops_peak if gops_eff_approx is not None else None

    return {
        "_run_dir": str(run_dir),
        "run_id": config.get("run_id", run_dir.name),
        "top_entity": parsed.get("top_entity") or config.get("top_entity"),
        "N": n,
        "tile_size": tile_size,
        "num_macs": num_macs,
        "data_width": number_or_none(config.get("data_width")),
        "acc_width": number_or_none(config.get("acc_width")),
        "mem_type": config.get("mem_type"),
        "dataflow": config.get("dataflow"),
        "buffering_mode": config.get("buffering_mode"),
        "memory_burst_len": config.get("memory_burst_len"),
        "mac_pipeline_stages": config.get("mac_pipeline_stages"),
        "memory_banks_a": config.get("memory_banks_a"),
        "memory_banks_b": config.get("memory_banks_b"),
        "flow_status": parsed.get("flow_status"),
        "alms": parsed.get("alms"),
        "alms_total": parsed.get("alms_total"),
        "alms_pct": parsed.get("alms_pct"),
        "aluts": parsed.get("aluts"),
        "registers": parsed.get("registers"),
        "pins": parsed.get("pins"),
        "pins_total": parsed.get("pins_total"),
        "pins_pct": parsed.get("pins_pct"),
        "dsps": parsed.get("dsps"),
        "dsps_total": parsed.get("dsps_total"),
        "dsps_pct": parsed.get("dsps_pct"),
        "block_memory_bits": parsed.get("block_memory_bits"),
        "block_memory_bits_total": parsed.get("block_memory_bits_total"),
        "block_memory_bits_pct": parsed.get("block_memory_bits_pct"),
        "fmax_mhz": fmax_mhz,
        "exec_cycles": exec_cycles,
        "load_cycles": log_values.get("load_cycles"),
        "compute_cycles": log_values.get("compute_cycles"),
        "store_cycles": log_values.get("store_cycles"),
        "ops_exact": ops_exact,
        "ops_approx_2n3": ops_approx,
        "exec_time_us": exec_time_us,
        "gops_eff_exact": gops_eff_exact,
        "gops_eff_approx": gops_eff_approx,
        "gops_peak": gops_peak,
        "peak_efficiency": peak_efficiency,
        "max_fanout": parsed.get("max_fanout"),
        "avg_fanout": parsed.get("avg_fanout"),
        "validation_passed": validation.get("passed"),
        "num_errors": validation.get("num_errors"),
        "quartus_warnings": parsed.get("warnings", []),
    }


def number_or_none(value: Any) -> int | float | None:
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return value
    try:
        number = float(str(value))
    except ValueError:
        return None
    if number.is_integer():
        return int(number)
    return number


def build_run_warnings(row: dict[str, Any], parsed: dict[str, Any]) -> list[str]:
    warnings = list(parsed.get("warnings", []))
    flow_status = str(row.get("flow_status") or "").lower()
    if flow_status and "success" not in flow_status:
        warnings.append("flow_status is not Successful")
    if not flow_status:
        warnings.append("flow_status is missing")
    if row.get("fmax_mhz") is None:
        warnings.append("fmax_mhz is missing")
    if row.get("exec_cycles") is None:
        warnings.append("exec_cycles is missing")
    if row.get("block_memory_bits") == 0:
        warnings.append("block_memory_bits is zero")
    if row.get("peak_efficiency") is not None and row["peak_efficiency"] > 1.05:
        warnings.append("peak_efficiency is greater than 1.05")
    if row.get("validation_passed") is False:
        warnings.append("validation_passed is false")
    if row.get("num_errors") not in (None, 0):
        warnings.append("num_errors is greater than zero")
    return warnings


def apply_cross_run_warnings(rows: list[dict[str, Any]]) -> None:
    grouped: dict[Any, list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault(row.get("tile_size"), []).append(row)

    for tile_size, group in grouped.items():
        previous: dict[str, Any] | None = None
        for row in sorted(group, key=lambda item: item.get("num_macs") or 0):
            if previous is not None:
                if row.get("dsps") is not None and previous.get("dsps") is not None:
                    if row["num_macs"] > previous["num_macs"] and row["dsps"] <= previous["dsps"]:
                        row.setdefault("warnings", []).append(
                            f"dsps did not increase from NUM_MACS={previous['num_macs']} to NUM_MACS={row['num_macs']} for TILE_SIZE={tile_size}"
                        )
            previous = row


def build_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    successful = [row for row in rows if not row.get("warnings")]
    errored = [row for row in rows if row.get("warnings")]
    return {
        "total_runs": len(rows),
        "successful_runs": len(successful),
        "error_or_warning_runs": len(errored),
        "best_gops_eff_exact": best_row(rows, "gops_eff_exact"),
        "best_gops_eff_approx": best_row(rows, "gops_eff_approx"),
        "best_peak_efficiency": best_row(rows, "peak_efficiency"),
    }


def best_row(rows: list[dict[str, Any]], metric: str) -> dict[str, Any] | None:
    candidates = [row for row in rows if row.get(metric) is not None]
    if not candidates:
        return None
    row = max(candidates, key=lambda item: item[metric])
    return {
        "run_id": row.get("run_id"),
        "tile_size": row.get("tile_size"),
        "num_macs": row.get("num_macs"),
        metric: row.get(metric),
    }


def print_summary(summary: dict[str, Any], csv_path: Path) -> None:
    print("")
    print(f"Total de runs: {summary['total_runs']}")
    print(f"Runs bem-sucedidos: {summary['successful_runs']}")
    print(f"Runs com erro/warning: {summary['error_or_warning_runs']}")
    print(f"Melhor por gops_eff_exact: {format_best(summary['best_gops_eff_exact'])}")
    print(f"Melhor por gops_eff_approx: {format_best(summary['best_gops_eff_approx'])}")
    print(f"Melhor por peak_efficiency: {format_best(summary['best_peak_efficiency'])}")
    print(f"CSV final: {csv_path}")


def format_best(value: dict[str, Any] | None) -> str:
    if value is None:
        return "NA"
    return json.dumps(value, ensure_ascii=False)


def csv_value(value: Any) -> Any:
    if value is None:
        return ""
    return value


if __name__ == "__main__":
    main()
