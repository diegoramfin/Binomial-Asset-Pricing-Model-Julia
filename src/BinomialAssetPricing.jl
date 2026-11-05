"""
Binomial asset pricing model (Shreve, *Stochastic Calculus for Finance I*,
ch. 1-4): European and American calls and puts on a recombining lattice
with up factor `u`, down factor `d` and one-period rate `r`.

Node `(k, j)` is time step `k` after `j` down moves:

    S(k, j) = S0 * u^(k-j) * d^j

Risk-neutral probabilities `p = (1 + r - d) / (u - d)`, `q = 1 - p`, and
backward induction

    V(k, j) = [p * V(k+1, j) + q * V(k+1, j+1)] / (1 + r)

with `V = max(intrinsic, continuation)` at every node for American options.
"""
module BinomialAssetPricing

export ModelParams, risk_neutral_prob, stock_tree, payoff, option_tree,
       price_option, write_outputs

"""
    ModelParams(S0, u, d, r, n)

Model inputs. Enforces the no-arbitrage condition `0 < d < 1 + r < u`.
"""
struct ModelParams
    S0::Float64
    u::Float64
    d::Float64
    r::Float64
    n::Int
    function ModelParams(S0, u, d, r, n)
        S0 > 0 || throw(ArgumentError("S0 must be positive (got $S0)"))
        0 < d < 1 + r < u || throw(ArgumentError(
            "no-arbitrage requires 0 < d < 1 + r < u (got d=$d, 1+r=$(1 + r), u=$u)"))
        n >= 1 || throw(ArgumentError("n must be at least 1 (got $n)"))
        new(S0, u, d, r, n)
    end
end

"""Risk-neutral probability of an up move: `p = (1 + r - d) / (u - d)`."""
risk_neutral_prob(m::ModelParams) = (1 + m.r - m.d) / (m.u - m.d)

"""
    stock_tree(m) -> Matrix{Float64}

`(n+1) x (n+1)` matrix with `S[j+1, k+1] = S0 u^(k-j) d^j` for `j <= k`
(rows = down moves, columns = time steps); `NaN` where no node exists.
"""
function stock_tree(m::ModelParams)
    S = fill(NaN, m.n + 1, m.n + 1)
    for k in 0:m.n, j in 0:k
        S[j+1, k+1] = m.S0 * m.u^(k - j) * m.d^j
    end
    return S
end

"""Intrinsic value of a `:call` or `:put` struck at `K`."""
function payoff(option::Symbol, S::Real, K::Real)
    option === :call && return max(S - K, 0.0)
    option === :put && return max(K - S, 0.0)
    throw(ArgumentError("option must be :call or :put (got $option)"))
end

"""
    option_tree(m, K, option, style) -> (V, exercise)

Backward induction on the lattice. `style` is `:european` or `:american`.
`V` has the same layout as [`stock_tree`](@ref). `exercise[j+1, k+1]` is
`true` where early exercise is optimal (American only, `k < n`, in the
money and intrinsic value at least the continuation value).
"""
function option_tree(m::ModelParams, K::Real, option::Symbol, style::Symbol)
    style in (:european, :american) ||
        throw(ArgumentError("style must be :european or :american (got $style)"))
    S = stock_tree(m)
    p = risk_neutral_prob(m)
    disc = 1 / (1 + m.r)
    V = fill(NaN, m.n + 1, m.n + 1)
    exercise = falses(m.n + 1, m.n + 1)
    for j in 0:m.n
        V[j+1, m.n+1] = payoff(option, S[j+1, m.n+1], K)
    end
    for k in (m.n-1):-1:0, j in 0:k
        cont = disc * (p * V[j+1, k+2] + (1 - p) * V[j+2, k+2])
        if style === :american
            intrinsic = payoff(option, S[j+1, k+1], K)
            exercise[j+1, k+1] = intrinsic > 0 && intrinsic >= cont
            V[j+1, k+1] = max(intrinsic, cont)
        else
            V[j+1, k+1] = cont
        end
    end
    return V, exercise
end

"""
    price_option(m, K, option, style) -> NamedTuple

Time-0 value plus the quantities reported to the desk: the European value
of the same contract, the early-exercise premium, and the time-0
replicating portfolio (`delta0` shares, `cash0` in the money market).
"""
function price_option(m::ModelParams, K::Real, option::Symbol, style::Symbol)
    S = stock_tree(m)
    V, exercise = option_tree(m, K, option, style)
    Ve, _ = option_tree(m, K, option, :european)
    delta0 = (V[1, 2] - V[2, 2]) / (S[1, 2] - S[2, 2])
    return (p=risk_neutral_prob(m), value=V[1, 1], european_value=Ve[1, 1],
            early_exercise_premium=V[1, 1] - Ve[1, 1],
            delta0=delta0, cash0=V[1, 1] - delta0 * m.S0,
            S=S, V=V, exercise=exercise)
end

# ---------------------------------------------------------------- output

_fmt(x::AbstractFloat) = isnan(x) ? "" : isinteger(x) && abs(x) < 1e15 ? string(Int(x)) : string(x)
_fmt(::Nothing) = ""
_fmt(x) = string(x)

function _write_csv(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join(_fmt.(row), ","))
        end
    end
    return path
end

function _write_tree(path, M)
    n = size(M, 2) - 1
    header = vcat("down_moves", ["step_$k" for k in 0:n])
    rows = [Any[j; [M[j+1, k+1] for k in 0:n]] for j in 0:n]
    return _write_csv(path, header, rows)
end

"""
    write_outputs(dir, m, K, option, style, res) -> Vector{String}

Write `summary.csv` (field,value), `stock_tree.csv`, `option_tree.csv`
and `exercise_tree.csv` (1 = exercise early) to `dir`, plus `nodes.csv`:
one row per node (step, down_moves, stock, option_value, intrinsic, exercise),
the long format that spreadsheets chart easily.
"""
function write_outputs(dir, m::ModelParams, K, option, style, res)
    mkpath(dir)
    summary = [
        ("S0", m.S0), ("u", m.u), ("d", m.d), ("r", m.r), ("n", m.n),
        ("K", K), ("option", option), ("style", style),
        ("risk_neutral_p", res.p), ("risk_neutral_q", 1 - res.p),
        ("value", res.value), ("european_value", res.european_value),
        ("early_exercise_premium", res.early_exercise_premium),
        ("delta0", res.delta0), ("cash0", res.cash0),
        ("early_exercise_nodes", count(res.exercise)),
    ]
    ex = Matrix{Any}(nothing, m.n + 1, m.n + 1)   # blank = no node at (k, j)
    for k in 0:m.n, j in 0:k
        ex[j+1, k+1] = Int(res.exercise[j+1, k+1])
    end
    return [
        _write_csv(joinpath(dir, "summary.csv"), ["field", "value"], summary),
        _write_tree(joinpath(dir, "stock_tree.csv"), res.S),
        _write_tree(joinpath(dir, "option_tree.csv"), res.V),
        _write_tree(joinpath(dir, "exercise_tree.csv"), ex),
        _write_csv(joinpath(dir, "nodes.csv"),
            ["step", "down_moves", "stock", "option_value", "intrinsic", "exercise"],
            [(k, j, res.S[j+1, k+1], res.V[j+1, k+1], payoff(option, res.S[j+1, k+1], K),
              Int(res.exercise[j+1, k+1])) for k in 0:m.n for j in 0:k]),
    ]
end

end # module
