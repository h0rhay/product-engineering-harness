---
name: calculator-mvp
max_iterations: 2
---

# Calculator MVP rubric

Applies only to a workpiece repo that has already been scaffolded via `harness init`.

1. `pnpm test` exits 0 after the engineer's changes (reviewer cites the command output).
2. A new Vitest test covers the per-person split calculation (reviewer cites the test file path).
3. The app renders three inputs (total, number of people, tip %) and one output (per-person amount). A Playwright smoke test in the engineer's branch verifies this (reviewer cites the test file path).
4. No new axe-core accessibility violations are introduced compared to `main` (reviewer cites the axe report).
