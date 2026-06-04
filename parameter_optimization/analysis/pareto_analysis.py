from metrics_utils import rows_as_dicts, to_float


def dominates(candidate, other, cost_key, performance_key):
    candidate_cost = to_float(candidate.get(cost_key))
    other_cost = to_float(other.get(cost_key))
    candidate_perf = to_float(candidate.get(performance_key))
    other_perf = to_float(other.get(performance_key))

    if None in (candidate_cost, other_cost, candidate_perf, other_perf):
        return False

    better_or_equal_cost = candidate_cost <= other_cost
    better_or_equal_perf = candidate_perf >= other_perf
    strictly_better = candidate_cost < other_cost or candidate_perf > other_perf
    return better_or_equal_cost and better_or_equal_perf and strictly_better


def pareto_front(rows, cost_key, performance_key):
    valid_rows = [
        row for row in rows
        if to_float(row.get(cost_key)) is not None and to_float(row.get(performance_key)) is not None
    ]
    frontier = []
    for row in valid_rows:
        if not any(dominates(candidate, row, cost_key, performance_key) for candidate in valid_rows):
            frontier.append(row)
    return sorted(frontier, key=lambda item: to_float(item.get(cost_key)) or 0.0)


def build_pareto_sets(data, is_pandas):
    rows = rows_as_dicts(data, is_pandas)
    specs = [
        ("alms", "gops_eff_approx"),
        ("dsps", "gops_eff_approx"),
        ("block_memory_bits", "gops_eff_approx"),
        ("resource_pressure_pct", "gops_eff_approx"),
        ("power_total_mw", "gops_eff_approx"),
    ]
    return {
        f"{cost}_vs_{performance}": pareto_front(rows, cost, performance)
        for cost, performance in specs
    }
