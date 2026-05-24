import csv
from pathlib import Path

def load_data(csv_path):
    try:
        import pandas as pd
        df = pd.read_csv(csv_path)
        # return list of dicts to be consistent or just return df and flag
        return df, True
    except ImportError:
        print("Warning: pandas is not available. Falling back to csv.DictReader.")
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            data = []
            for row in reader:
                # Convert numeric columns
                parsed_row = {}
                for k, v in row.items():
                    try:
                        if '.' in v:
                            parsed_row[k] = float(v)
                        else:
                            parsed_row[k] = int(v)
                    except ValueError:
                        parsed_row[k] = v
                data.append(parsed_row)
        return data, False

def calculate_correlations(df, is_pandas):
    correlations = {}
    metrics_x = ["tile_size", "num_macs", "alms", "alms_pct", "aluts", "registers", 
                 "dsps", "dsps_pct", "block_memory_bits", "block_memory_bits_pct", 
                 "pins", "pins_pct", "max_fanout", "avg_fanout", "resource_pressure_pct", "routing_pressure_score"]
    metrics_y = ["fmax_mhz", "exec_cycles", "exec_time_us", "gops_eff_exact", "gops_eff_approx", "gops_peak", "peak_efficiency", "performance_per_resource_score"]

    if is_pandas:
        for x in metrics_x:
            for y in metrics_y:
                if x in df.columns and y in df.columns:
                    try:
                        corr = df[x].corr(df[y])
                        correlations[f"{x}_vs_{y}"] = corr
                    except:
                        pass
    else:
        # Fallback calculation
        import math
        def pearson(x_list, y_list):
            n = len(x_list)
            if n == 0: return 0
            mean_x = sum(x_list)/n
            mean_y = sum(y_list)/n
            num = sum((xi - mean_x)*(yi - mean_y) for xi, yi in zip(x_list, y_list))
            den = math.sqrt(sum((xi - mean_x)**2 for xi in x_list) * sum((yi - mean_y)**2 for yi in y_list))
            return num / den if den != 0 else 0
            
        for x in metrics_x:
            for y in metrics_y:
                try:
                    if len(df) > 0 and x in df[0] and y in df[0]:
                        x_list = [row[x] for row in df if isinstance(row[x], (int, float))]
                        y_list = [row[y] for row in df if isinstance(row[y], (int, float))]
                        correlations[f"{x}_vs_{y}"] = pearson(x_list, y_list)
                except:
                    pass
    return correlations
