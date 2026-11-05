# Price the option described in inputs.toml and write CSVs to output/.
#
#   julia --project=. run.jl [inputs.toml]

using BinomialAssetPricing, TOML, Printf
include(joinpath(@__DIR__, "charts.jl"))

cfg = TOML.parsefile(get(ARGS, 1, joinpath(@__DIR__, "inputs.toml")))
m = ModelParams(cfg["S0"], cfg["u"], cfg["d"], cfg["r"], cfg["n"])
K, option, style = cfg["K"], Symbol(cfg["option"]), Symbol(cfg["style"])

res = price_option(m, K, option, style)
outdir = joinpath(@__DIR__, "output")
files = write_outputs(outdir, m, K, option, style, res)
info = @sprintf("%s %s, K=%.4g, S0=%.4g, u=%.4g, d=%.4g, r=%.4g, n=%d",
                style, option, K, m.S0, m.u, m.d, m.r, m.n)
charts = save_tree_charts(outdir, res, info)

@printf("%s %s, K = %.4g, n = %d\n", style, option, K, m.n)
@printf("  value                  %.6f\n", res.value)
@printf("  european value         %.6f\n", res.european_value)
@printf("  early-exercise premium %.6f\n", res.early_exercise_premium)
@printf("  delta0 / cash0         %.6f / %.6f\n", res.delta0, res.cash0)
println("Wrote ", join(basename.(vcat(files, charts)), ", "), " to output/")
