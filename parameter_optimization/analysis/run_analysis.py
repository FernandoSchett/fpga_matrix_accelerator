import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PARAM_DIR = SCRIPT_DIR.parent
for import_path in (SCRIPT_DIR, PARAM_DIR):
    if str(import_path) not in sys.path:
        sys.path.insert(0, str(import_path))

from metrics_utils import calculate_associations, load_table, require_columns, rows_as_dicts, to_float, top_associations
from pareto_analysis import build_pareto_sets
from plots.plot_experiment_results import generate_all_plots


REQUIRED_COLUMNS = [
    "run_id",
    "tile_size",
    "num_macs",
    "fmax_mhz",
    "gops_eff_approx",
    "peak_efficiency",
    "performance_per_resource_score",
    "routing_pressure_score",
]


def best_row(rows, key):
    valid = [row for row in rows if to_float(row.get(key)) is not None]
    if not valid:
        return None
    return max(valid, key=lambda row: to_float(row.get(key)))


def row_label(row):
    if not row:
        return "NA"
    return (
        f"{row.get('run_id')} "
        f"(tile={row.get('tile_size')}, macs={row.get('num_macs')}, "
        f"gops={to_float(row.get('gops_eff_approx'))})"
    )


def write_json(path, data):
    path = Path(path)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def generate_report(experiment_dir, rows, associations, pareto_sets, generated_plots):
    experiment_dir = Path(experiment_dir)
    report_path = experiment_dir / "analysis_report.md"

    best_gops = best_row(rows, "gops_eff_approx")
    best_peak = best_row(rows, "peak_efficiency")
    best_perf_resource = best_row(rows, "performance_per_resource_score")
    routing_limited = [row for row in rows if str(row.get("likely_routing_limited")).lower() == "true"]
    top_corrs = top_associations(associations, limit=8)

    lines = [
        f"# Relatorio de Analise: {experiment_dir.name}",
        "",
        "## Melhores Configuracoes",
        f"- Melhor por `gops_eff_approx`: {row_label(best_gops)}",
        f"- Melhor por `peak_efficiency`: {row_label(best_peak)}",
        f"- Melhor por `performance_per_resource_score`: {row_label(best_perf_resource)}",
        "",
        "## Possivel Limitacao por Roteamento",
    ]

    if routing_limited:
        for row in routing_limited:
            lines.append(
                f"- {row.get('run_id')}: score={row.get('routing_pressure_score')}, "
                f"risco={row.get('routing_risk_level')}, fmax={row.get('fmax_mhz')}"
            )
    else:
        lines.append("- Nenhuma configuracao marcada como possivelmente limitada por roteamento.")

    lines.extend([
        "",
        "## Principais Correlacoes",
        "As correlacoes abaixo indicam associacao/tendencia, nao causalidade.",
    ])
    if top_corrs:
        for name, values in top_corrs:
            pearson = values.get("pearson")
            spearman = values.get("spearman")
            r2 = values.get("linear_regression", {}).get("r2")
            lines.append(f"- `{name}`: Pearson={pearson:.3f}, Spearman={spearman:.3f}, R2={r2:.3f}" if None not in (pearson, spearman, r2) else f"- `{name}`: dados insuficientes")
    else:
        lines.append("- Dados insuficientes para correlacoes.")

    lines.extend([
        "",
        "## Pareto",
    ])
    for name, frontier in pareto_sets.items():
        labels = ", ".join(str(row.get("run_id")) for row in frontier) if frontier else "NA"
        lines.append(f"- `{name}`: {labels}")

    lines.extend([
        "",
        "## Interpretacao dos Graficos",
        "- Heatmaps ajudam a ver regioes onde `tile_size` e `num_macs` melhoram GOPS ou prejudicam Fmax.",
        "- Scatters de recurso vs Fmax/GOPS mostram associacoes que podem sugerir gargalos de roteamento ou uso de DSP/M10K.",
        "- Graficos de Pareto destacam configuracoes que entregam desempenho sem custo dominado por outra opcao.",
        "",
        "## Graficos Gerados",
    ])
    for plot_path in generated_plots:
        lines.append(f"- `{Path(plot_path).name}`")

    if len(rows) < 6:
        lines.extend([
            "",
            "## Limitacao",
            "- Ha poucos pontos experimentais. Use as correlacoes como indicio exploratorio, nao conclusao forte.",
        ])

    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Relatorio gerado: {report_path}")


def run_analysis(experiment_dir):
    experiment_dir = Path(experiment_dir).resolve()
    csv_path = experiment_dir / "experiment_results.csv"
    data, is_pandas = load_table(csv_path)
    require_columns(data, is_pandas, REQUIRED_COLUMNS)

    rows = rows_as_dicts(data, is_pandas)
    associations = calculate_associations(data, is_pandas)
    pareto_sets = build_pareto_sets(data, is_pandas)
    generated_plots = generate_all_plots(data, is_pandas, experiment_dir / "plots")

    analysis_json = {
        "note": "Correlacoes indicam associacao/tendencia, nao causalidade.",
        "top_associations": [{"name": name, **values} for name, values in top_associations(associations, limit=20)],
        "associations": associations,
        "pareto": {
            name: [row.get("run_id") for row in frontier]
            for name, frontier in pareto_sets.items()
        },
    }
    write_json(experiment_dir / "resource_speed_analysis.json", analysis_json)
    generate_report(experiment_dir, rows, associations, pareto_sets, generated_plots)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--experiment-dir", required=True, type=Path)
    parsed_args = parser.parse_args()
    run_analysis(parsed_args.experiment_dir)


if __name__ == "__main__":
    main()
