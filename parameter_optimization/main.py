import argparse
import subprocess
import sys
from pathlib import Path


PARAM_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = PARAM_DIR.parent
RUNNER_SCRIPT = PARAM_DIR / "run_experiment.ps1"


def run_experiment(args):
    if not RUNNER_SCRIPT.exists():
        raise SystemExit(f"Runner PowerShell nao encontrado: {RUNNER_SCRIPT}")

    command = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(RUNNER_SCRIPT),
        "-ConfigPath",
        str(args.config_path),
        "-VsimRetryCount",
        str(args.vsim_retry_count),
        "-VsimRetrySeconds",
        str(args.vsim_retry_seconds),
    ]

    if args.skip_simulation:
        command.append("-SkipSimulation")
    if args.skip_quartus:
        command.append("-SkipQuartus")
    if args.skip_analysis:
        command.append("-SkipAnalysis")
    if args.no_resume:
        command.append("-NoResume")
    if args.run_limit > 0:
        command.extend(["-RunLimit", str(args.run_limit)])

    completed = subprocess.run(command, cwd=PROJECT_ROOT)
    return completed.returncode


def main():
    parser = argparse.ArgumentParser(description="Roda um experimento arquitetural a partir de um JSON.")
    parser.add_argument(
        "--config-path",
        default=str(PARAM_DIR / "configs" / "01_compute_sweep.json"),
        help="Caminho do JSON de experimento.",
    )
    parser.add_argument("--skip-simulation", action="store_true")
    parser.add_argument("--skip-quartus", action="store_true")
    parser.add_argument("--skip-analysis", action="store_true")
    parser.add_argument("--no-resume", action="store_true")
    parser.add_argument("--run-limit", type=int, default=0)
    parser.add_argument("--vsim-retry-count", type=int, default=10)
    parser.add_argument("--vsim-retry-seconds", type=int, default=30)
    args = parser.parse_args()

    return run_experiment(args)


if __name__ == "__main__":
    raise SystemExit(main())
