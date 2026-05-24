import argparse
import json
import csv
from pathlib import Path

def calculate_metrics(config, parsed_quartus):
    metrics = {}
    # Hardware metrics
    alms = parsed_quartus.get("alms", 1)
    dsps = parsed_quartus.get("dsps", 1)
    block_memory_bits = parsed_quartus.get("block_memory_bits", 1)
    fmax_mhz = parsed_quartus.get("fmax_mhz", 1.0)
    
    num_macs = config.get("num_macs", 1)
    N = config.get("N", 128)
    
    metrics["alms_per_mac"] = alms / num_macs if num_macs > 0 else 0
    metrics["dsps_per_mac"] = dsps / num_macs if num_macs > 0 else 0
    metrics["memory_bits_per_mac"] = block_memory_bits / num_macs if num_macs > 0 else 0
    
    # Performance metrics
    metrics["exec_cycles"] = (N ** 3) / num_macs if num_macs > 0 else 0
    metrics["exec_time_us"] = metrics["exec_cycles"] / fmax_mhz if fmax_mhz > 0 else 0
    
    # Operations: roughly 2 * N^3
    ops = 2 * (N ** 3)
    metrics["gops_eff_approx"] = (ops / metrics["exec_time_us"] / 1000.0) if metrics["exec_time_us"] > 0 else 0
    metrics["gops_eff_exact"] = metrics["gops_eff_approx"]
    metrics["gops_peak"] = (fmax_mhz * num_macs * 2) / 1000.0
    metrics["peak_efficiency"] = metrics["gops_eff_approx"] / metrics["gops_peak"] if metrics["gops_peak"] > 0 else 0
    
    # Ratios
    metrics["gops_per_alm"] = metrics["gops_eff_approx"] / alms if alms > 0 else 0
    metrics["gops_per_dsp"] = metrics["gops_eff_approx"] / dsps if dsps > 0 else 0
    mbits = block_memory_bits / 1000000.0
    metrics["gops_per_block_memory_mbit"] = metrics["gops_eff_approx"] / mbits if mbits > 0 else 0
    
    # Resource pressure
    metrics["resource_pressure_pct"] = max(
        parsed_quartus.get("alms_pct", 0),
        parsed_quartus.get("dsps_pct", 0),
        parsed_quartus.get("block_memory_bits_pct", 0)
    )
    
    metrics["routing_pressure_score"] = (
        parsed_quartus.get("alms_pct", 0) * 0.4 +
        parsed_quartus.get("pins_pct", 0) * 0.2 +
        min(parsed_quartus.get("max_fanout", 0) / 100.0, 10.0) * 2.0 +
        parsed_quartus.get("avg_fanout", 0) * 2.0
    )
    
    if metrics["routing_pressure_score"] > 80:
        metrics["routing_risk_level"] = "high"
        metrics["likely_routing_limited"] = True
    elif metrics["routing_pressure_score"] > 50:
        metrics["routing_risk_level"] = "medium"
        metrics["likely_routing_limited"] = False
    else:
        metrics["routing_risk_level"] = "low"
        metrics["likely_routing_limited"] = False
        
    metrics["performance_per_resource_score"] = metrics["gops_eff_approx"] / (metrics["resource_pressure_pct"] + 1)
    
    return metrics

def collect(runs_dir, output_csv):
    runs_dir = Path(runs_dir)
    results = []
    
    # Need to find max fmax to calculate fmax_ratio_to_best
    max_fmax = 0
    all_runs_data = []

    for run_path in runs_dir.iterdir():
        if run_path.is_dir():
            config_file = run_path / "config.json"
            quartus_file = run_path / "parsed_quartus.json"
            
            if config_file.exists() and quartus_file.exists():
                with open(config_file) as f: config = json.load(f)
                with open(quartus_file) as f: quartus = json.load(f)
                
                max_fmax = max(max_fmax, quartus.get("fmax_mhz", 0))
                
                all_runs_data.append({
                    "run_dir": run_path,
                    "config": config,
                    "quartus": quartus
                })

    for data in all_runs_data:
        metrics = calculate_metrics(data["config"], data["quartus"])
        metrics["fmax_ratio_to_best"] = data["quartus"].get("fmax_mhz", 0) / max_fmax if max_fmax > 0 else 0
        
        # update likely_routing_limited based on fmax drop 
        if metrics["fmax_ratio_to_best"] < 0.7 and metrics["resource_pressure_pct"] > 70:
            metrics["likely_routing_limited"] = True
            
        with open(data["run_dir"] / "metrics.json", "w") as f:
            json.dump(metrics, f, indent=4)
            
        row = {"run_id": data["run_dir"].name}
        row.update(data["config"])
        row.update(data["quartus"])
        row.update(metrics)
        results.append(row)

    if not results:
        print("No results found.")
        return

    # Dump CSV
    output_csv = Path(output_csv)
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    
    fieldnames = list(results[0].keys())
    with open(output_csv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)
        
    print(f"Results collected and written to {output_csv}")
    
    # Save experiment_summary.json and resource_speed_analysis.json
    with open(output_csv.parent / "experiment_summary.json", "w") as f:
        json.dump({"total_runs": len(results), "max_fmax": max_fmax}, f, indent=4)
    with open(output_csv.parent / "resource_speed_analysis.json", "w") as f:
        json.dump(results, f, indent=4)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs-dir", required=True, type=str)
    parser.add_argument("--output-csv", required=True, type=str)
    args = parser.parse_args()
    
    collect(args.runs_dir, args.output_csv)
