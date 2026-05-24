import argparse
import csv
import json
import math
import re
from datetime import datetime
from pathlib import Path


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
    "fmax_ratio_to_best",
    "gops_per_alm",
    "gops_per_dsp",
    "gops_per_block_memory_mbit",
    "alms_per_mac",
    "dsps_per_mac",
    "memory_bits_per_mac",
    "resource_pressure_pct",
    "routing_pressure_score",
    "routing_risk_level",
    "likely_routing_limited",
    "performance_per_resource_score",
    "max_fanout",
    "avg_fanout",
    "validation_passed",
    "num_errors",
    "warnings",
]


CONFIG_MAP = {
    "N": "N",
    "tile_size": "tile_size",
    "TILE_SIZE": "tile_size",
    "num_macs": "num_macs",
    "NUM_MACS": "num_macs",
    "DATA_WIDTH": "data_width",
    "data_width": "data_width",
    "ACC_WIDTH": "acc_width",
    "acc_width": "acc_width",
    "MEM_TYPE": "mem_type",
    "mem_type": "mem_type",
    "DATAFLOW": "dataflow",
    "dataflow": "dataflow",
    "BUFFERING_MODE": "buffering_mode",
    "buffering_mode": "buffering_mode",
    "MEMORY_BURST_LEN": "memory_burst_len",
    "memory_burst_len": "memory_burst_len",
    "MAC_PIPELINE_STAGES": "mac_pipeline_stages",
    "mac_pipeline_stages": "mac_pipeline_stages",
    "MEMORY_BANKS_A": "memory_banks_a",
    "memory_banks_a": "memory_banks_a",
    "MEMORY_BANKS_B": "memory_banks_b",
    "memory_banks_b": "memory_banks_b",
    "TOP_ENTITY": "top_entity",
    "top_entity": "top_entity",
}


def load_json(path):
    path = Path(path)
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8-sig"))


def to_float(value):
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        return float(value)
    if isinstance(value, (int, float)):
        if isinstance(value, float) and math.isnan(value):
            return None
        return float(value)
    try:
        return float(str(value).replace(",", "").replace("%", ""))
    except ValueError:
        return None


def to_int(value):
    number = to_float(value)
    if number is None:
        return None
    return int(number)


def canonical_config(config):
    row = {}
    for source_key, target_key in CONFIG_MAP.items():
        if source_key in config:
            row[target_key] = config[source_key]

    row.setdefault("N", 128)
    row.setdefault("tile_size", 4)
    row.setdefault("num_macs", 4)
    row.setdefault("data_width", 8)
    row.setdefault("acc_width", 32)
    row.setdefault("mem_type", "internal_fpga_ram")
    row.setdefault("dataflow", "output_stationary")
    row.setdefault("buffering_mode", "single")
    row.setdefault("memory_burst_len", None)
    row.setdefault("mac_pipeline_stages", 0)
    row.setdefault("memory_banks_a", 1)
    row.setdefault("memory_banks_b", 1)
    row.setdefault("top_entity", "matrix_accelerator_full_top")

    for key in ("N", "tile_size", "num_macs", "data_width", "acc_width"):
        row[key] = to_int(row.get(key))

    return row


def find_first_regex(root, patterns):
    root = Path(root)
    for log_path in root.rglob("*"):
        if not log_path.is_file():
            continue
        if log_path.suffix.lower() not in {".log", ".txt", ".rpt", ".json"}:
            continue
        try:
            text = log_path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for pattern in patterns:
            regex_match = re.search(pattern, text, flags=re.IGNORECASE)
            if regex_match:
                return to_int(regex_match.group(1))
    return None


def extract_runtime_metrics(run_dir):
    run_dir = Path(run_dir)
    metrics = {}

    metrics["exec_cycles"] = find_first_regex(
        run_dir,
        [
            r"Ciclos de execucao:\s*([0-9]+)",
            r"exec_cycles\s*[:=]\s*([0-9]+)",
        ],
    )
    metrics["load_cycles"] = find_first_regex(run_dir, [r"load_cycles\s*[:=]\s*([0-9]+)"])
    metrics["compute_cycles"] = find_first_regex(run_dir, [r"compute_cycles\s*[:=]\s*([0-9]+)"])
    metrics["store_cycles"] = find_first_regex(run_dir, [r"store_cycles\s*[:=]\s*([0-9]+)"])

    validation = load_json(run_dir / "validation.json")
    host_validation = load_json(run_dir / "host_logs" / "validation.json")
    validation = validation or host_validation
    if validation:
        metrics["validation_passed"] = validation.get("passed", validation.get("validation_passed"))
        metrics["num_errors"] = validation.get("num_errors")
    else:
        metrics["validation_passed"] = None
        metrics["num_errors"] = None

    return metrics


def base_math_metrics(config, quartus, runtime):
    warnings = []
    n_value = to_int(config.get("N")) or 128
    num_macs = to_int(config.get("num_macs")) or 1
    fmax_mhz = to_float(quartus.get("fmax_mhz"))
    exec_cycles = to_float(runtime.get("exec_cycles"))

    ops_exact = (n_value**3) + (n_value**2 * (n_value - 1))
    ops_approx = 2 * (n_value**3)

    exec_time_us = None
    gops_eff_exact = None
    gops_eff_approx = None
    gops_peak = None
    peak_efficiency = None

    if exec_cycles is None:
        warnings.append("exec_cycles ausente")
    if fmax_mhz is None:
        warnings.append("fmax_mhz ausente")

    if exec_cycles and fmax_mhz:
        exec_time_s = exec_cycles / (fmax_mhz * 1_000_000.0)
        exec_time_us = exec_time_s * 1_000_000.0
        gops_eff_exact = ops_exact / exec_time_s / 1_000_000_000.0
        gops_eff_approx = ops_approx / exec_time_s / 1_000_000_000.0
        gops_peak = 2.0 * num_macs * fmax_mhz / 1000.0
        if gops_peak:
            peak_efficiency = gops_eff_approx / gops_peak

    return {
        "ops_exact": ops_exact,
        "ops_approx_2n3": ops_approx,
        "exec_time_us": exec_time_us,
        "gops_eff_exact": gops_eff_exact,
        "gops_eff_approx": gops_eff_approx,
        "gops_peak": gops_peak,
        "peak_efficiency": peak_efficiency,
        "_warnings": warnings,
    }


def resource_metrics(row, best_fmax):
    warnings = []

    alms = to_float(row.get("alms")) or 0.0
    dsps = to_float(row.get("dsps")) or 0.0
    block_memory_bits = to_float(row.get("block_memory_bits")) or 0.0
    num_macs = to_float(row.get("num_macs")) or 0.0
    gops = to_float(row.get("gops_eff_approx"))
    fmax = to_float(row.get("fmax_mhz"))

    alms_pct = to_float(row.get("alms_pct")) or 0.0
    dsps_pct = to_float(row.get("dsps_pct")) or 0.0
    mem_pct = to_float(row.get("block_memory_bits_pct")) or 0.0
    pins_pct = to_float(row.get("pins_pct")) or 0.0
    max_fanout = to_float(row.get("max_fanout")) or 0.0
    avg_fanout = to_float(row.get("avg_fanout")) or 0.0

    fmax_ratio = fmax / best_fmax if fmax is not None and best_fmax else None
    fmax_drop_pct = (1.0 - fmax_ratio) * 100.0 if fmax_ratio is not None else 0.0

    resource_pressure_pct = max(alms_pct, dsps_pct, mem_pct, pins_pct)
    fanout_component = min(max_fanout / 20.0, 35.0) + min(avg_fanout * 2.0, 15.0)
    routing_pressure_score = min(
        100.0,
        (0.22 * alms_pct)
        + (0.14 * dsps_pct)
        + (0.18 * mem_pct)
        + (0.10 * pins_pct)
        + fanout_component
        + (0.22 * fmax_drop_pct),
    )

    if routing_pressure_score >= 70.0:
        routing_risk_level = "high"
    elif routing_pressure_score >= 40.0:
        routing_risk_level = "medium"
    else:
        routing_risk_level = "low"

    likely_routing_limited = (
        routing_pressure_score >= 70.0
        or (fmax_ratio is not None and fmax_ratio < 0.70 and resource_pressure_pct >= 55.0)
        or (max_fanout >= 1000.0 and fmax_ratio is not None and fmax_ratio < 0.85)
    )

    if block_memory_bits == 0:
        warnings.append("block_memory_bits igual a zero")
    if row.get("flow_status") not in (None, "", "NA") and "successful" not in str(row.get("flow_status")).lower() and str(row.get("flow_status")).lower() not in {"success", "skipped"}:
        warnings.append("flow_status nao indica sucesso")
    if row.get("validation_passed") is False or str(row.get("validation_passed")).lower() == "false":
        warnings.append("validacao falhou")
    if to_int(row.get("num_errors")) not in (None, 0):
        warnings.append("num_errors maior que zero")

    peak_efficiency = to_float(row.get("peak_efficiency"))
    if peak_efficiency is not None and peak_efficiency > 1.05:
        warnings.append("peak_efficiency acima de 1.05")

    return {
        "fmax_ratio_to_best": fmax_ratio,
        "gops_per_alm": gops / alms if gops is not None and alms else None,
        "gops_per_dsp": gops / dsps if gops is not None and dsps else None,
        "gops_per_block_memory_mbit": gops / (block_memory_bits / 1_000_000.0) if gops is not None and block_memory_bits else None,
        "alms_per_mac": alms / num_macs if num_macs else None,
        "dsps_per_mac": dsps / num_macs if num_macs else None,
        "memory_bits_per_mac": block_memory_bits / num_macs if num_macs else None,
        "resource_pressure_pct": resource_pressure_pct,
        "routing_pressure_score": routing_pressure_score,
        "routing_risk_level": routing_risk_level,
        "likely_routing_limited": likely_routing_limited,
        "performance_per_resource_score": gops / (resource_pressure_pct + 1.0) if gops is not None else None,
        "_warnings": warnings,
    }


def normalize_quartus(parsed):
    normalized = {}
    for key in [
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
    ]:
        normalized[key] = parsed.get(key)
    return normalized


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def write_csv(path, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    extra_columns = []
    for row in rows:
        for key in row:
            if key not in CSV_COLUMNS and key not in extra_columns:
                extra_columns.append(key)

    fieldnames = CSV_COLUMNS + extra_columns
    with path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({column: row.get(column) for column in fieldnames})


def collect_results(runs_dir, output_csv):
    runs_dir = Path(runs_dir).resolve()
    output_csv = Path(output_csv).resolve()

    if not runs_dir.exists():
        raise SystemExit(f"runs-dir nao existe: {runs_dir}")

    collected = []
    for run_dir in sorted(path for path in runs_dir.iterdir() if path.is_dir()):
        config = canonical_config(load_json(run_dir / "config.json"))
        parsed_quartus = normalize_quartus(load_json(run_dir / "parsed_quartus.json"))
        runtime = extract_runtime_metrics(run_dir)

        row = {"run_id": run_dir.name}
        row.update(config)
        row.update(parsed_quartus)
        row.update(runtime)
        row.update(base_math_metrics(config, parsed_quartus, runtime))
        row["warnings"] = "; ".join(row.pop("_warnings"))
        collected.append(row)

    best_fmax = max((to_float(row.get("fmax_mhz")) or 0.0 for row in collected), default=0.0)

    final_rows = []
    for row in collected:
        resource_row = resource_metrics(row, best_fmax)
        warning_text = row.get("warnings") or ""
        resource_warnings = resource_row.pop("_warnings")
        if resource_warnings:
            warning_text = "; ".join([item for item in [warning_text, "; ".join(resource_warnings)] if item])
        row.update(resource_row)
        row["warnings"] = warning_text
        final_rows.append(row)

        run_metrics = {key: row.get(key) for key in CSV_COLUMNS if key not in CONFIG_MAP.values()}
        write_json(runs_dir / row["run_id"] / "metrics.json", run_metrics)

    write_csv(output_csv, final_rows)

    successful = [
        row for row in final_rows
        if "successful" in str(row.get("flow_status", "")).lower() or str(row.get("flow_status", "")).lower() in {"success", "skipped"}
    ]
    best_exact = max(final_rows, key=lambda row: to_float(row.get("gops_eff_exact")) or -1, default=None)
    best_approx = max(final_rows, key=lambda row: to_float(row.get("gops_eff_approx")) or -1, default=None)
    best_eff = max(final_rows, key=lambda row: to_float(row.get("peak_efficiency")) or -1, default=None)
    warnings = {row["run_id"]: row["warnings"] for row in final_rows if row.get("warnings")}

    summary = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "total_runs": len(final_rows),
        "successful_runs": len(successful),
        "error_or_suspect_runs": len(final_rows) - len(successful) + len(warnings),
        "best_by_gops_eff_exact": best_exact.get("run_id") if best_exact else None,
        "best_by_gops_eff_approx": best_approx.get("run_id") if best_approx else None,
        "best_by_peak_efficiency": best_eff.get("run_id") if best_eff else None,
        "csv": str(output_csv),
        "warnings": warnings,
    }
    write_json(output_csv.parent / "experiment_summary.json", summary)

    resource_summary = {
        "best_fmax_mhz": best_fmax,
        "routing_limited_runs": [row["run_id"] for row in final_rows if row.get("likely_routing_limited")],
        "rows": final_rows,
    }
    write_json(output_csv.parent / "resource_speed_analysis.json", resource_summary)

    print(f"CSV final: {output_csv}")
    print(f"Total de runs: {summary['total_runs']}")
    print(f"Runs bem-sucedidos: {summary['successful_runs']}")
    print(f"Melhor GOPS exact: {summary['best_by_gops_eff_exact']}")
    print(f"Melhor GOPS approx: {summary['best_by_gops_eff_approx']}")
    print(f"Melhor peak efficiency: {summary['best_by_peak_efficiency']}")
    if warnings:
        print(f"Warnings registrados em {output_csv.parent / 'experiment_summary.json'}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs-dir", required=True, type=Path)
    parser.add_argument("--output-csv", required=True, type=Path)
    parsed_args = parser.parse_args()
    collect_results(parsed_args.runs_dir, parsed_args.output_csv)


if __name__ == "__main__":
    main()
