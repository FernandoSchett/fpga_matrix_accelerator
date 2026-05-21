"""Shared project configuration loaded from a .env file."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ENV_FILE = PROJECT_ROOT / ".env"


@dataclass(frozen=True)
class MatrixConfig:
    num_tests: int
    data_width: int
    acc_width: int
    rows_a: int
    cols_a: int
    rows_b: int
    cols_b: int
    seed: int
    min_value: int
    max_value: int
    input_file: Path
    output_file: Path
    example: bool


def load_env_file(path: Path = DEFAULT_ENV_FILE) -> None:
    if not path.exists():
        return

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()

        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"Invalid .env line {line_number}: expected KEY=VALUE")

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("\"'")

        if not key:
            raise ValueError(f"Invalid .env line {line_number}: empty key")

        os.environ[key] = value


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None:
        return default

    try:
        return int(value)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer, got {value!r}") from exc


def env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default

    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False

    raise ValueError(f"{name} must be a boolean, got {value!r}")


def env_path(name: str, default: str, base_dir: Path) -> Path:
    path = Path(os.environ.get(name, default))
    if path.is_absolute():
        return path
    return base_dir / path


def load_matrix_config(env_file: Path = DEFAULT_ENV_FILE) -> MatrixConfig:
    env_file = Path(env_file)
    load_env_file(env_file)
    base_dir = env_file.parent
    cols_a = env_int("COLS_A", 2)

    return MatrixConfig(
        num_tests=env_int("NUM_TESTS", 1),
        data_width=env_int("DATA_WIDTH", 16),
        acc_width=env_int("ACC_WIDTH", 32),
        rows_a=env_int("ROWS_A", 2),
        cols_a=cols_a,
        rows_b=env_int("ROWS_B", cols_a),
        cols_b=env_int("COLS_B", 2),
        seed=env_int("SEED", 0),
        min_value=env_int("MIN_VALUE", 0),
        max_value=env_int("MAX_VALUE", 9),
        input_file=env_path("MATRIX_INPUT_FILE", "matrix_inputs.txt", base_dir),
        output_file=env_path("MATRIX_OUTPUT_FILE", "matrix_outputs.txt", base_dir),
        example=env_bool("EXAMPLE", False),
    )
