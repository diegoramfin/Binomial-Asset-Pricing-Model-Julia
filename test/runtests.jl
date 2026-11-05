using BinomialAssetPricing
using Test

@testset "inputs" begin
    @test_throws ArgumentError ModelParams(100.0, 1.1, 0.95, 0.10, 2)  # 1+r > u
    @test_throws ArgumentError ModelParams(0.0, 1.2, 0.8, 0.05, 2)
    @test_throws ArgumentError ModelParams(100.0, 1.2, 0.8, 0.05, 0)
    @test risk_neutral_prob(ModelParams(100.0, 1.2, 0.8, 0.05, 3)) ≈ 0.625
end

@testset "stock tree" begin
    S = stock_tree(ModelParams(100.0, 1.2, 0.8, 0.05, 2))
    @test S[1, 1] == 100.0
    @test S[1:2, 2] ≈ [120.0, 80.0]
    @test S[1:3, 3] ≈ [144.0, 96.0, 64.0]
    @test isnan(S[2, 1])
end

# Shreve vol. I running example: S0 = 4, u = 2, d = 1/2, r = 1/4, p = q = 1/2.
const SHREVE = ModelParams(4.0, 2.0, 0.5, 0.25, 1)

@testset "Shreve one-period call (Sec. 1.1)" begin
    res = price_option(SHREVE, 5.0, :call, :european)
    @test res.p ≈ 0.5
    @test res.value ≈ 1.20            # V0 = 1.20
    @test res.delta0 ≈ 0.5            # hedge with 1/2 share
    @test res.cash0 ≈ 1.20 - 2.0      # borrow 0.80
end

@testset "Shreve American put (Example 4.2.1)" begin
    m = ModelParams(4.0, 2.0, 0.5, 0.25, 2)
    res = price_option(m, 5.0, :put, :american)
    @test res.value ≈ 1.36
    @test res.exercise[2, 2]          # exercise at S1 = 2
    @test res.early_exercise_premium > 0
end

@testset "European prices match the binomial sum" begin
    m = ModelParams(100.0, 1.2, 0.8, 0.05, 6)
    p = risk_neutral_prob(m)
    for (opt, K) in ((:call, 100.0), (:put, 105.0))
        direct = sum(binomial(m.n, j) * p^(m.n - j) * (1 - p)^j *
                     payoff(opt, m.S0 * m.u^(m.n - j) * m.d^j, K)
                     for j in 0:m.n) / (1 + m.r)^m.n
        @test price_option(m, K, opt, :european).value ≈ direct
    end
end

@testset "put-call parity and American call = European call" begin
    m = ModelParams(100.0, 1.2, 0.8, 0.05, 5)
    K = 105.0
    c = price_option(m, K, :call, :european).value
    p = price_option(m, K, :put, :european).value
    @test c - p ≈ m.S0 - K / (1 + m.r)^m.n
    # no dividends and r > 0: never optimal to exercise a call early
    ac = price_option(m, K, :call, :american)
    @test ac.value ≈ c
    @test ac.early_exercise_premium ≈ 0 atol = 1e-12
    @test count(ac.exercise) == 0
end
