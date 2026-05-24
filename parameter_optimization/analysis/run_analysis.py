import argparse
import sys
from pathlib import Path
from metrics_utils import load_data, calculate_correlations
import os

# append relative path so it can find plots
sys.path.append(str(Path(__file__).parent.parent))
from plots.plot_experiment_results import generate_all_plots

def get_best_configs(data, is_pandas):
    if is_pandas:
        if 'gops_eff_approx' not in data.columns:
            print("Error: Missing expected columns in CSV.")
            sys.exit(1)
        best_gops = data.loc[data['gops_eff_approx'].idxmax()]['run_id'] if not data.empty else None
        best_peak_eff = data.loc[data['peak_efficiency'].idxmax()]['run_id'] if not data.empty else None
        best_perf_res = data.loc[data['performance_per_resource_score'].idxmax()]['run_id'] if not data.empty else None
        routing_limited = data[data['likely_routing_limited'] == True]['run_id'].tolist() if 'likely_routing_limited' in data.columns else []
    else:
        if len(data) == 0 or 'gops_eff_approx' not in data[0]:
            print("Error: Missing expected columns in CSV.")
            sys.exit(1)
        best_gops = max(data, key=lambda x: x.get('gops_eff_approx', 0)).get('run_id')
        best_peak_eff = max(data, key=lambda x: x.get('peak_efficiency', 0)).get('run_id')
        best_perf_res = max(data, key=lambda x: x.get('performance_per_resource_score', 0)).get('run_id')
        routing_limited = [row['run_id'] for row in data if row.get('likely_routing_limited') == 'True' or row.get('likely_routing_limited') is True]

    return {
        "best_gops": best_gops,
        "best_peak_eff": best_peak_eff,
        "best_perf_res": best_perf_res,
        "routing_limited": routing_limited
    }

def generate_report(experiment_dir, best, correlations):
    experiment_dir = Path(experiment_dir)
    report_path = experiment_dir / "analysis_report.md"
    
    lines = [
        f"# Analysis Report for {experiment_dir.name}",
        "",
        "## Best Configurations",
        f"- **Best by GOPS Approx**: {best['best_gops']}",
        f"- **Best by Peak Efficiency**: {best['best_peak_eff']}",
        f"- **Best by Performance/Resource**: {best['best_perf_res']}",
        "",
        "## Routing Constraints",
        f"- **Configs possibly routing limited**: {', '.join(best['routing_limited']) if best['routing_limited'] else 'None'}",
        "",
        "## Correlations",
        "Key associations discovered between resources and performance. (Correlation does not imply causality; indicates trends):",
        ""
    ]
    
    sorted_corr = sorted(correlations.items(), key=lambda item: abs(item[1]), reverse=True)
    for k, v in sorted_corr[:10]:
        lines.append(f"- **{k}**: {v:.3f}")
        
    lines.extend([
        "",
        "## Warnings",
        "- **Data points**: Ensure you have enough data points to validate the correlations. Small datasets may yield spurious correlations."
    ])

    with open(report_path, "w") as f:
        f.write("\n".join(lines))
    print(f"Report written to {report_path}")

def run_analysis(experiment_dir):
    experiment_dir = Path(experiment_dir)
    csv_path = experiment_dir / "experiment_results.csv"
    
    if not csv_path.exists():
        print(f"Error: {csv_path} does not exist.")
        sys.exit(1)
        
    data, is_pandas = load_data(csv_path)
    correlations = calculate_correlations(data, is_pandas)
    best = get_best_configs(data, is_pandas)
    
    generate_report(experiment_dir, best, correlations)
    generate_all_plots(data, is_pandas, experiment_dir / "plots")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--experiment-dir", required=True, type=str)
    args = parser.parse_args()
    
    run_analysis(args.experiment_dir)
