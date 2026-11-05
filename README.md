# Binomial Option Pricer

Prices European and American calls and puts on the multi-period binomial model
(Shreve, *Stochastic Calculus for Finance I*, ch. 1 and 4). The Julia code is the
pricing engine; the Excel workbook is the desk view.

## Workflow

```bash
julia --project=. run.jl              # price the trade in inputs.toml, write output/*.csv
julia --project=. test/runtests.jl    # Shreve worked examples as tests
```

Then run `RefreshOutputs` in the workbook (see Excel below). Julia 1.10+. The charts
use Plots.jl (installed by `Pkg.instantiate()` from `Project.toml`); the pricing engine
itself uses only the standard library.

## Model

- Stock: `S(k, j) = S0 u^(k-j) d^j` after k steps with j down moves.
- No arbitrage requires `0 < d < 1 + r < u`; risk-neutral `p = (1 + r - d) / (u - d)`.
- Backward induction: `V = (p V_up + q V_down) / (1 + r)`; an American option takes
  the max of that and intrinsic value at every node.
- Time-0 hedge: `delta0 = (V_up - V_down) / (S_up - S_down)` shares and
  `cash0 = V0 - delta0 S0` in the money market.

## Inputs (`inputs.toml`)

`S0, u, d, r, n` (model), `K, option = "call"|"put", style = "european"|"american"`.

## Outputs (`output/`)

| File | Contents |
|---|---|
| `summary.csv` | inputs, p, value, European value, early-exercise premium, delta0, cash0 |
| `stock_tree.csv`, `option_tree.csv` | trees as matrices: rows = down moves, columns = steps |
| `exercise_tree.csv` | 1 where early exercise is optimal |
| `nodes.csv` | one row per node (step, down_moves, stock, option_value, intrinsic, exercise) |
| `stock_tree.png`, `option_tree.png` | tree charts on the same lattice; red stars mark nodes where early exercise is optimal |

## Excel

`Binomial Pricer.xlsm` is the desk view. Its data sheets are named after the CSVs in `output/`;
the Dashboard reads them with formulas and charts.

One-time setup:

1. Open `Binomial Pricer.xlsx`, then press Alt+F11 (Mac: Tools > Macro > Visual Basic Editor).
2. File > Import File > `RefreshEngineOutput.bas`.
3. Save As `Binomial Pricer.xlsm` (Excel Macro-Enabled Workbook) in this folder, next to `output/`.

After each engine run, run the macro `RefreshOutputs` (Alt+F8 / Tools > Macro > Macros).
It reloads every `output/*.csv` into the sheet of the same name and places any
`output/*.png` on an `Images` sheet. Only cell contents are replaced, so the
Dashboard formulas, formats and charts keep working.

## Layout

- `src/BinomialAssetPricing.jl`: model, trees, pricing, CSV writers
- `run.jl`: reads `inputs.toml`, prices, writes `output/`
- `charts.jl`: tree PNGs for `output/` (Plots.jl)
- `test/runtests.jl`: Shreve Sec. 1.1 one-period call, Example 4.2.1 American put,
  put-call parity
