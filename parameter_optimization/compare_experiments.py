import argparse
import csv
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path


PARAM_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = PARAM_DIR.parent
ANALYSIS_DIR = PARAM_DIR / "analysis"
PLOTS_DIR = PARAM_DIR / "plots"
for import_path in (ANALYSIS_DIR, PARAM_DIR, PLOTS_DIR):
    if str(import_path) not in sys.path:
        sys.path.insert(0, str(import_path))

from metrics_utils import to_float
from pareto_analysis import pareto_front
from plots.plot_utils import get_matplotlib, save_figure


DEFAULT_METRICS = [
    "gops_eff_approx",
    "gops_eff_exact",
    "peak_efficiency",
    "performance_per_resource_score",
    "fmax_mhz",
]


def read_csv(path):
    path = Path(path)
    with path.open(newline="", encoding="utf-8") as csv_file:
        return list(csv.DictReader(csv_file))


def write_csv(path, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["experiment_name"]
    for row in rows:
        for key in row.keys():
            if key not in fieldnames:
                fieldnames.append(key)

    with path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def discover_experiments(results_root, selected):
    results_root = Path(results_root)
    if selected:
        return [results_root / name for name in selected]

    experiments = []
    if not results_root.exists():
        return experiments

    for path in sorted(results_root.iterdir()):
        if not path.is_dir():
            continue
        if path.name.startswith("_") or path.name == "compare_experiments":
            continue
        if (path / "experiment_results.csv").exists() or (path / "runs").exists():
            experiments.append(path)
    return experiments


def run_python(script_path, arguments):
    command = [sys.executable, str(script_path), *[str(arg) for arg in arguments]]
    completed = subprocess.run(command, cwd=PROJECT_ROOT, text=True)
    return completed.returncode


def refresh_experiment(experiment_dir, warnings, refresh_analysis=False):
    runs_dir = experiment_dir / "runs"
    if not runs_dir.exists():
        warnings.append(f"{experiment_dir.name}: pasta runs/ nao encontrada; refresh ignorado.")
        return

    collect_script = ANALYSIS_DIR / "collect_results.py"
    csv_path = experiment_dir / "experiment_results.csv"
    code = run_python(collect_script, ["--runs-dir", runs_dir, "--output-csv", csv_path])
    if code != 0:
        warnings.append(f"{experiment_dir.name}: collect_results.py retornou codigo {code}.")
        return

    if refresh_analysis:
        analysis_script = ANALYSIS_DIR / "run_analysis.py"
        code = run_python(analysis_script, ["--experiment-dir", experiment_dir])
        if code != 0:
            warnings.append(f"{experiment_dir.name}: run_analysis.py retornou codigo {code}.")


def normalize_flow_status(value):
    return str(value or "").strip().lower()


def is_false(value):
    return str(value or "").strip().lower() in ("false", "0", "no", "nao")


def is_eligible(row, metric_key):
    metric = to_float(row.get(metric_key))
    fmax = to_float(row.get("fmax_mhz"))
    exec_cycles = to_float(row.get("exec_cycles"))
    flow_status = normalize_flow_status(row.get("flow_status"))
    validation_passed = row.get("validation_passed")
    num_errors = to_float(row.get("num_errors"))

    if metric is None:
        return False
    if fmax is None or fmax <= 0:
        return False
    if exec_cycles is None or exec_cycles <= 0:
        return False
    if flow_status and flow_status != "successful":
        return False
    if is_false(validation_passed):
        return False
    if num_errors is not None and num_errors > 0:
        return False
    return True


def best_row(rows, metric_key, eligible_only=True):
    candidates = []
    for row in rows:
        value = to_float(row.get(metric_key))
        if value is None:
            continue
        if eligible_only and not is_eligible(row, metric_key):
            continue
        candidates.append(row)
    if not candidates:
        return None
    return max(candidates, key=lambda row: to_float(row.get(metric_key)) or float("-inf"))


def compact_row(row):
    if not row:
        return None
    keys = [
        "experiment_name",
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
        "fmax_mhz",
        "exec_cycles",
        "gops_eff_exact",
        "gops_eff_approx",
        "gops_peak",
        "peak_efficiency",
        "performance_per_resource_score",
        "resource_pressure_pct",
        "routing_pressure_score",
        "routing_risk_level",
        "likely_routing_limited",
        "alms",
        "alms_pct",
        "dsps",
        "dsps_pct",
        "block_memory_bits_pct",
        "validation_passed",
        "num_errors",
    ]
    return {key: row.get(key) for key in keys if key in row}


def row_label(row, metric_key):
    if not row:
        return "NA"
    metric = to_float(row.get(metric_key))
    metric_text = "NA" if metric is None else f"{metric:.6g}"
    return (
        f"{row.get('experiment_name')}/{row.get('run_id')} "
        f"(tile={row.get('tile_size')}, macs={row.get('num_macs')}, "
        f"acc={row.get('acc_width')}, pipe={row.get('mac_pipeline_stages')}, "
        f"banks={row.get('memory_banks_a')}/{row.get('memory_banks_b')}, "
        f"{metric_key}={metric_text})"
    )


def rows_by_experiment(rows):
    grouped = {}
    for row in rows:
        grouped.setdefault(row.get("experiment_name", "unknown"), []).append(row)
    return grouped


def top_rows(rows, metric_key, limit, eligible_only=True):
    candidates = []
    for row in rows:
        value = to_float(row.get(metric_key))
        if value is None:
            continue
        if eligible_only and not is_eligible(row, metric_key):
            continue
        candidates.append(row)
    return sorted(candidates, key=lambda row: to_float(row.get(metric_key)) or 0.0, reverse=True)[:limit]


def get_plotter(warnings):
    try:
        return get_matplotlib()
    except SystemExit as exc:
        warnings.append(str(exc))
        return None


def experiment_color_map(plt, rows):
    experiments = sorted({row.get("experiment_name", "unknown") for row in rows})
    cmap = plt.get_cmap("tab10")
    return {name: cmap(idx % 10) for idx, name in enumerate(experiments)}


def scatter_by_experiment(rows, x_key, y_key, xlabel, ylabel, filename, plots_dir, warnings):
    plt = get_plotter(warnings)
    if plt is None:
        return None

    colors = experiment_color_map(plt, rows)
    has_points = False
    plt.figure(figsize=(8, 5))
    for experiment, group in rows_by_experiment(rows).items():
        xs = []
        ys = []
        for row in group:
            x_value = to_float(row.get(x_key))
            y_value = to_float(row.get(y_key))
            if x_value is not None and y_value is not None:
                xs.append(x_value)
                ys.append(y_value)
        if xs:
            has_points = True
            plt.scatter(xs, ys, alpha=0.75, label=experiment, color=colors.get(experiment))

    if not has_points:
        plt.close()
        return None

    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(f"{ylabel} vs {xlabel}")
    plt.grid(True, linestyle="--", alpha=0.35)
    plt.legend(fontsize=8)
    return save_figure(plt, plots_dir, filename)


def bar_best_by_experiment(rows, metric_key, filename, plots_dir, warnings):
    plt = get_plotter(warnings)
    if plt is None:
        return None

    pairs = []
    for experiment, group in rows_by_experiment(rows).items():
        best = best_row(group, metric_key, eligible_only=False)
        if best:
            value = to_float(best.get(metric_key))
            if value is not None:
                pairs.append((experiment, value))

    if not pairs:
        return None

    pairs.sort(key=lambda item: item[1], reverse=True)
    labels = [item[0] for item in pairs]
    values = [item[1] for item in pairs]
    plt.figure(figsize=(9, 5))
    plt.bar(labels, values)
    plt.xticks(rotation=25, ha="right")
    plt.ylabel(metric_key)
    plt.title(f"Melhor {metric_key} por experimento")
    return save_figure(plt, plots_dir, filename)


def bar_top_global(rows, metric_key, filename, plots_dir, warnings, limit=12):
    plt = get_plotter(warnings)
    if plt is None:
        return None

    selected = top_rows(rows, metric_key, limit, eligible_only=False)
    if not selected:
        return None

    labels = [f"{row.get('experiment_name')}\n{row.get('run_id')}" for row in selected]
    values = [to_float(row.get(metric_key)) for row in selected]
    plt.figure(figsize=(11, 5))
    plt.bar(labels, values)
    plt.xticks(rotation=35, ha="right", fontsize=8)
    plt.ylabel(metric_key)
    plt.title(f"Top global por {metric_key}")
    return save_figure(plt, plots_dir, filename)


def pareto_global(rows, cost_key, perf_key, filename, plots_dir, warnings):
    plt = get_plotter(warnings)
    if plt is None:
        return None

    points = [
        row for row in rows
        if to_float(row.get(cost_key)) is not None and to_float(row.get(perf_key)) is not None
    ]
    if not points:
        return None

    colors = experiment_color_map(plt, rows)
    plt.figure(figsize=(8, 5))
    for experiment, group in rows_by_experiment(points).items():
        xs = [to_float(row.get(cost_key)) for row in group]
        ys = [to_float(row.get(perf_key)) for row in group]
        plt.scatter(xs, ys, alpha=0.65, label=experiment, color=colors.get(experiment))

    frontier = pareto_front(points, cost_key, perf_key)
    if frontier:
        fx = [to_float(row.get(cost_key)) for row in frontier]
        fy = [to_float(row.get(perf_key)) for row in frontier]
        plt.plot(fx, fy, color="black", marker="o", linewidth=1.5, label="Pareto global")

    plt.xlabel(cost_key)
    plt.ylabel(perf_key)
    plt.title(f"Pareto global: {perf_key} vs {cost_key}")
    plt.grid(True, linestyle="--", alpha=0.35)
    plt.legend(fontsize=8)
    return save_figure(plt, plots_dir, filename)


def heatmap_best_tile_macs(rows, metric_key, filename, plots_dir, warnings):
    plt = get_plotter(warnings)
    if plt is None:
        return None

    best_by_pair = {}
    for row in rows:
        tile = to_float(row.get("tile_size"))
        macs = to_float(row.get("num_macs"))
        value = to_float(row.get(metric_key))
        if None in (tile, macs, value):
            continue
        key = (tile, macs)
        if key not in best_by_pair or value > best_by_pair[key]:
            best_by_pair[key] = value

    if not best_by_pair:
        return None

    tile_values = sorted({key[0] for key in best_by_pair})
    mac_values = sorted({key[1] for key in best_by_pair})
    matrix = []
    for mac in mac_values:
        matrix.append([best_by_pair.get((tile, mac), float("nan")) for tile in tile_values])

    plt.figure(figsize=(7, 5))
    image = plt.imshow(matrix, origin="lower", aspect="auto", cmap="viridis")
    plt.colorbar(image, label=metric_key)
    plt.xticks(range(len(tile_values)), [str(int(value)) for value in tile_values])
    plt.yticks(range(len(mac_values)), [str(int(value)) for value in mac_values])
    plt.xlabel("tile_size")
    plt.ylabel("num_macs")
    plt.title(f"Melhor {metric_key} global por tile_size x num_macs")
    return save_figure(plt, plots_dir, filename)


def generate_plots(rows, plots_dir, warnings, top_n):
    plots_dir = Path(plots_dir)
    plots_dir.mkdir(parents=True, exist_ok=True)
    generated = []
    specs = [
        (bar_best_by_experiment, (rows, "gops_eff_approx", "01_bar_best_gops_by_experiment", plots_dir, warnings)),
        (bar_best_by_experiment, (rows, "performance_per_resource_score", "02_bar_best_perf_resource_by_experiment", plots_dir, warnings)),
        (bar_top_global, (rows, "gops_eff_approx", "03_bar_top_global_gops_eff_approx", plots_dir, warnings, top_n)),
        (bar_top_global, (rows, "performance_per_resource_score", "04_bar_top_global_performance_resource", plots_dir, warnings, top_n)),
        (scatter_by_experiment, (rows, "fmax_mhz", "gops_eff_approx", "Fmax (MHz)", "GOPS approx", "05_scatter_fmax_vs_gops_by_experiment", plots_dir, warnings)),
        (scatter_by_experiment, (rows, "resource_pressure_pct", "gops_eff_approx", "Resource pressure (%)", "GOPS approx", "06_scatter_resource_pressure_vs_gops_by_experiment", plots_dir, warnings)),
        (scatter_by_experiment, (rows, "routing_pressure_score", "fmax_mhz", "Routing pressure score", "Fmax (MHz)", "07_scatter_routing_pressure_vs_fmax_by_experiment", plots_dir, warnings)),
        (scatter_by_experiment, (rows, "alms_pct", "gops_eff_approx", "ALMs (%)", "GOPS approx", "08_scatter_alms_pct_vs_gops_by_experiment", plots_dir, warnings)),
        (scatter_by_experiment, (rows, "dsps", "gops_eff_approx", "DSPs", "GOPS approx", "09_scatter_dsps_vs_gops_by_experiment", plots_dir, warnings)),
        (pareto_global, (rows, "resource_pressure_pct", "gops_eff_approx", "10_pareto_resource_pressure_vs_gops_global", plots_dir, warnings)),
        (pareto_global, (rows, "alms", "gops_eff_approx", "11_pareto_alms_vs_gops_global", plots_dir, warnings)),
        (heatmap_best_tile_macs, (rows, "gops_eff_approx", "12_heatmap_best_tile_macs_gops_global", plots_dir, warnings)),
    ]

    for plot_function, args in specs:
        output = plot_function(*args)
        if output:
            generated.append(str(output))

    (plots_dir / "plots_manifest.txt").write_text("\n".join(generated), encoding="utf-8")
    return generated


def generate_report(path, rows, summary, metric_key, top_n):
    best = summary["best"]
    lines = [
        "# Comparacao Global de Experimentos",
        "",
        "Este relatorio compara os CSVs ja gerados pelos sweeps. Ele nao executa Quartus nem ModelSim.",
        "",
        "## Melhor Configuracao Global",
    ]

    for metric in DEFAULT_METRICS:
        lines.append(f"- Melhor por `{metric}`: {row_label(best.get(metric), metric)}")

    lines.extend([
        "",
        "## Melhor por Experimento",
    ])

    for experiment, info in summary["experiments"].items():
        row = info.get(f"best_{metric_key}")
        lines.append(
            f"- `{experiment}`: {row_label(row, metric_key)} "
            f"(runs={info.get('rows_total')}, elegiveis={info.get('eligible_rows')})"
        )

    lines.extend([
        "",
        f"## Top {top_n} Global por `{metric_key}`",
        "",
        "| # | experimento | run_id | tile | macs | acc | pipe | bancos | fmax_mhz | gops_eff_approx | score recurso | risco roteamento |",
        "|---|---|---|---:|---:|---:|---:|---|---:|---:|---:|---|",
    ])

    for index, row in enumerate(top_rows(rows, metric_key, top_n, eligible_only=True), start=1):
        lines.append(
            f"| {index} | {row.get('experiment_name')} | {row.get('run_id')} | "
            f"{row.get('tile_size')} | {row.get('num_macs')} | {row.get('acc_width')} | "
            f"{row.get('mac_pipeline_stages')} | {row.get('memory_banks_a')}/{row.get('memory_banks_b')} | "
            f"{row.get('fmax_mhz')} | {row.get('gops_eff_approx')} | "
            f"{row.get('performance_per_resource_score')} | {row.get('routing_risk_level')} |"
        )

    lines.extend([
        "",
        "## Avisos",
    ])

    warnings = summary.get("warnings", [])
    if warnings:
        lines.extend([f"- {warning}" for warning in warnings])
    else:
        lines.append("- Nenhum aviso.")

    lines.extend([
        "",
        "## Arquivos Gerados",
        f"- `all_experiment_results.csv`",
        f"- `comparison_summary.json`",
        f"- `plots/`",
    ])

    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Compara resultados de varios sweeps arquiteturais.")
    parser.add_argument("--results-root", default=str(PARAM_DIR / "results"))
    parser.add_argument("--experiments", nargs="*", default=None)
    parser.add_argument("--output-dir", default="")
    parser.add_argument("--metric", default="gops_eff_approx")
    parser.add_argument("--top-n", type=int, default=12)
    parser.add_argument("--refresh", action="store_true", help="Reexecuta collect_results.py antes de comparar.")
    parser.add_argument("--refresh-analysis", action="store_true", help="Tambem reexecuta run_analysis.py por experimento.")
    args = parser.parse_args()

    results_root = Path(args.results_root).resolve()
    output_dir = Path(args.output_dir).resolve() if args.output_dir else results_root / "compare_experiments"
    output_dir.mkdir(parents=True, exist_ok=True)

    warnings = []
    experiment_dirs = discover_experiments(results_root, args.experiments)
    if not experiment_dirs:
        raise SystemExit(f"Nenhum experimento encontrado em {results_root}.")

    rows = []
    experiment_summary = {}

    for experiment_dir in experiment_dirs:
        if args.refresh or args.refresh_analysis:
            refresh_experiment(experiment_dir, warnings, refresh_analysis=args.refresh_analysis)

        csv_path = experiment_dir / "experiment_results.csv"
        if not csv_path.exists():
            warnings.append(f"{experiment_dir.name}: experiment_results.csv nao encontrado; experimento ignorado.")
            continue

        experiment_rows = read_csv(csv_path)
        for row in experiment_rows:
            row["experiment_name"] = experiment_dir.name
        rows.extend(experiment_rows)

        eligible = [row for row in experiment_rows if is_eligible(row, args.metric)]
        experiment_summary[experiment_dir.name] = {
            "csv": str(csv_path),
            "rows_total": len(experiment_rows),
            "eligible_rows": len(eligible),
            f"best_{args.metric}": compact_row(best_row(experiment_rows, args.metric, eligible_only=True)),
        }
        if not eligible:
            warnings.append(f"{experiment_dir.name}: nenhum run elegivel para {args.metric}.")

    if not rows:
        raise SystemExit("Nenhuma linha de resultado encontrada para comparar.")

    combined_csv = output_dir / "all_experiment_results.csv"
    write_csv(combined_csv, rows)

    best = {metric: compact_row(best_row(rows, metric, eligible_only=True)) for metric in DEFAULT_METRICS}
    summary = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "results_root": str(results_root),
        "output_dir": str(output_dir),
        "metric": args.metric,
        "rows_total": len(rows),
        "eligible_rows": len([row for row in rows if is_eligible(row, args.metric)]),
        "experiments": experiment_summary,
        "best": best,
        "warnings": warnings,
    }

    plots = generate_plots(rows, output_dir / "plots", warnings, args.top_n)
    summary["plots"] = plots
    write_json(output_dir / "comparison_summary.json", summary)
    generate_report(output_dir / "comparison_report.md", rows, summary, args.metric, args.top_n)

    print(f"Resultados combinados: {combined_csv}")
    print(f"Resumo: {output_dir / 'comparison_summary.json'}")
    print(f"Relatorio: {output_dir / 'comparison_report.md'}")
    print(f"Graficos: {output_dir / 'plots'}")
    selected_best = best.get(args.metric)
    if selected_best:
        print("Melhor config global:")
        print(row_label(selected_best, args.metric))
    if warnings:
        print("Avisos:")
        for warning in warnings:
            print(f"- {warning}")


if __name__ == "__main__":
    main()
