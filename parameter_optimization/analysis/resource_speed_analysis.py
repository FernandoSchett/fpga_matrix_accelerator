import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from metrics_utils import calculate_associations, load_table, top_associations


def write_resource_speed_analysis(experiment_dir):
    experiment_dir = Path(experiment_dir).resolve()
    csv_path = experiment_dir / "experiment_results.csv"
    data, is_pandas = load_table(csv_path)
    associations = calculate_associations(data, is_pandas)
    output = {
        "note": "Correlacoes indicam associacao/tendencia, nao causalidade.",
        "top_associations": [
            {"name": name, **values}
            for name, values in top_associations(associations, limit=20)
        ],
        "associations": associations,
    }
    output_path = experiment_dir / "resource_speed_analysis.json"
    output_path.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--experiment-dir", required=True, type=Path)
    parsed_args = parser.parse_args()
    write_resource_speed_analysis(parsed_args.experiment_dir)


if __name__ == "__main__":
    main()
