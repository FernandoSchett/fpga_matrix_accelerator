import math
import sys
from pathlib import Path

PLOTS_DIR = Path(__file__).resolve().parent
PARAM_DIR = PLOTS_DIR.parent
ANALYSIS_DIR = PARAM_DIR / "analysis"
for import_path in (PARAM_DIR, ANALYSIS_DIR, PLOTS_DIR):
    if str(import_path) not in sys.path:
        sys.path.insert(0, str(import_path))

from analysis.metrics_utils import rows_as_dicts, to_float
from analysis.pareto_analysis import pareto_front
from plots.plot_utils import get_matplotlib, numeric_pairs, save_figure


def scatter_plot(rows, x_key, y_key, xlabel, ylabel, filename, plots_dir):
    xs, ys, _labels = numeric_pairs(rows, x_key, y_key, to_float)
    if not xs:
        return None
    plt = get_matplotlib()
    plt.figure(figsize=(7, 5))
    plt.scatter(xs, ys, alpha=0.75)
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(f"{ylabel} vs {xlabel}")
    plt.grid(True, linestyle="--", alpha=0.35)
    return save_figure(plt, plots_dir, filename)


def heatmap_plot(rows, x_key, y_key, z_key, xlabel, ylabel, zlabel, filename, plots_dir):
    points = []
    for row in rows:
        x_value = to_float(row.get(x_key))
        y_value = to_float(row.get(y_key))
        z_value = to_float(row.get(z_key))
        if None not in (x_value, y_value, z_value):
            points.append((x_value, y_value, z_value))
    if not points:
        return None

    x_values = sorted({point[0] for point in points})
    y_values = sorted({point[1] for point in points})
    matrix = [[math.nan for _ in x_values] for _ in y_values]
    for x_value, y_value, z_value in points:
        matrix[y_values.index(y_value)][x_values.index(x_value)] = z_value

    plt = get_matplotlib()
    plt.figure(figsize=(7, 5))
    image = plt.imshow(matrix, origin="lower", aspect="auto", cmap="viridis")
    plt.colorbar(image, label=zlabel)
    plt.xticks(range(len(x_values)), [str(int(value)) if value.is_integer() else str(value) for value in x_values])
    plt.yticks(range(len(y_values)), [str(int(value)) if value.is_integer() else str(value) for value in y_values])
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(f"{zlabel}: {xlabel} x {ylabel}")
    return save_figure(plt, plots_dir, filename)


def pareto_plot(rows, cost_key, performance_key, xlabel, ylabel, filename, plots_dir):
    xs, ys, _labels = numeric_pairs(rows, cost_key, performance_key, to_float)
    if not xs:
        return None

    frontier = pareto_front(rows, cost_key, performance_key)
    plt = get_matplotlib()
    plt.figure(figsize=(7, 5))
    plt.scatter(xs, ys, alpha=0.6, label="configuracoes")
    if frontier:
        fx = [to_float(row.get(cost_key)) for row in frontier]
        fy = [to_float(row.get(performance_key)) for row in frontier]
        plt.plot(fx, fy, color="red", marker="o", label="Pareto")
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(f"Pareto: {ylabel} vs {xlabel}")
    plt.grid(True, linestyle="--", alpha=0.35)
    plt.legend()
    return save_figure(plt, plots_dir, filename)


def bar_top(rows, value_key, title, ylabel, filename, plots_dir, reverse=True, top_n=8):
    pairs = []
    for row in rows:
        value = to_float(row.get(value_key))
        if value is not None:
            pairs.append((str(row.get("run_id", "")), value))
    if not pairs:
        return None
    pairs = sorted(pairs, key=lambda item: item[1], reverse=reverse)[:top_n]
    labels = [item[0] for item in pairs]
    values = [item[1] for item in pairs]

    plt = get_matplotlib()
    plt.figure(figsize=(8, 5))
    plt.bar(labels, values)
    plt.xticks(rotation=35, ha="right")
    plt.ylabel(ylabel)
    plt.title(title)
    return save_figure(plt, plots_dir, filename)


def correlation_matrix(rows, filename, plots_dir):
    metric_keys = [
        "tile_size",
        "num_macs",
        "alms_pct",
        "dsps_pct",
        "block_memory_bits_pct",
        "resource_pressure_pct",
        "routing_pressure_score",
        "fmax_mhz",
        "gops_eff_approx",
        "peak_efficiency",
        "performance_per_resource_score",
    ]
    available = []
    values_by_key = {}
    for key in metric_keys:
        values = [to_float(row.get(key)) for row in rows]
        values = [value for value in values if value is not None]
        if len(values) >= 2:
            available.append(key)
            values_by_key[key] = values
    if len(available) < 2:
        return None

    try:
        import numpy as np
    except ImportError:
        return None

    matrix = []
    for left in available:
        row_values = []
        for right in available:
            pairs = []
            for row in rows:
                left_value = to_float(row.get(left))
                right_value = to_float(row.get(right))
                if left_value is not None and right_value is not None:
                    pairs.append((left_value, right_value))
            if len(pairs) < 2:
                row_values.append(math.nan)
            else:
                xs, ys = zip(*pairs)
                row_values.append(float(np.corrcoef(xs, ys)[0, 1]))
        matrix.append(row_values)

    plt = get_matplotlib()
    plt.figure(figsize=(10, 8))
    image = plt.imshow(matrix, vmin=-1, vmax=1, cmap="coolwarm")
    plt.colorbar(image, label="Pearson")
    plt.xticks(range(len(available)), available, rotation=45, ha="right")
    plt.yticks(range(len(available)), available)
    plt.title("Matriz de correlacao")
    return save_figure(plt, plots_dir, filename)


def generate_all_plots(data, is_pandas, plots_dir):
    rows = rows_as_dicts(data, is_pandas)
    plots_dir = Path(plots_dir)
    plots_dir.mkdir(parents=True, exist_ok=True)

    generated = []
    specs = [
        (heatmap_plot, ("tile_size", "num_macs", "gops_eff_approx", "tile_size", "num_macs", "gops_eff_approx", "01_heatmap_tile_macs_gops")),
        (heatmap_plot, ("tile_size", "num_macs", "fmax_mhz", "tile_size", "num_macs", "fmax_mhz", "02_heatmap_tile_macs_fmax")),
        (scatter_plot, ("alms_pct", "fmax_mhz", "ALMs (%)", "Fmax (MHz)", "03_scatter_alms_pct_fmax")),
        (scatter_plot, ("routing_pressure_score", "fmax_mhz", "Routing pressure score", "Fmax (MHz)", "04_scatter_routing_pressure_fmax")),
        (scatter_plot, ("dsps", "gops_eff_approx", "DSPs", "GOPS efetivo approx", "05_scatter_dsps_gops")),
        (pareto_plot, ("alms", "gops_eff_approx", "ALMs", "GOPS efetivo approx", "06_pareto_alms_gops")),
        (scatter_plot, ("block_memory_bits_pct", "gops_eff_approx", "Block memory (%)", "GOPS efetivo approx", "07_scatter_block_memory_pct_gops")),
        (scatter_plot, ("max_fanout", "fmax_mhz", "Max fanout", "Fmax (MHz)", "08_scatter_max_fanout_fmax")),
        (scatter_plot, ("resource_pressure_pct", "fmax_mhz", "Resource pressure (%)", "Fmax (MHz)", "09_scatter_resource_pressure_fmax")),
        (scatter_plot, ("resource_pressure_pct", "gops_eff_approx", "Resource pressure (%)", "GOPS efetivo approx", "10_scatter_resource_pressure_gops")),
        (bar_top, ("gops_eff_approx", "Top configuracoes por GOPS approx", "GOPS approx", "11_bar_top_gops")),
        (bar_top, ("performance_per_resource_score", "Top por performance/recurso", "Score", "12_bar_top_performance_resource")),
        (bar_top, ("routing_pressure_score", "Maiores routing pressure score", "Score", "13_bar_routing_pressure")),
        (correlation_matrix, ("14_correlation_matrix",)),
        (pareto_plot, ("dsps", "gops_eff_approx", "DSPs", "GOPS efetivo approx", "15_pareto_dsps_gops")),
        (pareto_plot, ("block_memory_bits", "gops_eff_approx", "Block memory bits", "GOPS efetivo approx", "16_pareto_block_memory_gops")),
        (pareto_plot, ("resource_pressure_pct", "gops_eff_approx", "Resource pressure (%)", "GOPS efetivo approx", "17_pareto_resource_pressure_gops")),
    ]

    for plot_function, args in specs:
        output = plot_function(rows, *args, plots_dir)
        if output:
            generated.append(str(output))

    manifest = plots_dir / "plots_manifest.txt"
    manifest.write_text("\n".join(generated), encoding="utf-8")
    print(f"Graficos gerados em {plots_dir}")
    return generated
