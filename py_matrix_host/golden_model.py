"""Golden reference model for integer matrix multiplication.

Generates two structured text files:
  - one with input test vectors containing matrices A and B
  - one with expected output test vectors containing matrix C = A x B
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path
from typing import NamedTuple

try:
    from .project_config import DEFAULT_ENV_FILE, load_matrix_config
except ImportError:
    from project_config import DEFAULT_ENV_FILE, load_matrix_config


DEFAULT_EXAMPLE_A = [[1, 2], [3, 4]]
DEFAULT_EXAMPLE_B = [[5, 6], [7, 8]]


class TestVector(NamedTuple):
    index: int
    a: list[list[int]]
    b: list[list[int]]
    c: list[list[int]]


def parse_args() -> argparse.Namespace:
    env_parser = argparse.ArgumentParser(add_help=False)
    env_parser.add_argument(
        "--env-file",
        type=Path,
        default=DEFAULT_ENV_FILE,
        help="Configuration file with shared defaults. Default: .env",
    )
    env_args, _ = env_parser.parse_known_args()
    config = load_matrix_config(env_args.env_file)

    parser = argparse.ArgumentParser(
        description="Generate integer matrices and the expected C = A x B result.",
        parents=[env_parser],
    )
    parser.add_argument(
        "--num-tests",
        type=int,
        default=config.num_tests,
        help=f"Number of test vectors to generate. Default from .env: {config.num_tests}",
    )
    parser.add_argument(
        "--rows-a",
        type=int,
        default=config.rows_a,
        help=f"Number of rows in matrix A and C. Default from .env: {config.rows_a}",
    )
    parser.add_argument(
        "--cols-a",
        type=int,
        default=config.cols_a,
        help=f"Number of columns in matrix A. Default from .env: {config.cols_a}",
    )
    parser.add_argument(
        "--rows-b",
        type=int,
        default=config.rows_b,
        help=f"Number of rows in matrix B. Must match COLS_A. Default from .env: {config.rows_b}",
    )
    parser.add_argument(
        "--cols-b",
        type=int,
        default=config.cols_b,
        help=f"Number of columns in matrix B and C. Default from .env: {config.cols_b}",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=config.seed,
        help=f"Random seed, used to reproduce the same matrices. Default from .env: {config.seed}",
    )
    parser.add_argument(
        "--min-value",
        type=int,
        default=config.min_value,
        help=f"Minimum generated integer value. Default from .env: {config.min_value}",
    )
    parser.add_argument(
        "--max-value",
        type=int,
        default=config.max_value,
        help=f"Maximum generated integer value. Default from .env: {config.max_value}",
    )
    parser.add_argument(
        "--input-file",
        type=Path,
        default=config.input_file,
        help=f"Output file for matrices A and B. Default from .env: {config.input_file}",
    )
    parser.add_argument(
        "--output-file",
        type=Path,
        default=config.output_file,
        help=f"Output file for expected matrix C. Default from .env: {config.output_file}",
    )
    example_group = parser.add_mutually_exclusive_group()
    example_group.add_argument(
        "--example",
        dest="example",
        action="store_true",
        default=config.example,
        help=(
            "Use the initial fixed 2x2 example as TEST 0. "
            "If --num-tests is greater than 1, the remaining tests are random."
        ),
    )
    example_group.add_argument(
        "--no-example",
        dest="example",
        action="store_false",
        help="Disable the fixed 2x2 example, even if EXAMPLE=true in .env.",
    )
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    if args.num_tests <= 0:
        raise ValueError("--num-tests must be greater than zero")
    if args.rows_a <= 0:
        raise ValueError("--rows-a must be greater than zero")
    if args.cols_a <= 0:
        raise ValueError("--cols-a must be greater than zero")
    if args.rows_b <= 0:
        raise ValueError("--rows-b must be greater than zero")
    if args.cols_b <= 0:
        raise ValueError("--cols-b must be greater than zero")
    if args.cols_a != args.rows_b:
        raise ValueError("--cols-a must be equal to --rows-b for A x B")
    if args.min_value > args.max_value:
        raise ValueError("--min-value must be less than or equal to --max-value")


def generate_matrix(
    rng: random.Random, rows: int, cols: int, min_value: int, max_value: int
) -> list[list[int]]:
    return [[rng.randint(min_value, max_value) for _ in range(cols)] for _ in range(rows)]


def multiply_matrices(a: list[list[int]], b: list[list[int]]) -> list[list[int]]:
    rows_a = len(a)
    cols_a = len(a[0])
    rows_b = len(b)
    cols_b = len(b[0])

    if cols_a != rows_b:
        raise ValueError("Matrix sizes are incompatible: A columns must match B rows")

    return [
        [sum(a[row][k] * b[k][col] for k in range(cols_a)) for col in range(cols_b)]
        for row in range(rows_a)
    ]


def format_matrix(name: str, matrix: list[list[int]]) -> str:
    rows = len(matrix)
    cols = len(matrix[0]) if rows else 0
    body = "\n".join(" ".join(str(value) for value in row) for row in matrix)
    return f"{name} {rows} {cols}\n{body}\n"


def generate_test_vectors(args: argparse.Namespace) -> list[TestVector]:
    rng = random.Random(args.seed)
    tests = []

    for index in range(args.num_tests):
        if args.example and index == 0:
            a = DEFAULT_EXAMPLE_A
            b = DEFAULT_EXAMPLE_B
        else:
            a = generate_matrix(rng, args.rows_a, args.cols_a, args.min_value, args.max_value)
            b = generate_matrix(rng, args.rows_b, args.cols_b, args.min_value, args.max_value)

        tests.append(TestVector(index=index, a=a, b=b, c=multiply_matrices(a, b)))

    return tests


def format_input_test(test: TestVector) -> str:
    return (
        f"TEST {test.index}\n"
        f"{format_matrix('A', test.a)}"
        f"\n{format_matrix('B', test.b)}"
        "END_TEST\n"
    )


def format_output_test(test: TestVector) -> str:
    return (
        f"TEST {test.index}\n"
        f"{format_matrix('C', test.c)}"
        "END_TEST\n"
    )


def write_inputs(path: Path, tests: list[TestVector], args: argparse.Namespace) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    metadata = (
        "# Matrix inputs generated by golden_model.py\n"
        f"# seed={args.seed} num_tests={len(tests)} rows_a={args.rows_a} "
        f"cols_a={args.cols_a} rows_b={args.rows_b} cols_b={args.cols_b}\n"
        f"# min_value={args.min_value} max_value={args.max_value} example={args.example}\n\n"
        f"NUM_TESTS {len(tests)}\n\n"
    )
    path.write_text(metadata + "\n".join(format_input_test(test) for test in tests), encoding="utf-8")


def write_outputs(path: Path, tests: list[TestVector], args: argparse.Namespace) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    metadata = (
        "# Expected output generated by golden_model.py\n"
        "# C = A x B\n"
        f"# seed={args.seed} num_tests={len(tests)} rows_c={args.rows_a} "
        f"cols_c={args.cols_b} rows_b={args.rows_b} example={args.example}\n\n"
        f"NUM_TESTS {len(tests)}\n\n"
    )
    path.write_text(metadata + "\n".join(format_output_test(test) for test in tests), encoding="utf-8")


def print_matrix(name: str, matrix: list[list[int]]) -> None:
    print(f"{name} =")
    for row in matrix:
        print("  " + " ".join(f"{value:4d}" for value in row))
    print()


def main() -> None:
    args = parse_args()
    validate_args(args)

    tests = generate_test_vectors(args)

    write_inputs(args.input_file, tests, args)
    write_outputs(args.output_file, tests, args)

    for test in tests:
        print(f"TEST {test.index}")
        print_matrix("A", test.a)
        print_matrix("B", test.b)
        print_matrix("C = A x B", test.c)
    print(f"Wrote inputs to:  {args.input_file}")
    print(f"Wrote outputs to: {args.output_file}")


if __name__ == "__main__":
    main()
