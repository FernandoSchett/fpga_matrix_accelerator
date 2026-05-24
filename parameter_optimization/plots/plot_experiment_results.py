import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path
import sys

# Hack to import from analysis/pareto_analysis.py
sys.path.append(str(Path(__file__).parent.parent))
from analysis.pareto_analysis import identify_pareto

def generate_all_plots(data, is_pandas, plots_dir):
    plots_dir = Path(plots_dir)
    plots_dir.mkdir(parents=True, exist_ok=True)
    
    # Helper to extract columns
    def get_col(col):
        if is_pandas:
            return data[col].tolist() if col in data.columns else []
        else:
            return [row.get(col) for row in data if col in row]

    run_ids = get_col("run_id")
    tile_sizes = get_col("tile_size")
    num_macs = get_col("num_macs")
    gops = get_col("gops_eff_approx")
    fmax = get_col("fmax_mhz")
    alms = get_col("alms")
    alms_pct = get_col("alms_pct")
    routing_pressure = get_col("routing_pressure_score")
    dsps = get_col("dsps")
    bram_pct = get_col("block_memory_bits_pct")
    max_fanout = get_col("max_fanout")
    resource_pressure = get_col("resource_pressure_pct")
    bram = get_col("block_memory_bits")
    perf_res_score = get_col("performance_per_resource_score")

    def scatter_plot(x, y, xlabel, ylabel, filename):
        if not x or not y or len(x) != len(y): return
        plt.figure()
        plt.scatter(x, y, alpha=0.7)
        plt.xlabel(xlabel)
        plt.ylabel(ylabel)
        plt.title(f"{ylabel} vs {xlabel}")
        plt.grid(True, linestyle="--", alpha=0.5)
        plt.savefig(plots_dir / filename)
        plt.close()

    def pareto_plot(x, y, xlabel, ylabel, filename):
        if not x or not y or len(x) != len(y): return
        plt.figure()
        plt.scatter(x, y, label='Configurations', alpha=0.6)
        
        pareto_front = identify_pareto(x, y, minimize_x=True, maximize_y=True)
        if pareto_front:
            px, py = zip(*pareto_front)
            plt.plot(px, py, 'r-', marker='o', label='Pareto Front')
            
        plt.xlabel(xlabel)
        plt.ylabel(ylabel)
        plt.title(f"Pareto: {ylabel} vs {xlabel}")
        plt.grid(True, linestyle="--", alpha=0.5)
        plt.legend()
        plt.savefig(plots_dir / filename)
        plt.close()

    def heatmap_plot(x, y, z, xlabel, ylabel, zlabel, filename):
        if not x or not y or not z: return
        try:
            ux = sorted(list(set(x)))
            uy = sorted(list(set(y)))
            
            Z = np.zeros((len(uy), len(ux)))
            Z[:] = np.nan
            
            for xi, yi, zi in zip(x, y, z):
                if xi in ux and yi in uy:
                    Z[uy.index(yi), ux.index(xi)] = zi
                    
            plt.figure()
            plt.imshow(Z, origin='lower', aspect='auto', cmap='viridis')
            plt.colorbar(label=zlabel)
            plt.xticks(range(len(ux)), ux)
            plt.yticks(range(len(uy)), uy)
            plt.xlabel(xlabel)
            plt.ylabel(ylabel)
            plt.title(f"Heatmap: {zlabel}")
            plt.savefig(plots_dir / filename)
            plt.close()
        except:
            pass

    def bar_chart_top(labels, values, title, ylabel, filename, top_n=5):
        if not labels or not values: return
        pairs = list(zip(labels, values))
        pairs.sort(key=lambda p: p[1] if p[1] is not None else -1e9, reverse=True)
        pairs = pairs[:top_n]
        
        l, v = zip(*pairs)
        plt.figure()
        plt.bar(l, v, color='skyblue')
        plt.xticks(rotation=45, ha='right')
        plt.ylabel(ylabel)
        plt.title(title)
        plt.tight_layout()
        plt.savefig(plots_dir / filename)
        plt.close()

    # 1. Heatmap: tile_size x num_macs -> gops_eff_approx
    heatmap_plot(tile_sizes, num_macs, gops, "tile_size", "num_macs", "gops_eff_approx", "01_heatmap_tile_macs_gops.png")
    # 2. Heatmap: tile_size x num_macs -> fmax_mhz
    heatmap_plot(tile_sizes, num_macs, fmax, "tile_size", "num_macs", "fmax_mhz", "02_heatmap_tile_macs_fmax.png")
    
    # 3. Scatter: alms_pct vs fmax_mhz
    scatter_plot(alms_pct, fmax, "ALMs %", "Fmax (MHz)", "03_scatter_alms_fmax.png")
    # 4. Scatter: routing_pressure_score vs fmax_mhz
    scatter_plot(routing_pressure, fmax, "Routing Pressure Score", "Fmax (MHz)", "04_scatter_routing_fmax.png")
    # 5. Scatter: dsps vs gops_eff_approx
    scatter_plot(dsps, gops, "DSPs", "GOPS Approx", "05_scatter_dsps_gops.png")
    # 6. Pareto: alms vs gops_eff_approx
    pareto_plot(alms, gops, "ALMs", "GOPS Approx", "06_pareto_alms_gops.png")

    # Additional
    scatter_plot(bram_pct, gops, "BRAM %", "GOPS Approx", "07_scatter_bram_gops.png")
    scatter_plot(max_fanout, fmax, "Max Fanout", "Fmax (MHz)", "08_scatter_max_fanout_fmax.png")
    scatter_plot(resource_pressure, fmax, "Resource Pressure %", "Fmax (MHz)", "09_scatter_res_pressure_fmax.png")
    scatter_plot(resource_pressure, gops, "Resource Pressure %", "GOPS Approx", "10_scatter_res_pressure_gops.png")
    
    bar_chart_top(run_ids, gops, "Top Configs by GOPS", "GOPS Approx", "11_bar_top_gops.png")
    bar_chart_top(run_ids, perf_res_score, "Top Configs by Perf/Resource", "Score", "12_bar_top_perf_res.png")
    bar_chart_top(run_ids, routing_pressure, "Highest Routing Pressure", "Score", "13_bar_top_routing_pressure.png")

    pareto_plot(dsps, gops, "DSPs", "GOPS Approx", "15_pareto_dsps_gops.png")
    pareto_plot(bram, gops, "Block Memory Bits", "GOPS Approx", "16_pareto_bram_gops.png")
    pareto_plot(resource_pressure, gops, "Resource Pressure %", "GOPS Approx", "17_pareto_res_pressure_gops.png")

    print(f"All plots generated in {plots_dir}")
