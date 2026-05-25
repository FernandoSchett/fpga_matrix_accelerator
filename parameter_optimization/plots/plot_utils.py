from pathlib import Path


def get_matplotlib():
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as exc:
        raise SystemExit("matplotlib nao esta instalado; instale para gerar graficos.") from exc
    return plt


def save_figure(plt, plots_dir, filename):
    plots_dir = Path(plots_dir)
    plots_dir.mkdir(parents=True, exist_ok=True)
    png_path = plots_dir / f"{filename}.png"
    plt.tight_layout()
    plt.savefig(png_path, dpi=160)
    plt.close()
    return png_path


def numeric_pairs(rows, x_key, y_key, to_float):
    xs = []
    ys = []
    labels = []
    for row in rows:
        x_value = to_float(row.get(x_key))
        y_value = to_float(row.get(y_key))
        if x_value is None or y_value is None:
            continue
        xs.append(x_value)
        ys.append(y_value)
        labels.append(str(row.get("run_id", "")))
    return xs, ys, labels
