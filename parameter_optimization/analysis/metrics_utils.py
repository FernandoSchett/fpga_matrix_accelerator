import csv
import math
from pathlib import Path


RESOURCE_METRICS = [
    "tile_size",
    "num_macs",
    "alms",
    "alms_pct",
    "aluts",
    "registers",
    "dsps",
    "dsps_pct",
    "block_memory_bits",
    "block_memory_bits_pct",
    "pins",
    "pins_pct",
    "power_total_mw",
    "power_core_dynamic_mw",
    "power_core_static_mw",
    "power_io_mw",
    "max_fanout",
    "avg_fanout",
    "resource_pressure_pct",
    "routing_pressure_score",
]

PERFORMANCE_METRICS = [
    "fmax_mhz",
    "exec_cycles",
    "exec_time_us",
    "gops_eff_exact",
    "gops_eff_approx",
    "gops_peak",
    "peak_efficiency",
    "gops_per_watt",
    "energy_est_mj",
    "energy_per_op_approx_nj",
    "energy_per_op_exact_nj",
    "performance_per_resource_score",
]


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


def load_table(csv_path):
    csv_path = Path(csv_path)
    if not csv_path.exists():
        raise SystemExit(f"CSV nao encontrado: {csv_path}")

    try:
        import pandas as pd
    except ImportError:
        rows = []
        with csv_path.open(newline="", encoding="utf-8") as csv_file:
            reader = csv.DictReader(csv_file)
            for row in reader:
                parsed = {}
                for key, value in row.items():
                    numeric = to_float(value)
                    parsed[key] = numeric if numeric is not None else value
                rows.append(parsed)
        return rows, False

    return pd.read_csv(csv_path), True


def require_columns(data, is_pandas, columns):
    if is_pandas:
        missing = [column for column in columns if column not in data.columns]
    else:
        available = set(data[0].keys()) if data else set()
        missing = [column for column in columns if column not in available]
    if missing:
        raise SystemExit("Colunas ausentes no CSV: " + ", ".join(missing))


def column_values(data, is_pandas, column):
    if is_pandas:
        if column not in data.columns:
            return []
        values = data[column].tolist()
    else:
        values = [row.get(column) for row in data if column in row]
    return [to_float(value) for value in values if to_float(value) is not None]


def rows_as_dicts(data, is_pandas):
    if is_pandas:
        return data.to_dict(orient="records")
    return list(data)


def pearson(xs, ys):
    if len(xs) != len(ys) or len(xs) < 2:
        return None
    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    denom_x = math.sqrt(sum((x - mean_x) ** 2 for x in xs))
    denom_y = math.sqrt(sum((y - mean_y) ** 2 for y in ys))
    denominator = denom_x * denom_y
    if denominator == 0:
        return None
    return numerator / denominator


def ranks(values):
    indexed = sorted(enumerate(values), key=lambda item: item[1])
    result = [0.0] * len(values)
    idx = 0
    while idx < len(indexed):
        end_idx = idx
        while end_idx + 1 < len(indexed) and indexed[end_idx + 1][1] == indexed[idx][1]:
            end_idx += 1
        rank = (idx + end_idx + 2) / 2.0
        for ranked_idx in range(idx, end_idx + 1):
            result[indexed[ranked_idx][0]] = rank
        idx = end_idx + 1
    return result


def spearman(xs, ys):
    if len(xs) != len(ys) or len(xs) < 2:
        return None
    return pearson(ranks(xs), ranks(ys))


def linear_regression(xs, ys):
    if len(xs) != len(ys) or len(xs) < 2:
        return {"slope": None, "intercept": None, "r2": None}
    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    ss_x = sum((x - mean_x) ** 2 for x in xs)
    if ss_x == 0:
        return {"slope": None, "intercept": None, "r2": None}
    slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / ss_x
    intercept = mean_y - slope * mean_x
    predictions = [slope * x + intercept for x in xs]
    ss_tot = sum((y - mean_y) ** 2 for y in ys)
    ss_res = sum((y - pred) ** 2 for y, pred in zip(ys, predictions))
    r2 = 1.0 - (ss_res / ss_tot) if ss_tot else None
    return {"slope": slope, "intercept": intercept, "r2": r2}


def paired_numeric_values(data, is_pandas, left, right):
    rows = rows_as_dicts(data, is_pandas)
    xs = []
    ys = []
    for row in rows:
        x_value = to_float(row.get(left))
        y_value = to_float(row.get(right))
        if x_value is not None and y_value is not None:
            xs.append(x_value)
            ys.append(y_value)
    return xs, ys


def calculate_associations(data, is_pandas, resource_metrics=None, performance_metrics=None):
    resource_metrics = resource_metrics or RESOURCE_METRICS
    performance_metrics = performance_metrics or PERFORMANCE_METRICS
    associations = {}

    for resource in resource_metrics:
        for performance in performance_metrics:
            xs, ys = paired_numeric_values(data, is_pandas, resource, performance)
            if len(xs) < 2:
                continue
            associations[f"{resource}_vs_{performance}"] = {
                "resource_metric": resource,
                "performance_metric": performance,
                "n": len(xs),
                "pearson": pearson(xs, ys),
                "spearman": spearman(xs, ys),
                "linear_regression": linear_regression(xs, ys),
                "interpretation": "associacao estatistica; nao implica causalidade",
            }
    return associations


def top_associations(associations, limit=10):
    def score(item):
        value = item[1].get("pearson")
        return abs(value) if value is not None else -1.0

    return sorted(associations.items(), key=score, reverse=True)[:limit]
