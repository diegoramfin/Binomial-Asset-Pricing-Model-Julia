# Tree charts for output/: the stock tree and the option value tree, drawn on
# the same lattice so they line up node for node. Nodes where early exercise
# is optimal are marked red on both charts.
#
# Needs Plots.jl (GR backend). Loaded by run.jl; the engine module does not use it.

ENV["GKSwstype"] = "100"   # GR: write files without opening a window
using Plots, Printf

# Node (k, j): x = step k, y = up moves minus down moves (k - 2j).
# An up move goes to (k+1, j), a down move to (k+1, j+1).
_pos(k, j) = (k, k - 2j)

function _tree_chart(M::AbstractMatrix, exercise::AbstractMatrix{Bool},
                     title::AbstractString, path::AbstractString)
    n = size(M, 1) - 1
    plt = plot(; title = title, xlabel = "step k", ylabel = "up moves - down moves",
               xticks = 0:n, legend = :topleft, grid = false, size = (max(640, 120 * (n + 1)), 520),
               xlims = (-0.5, n + 0.5), ylims = (-n - 1.5, n + 1.5))

    for k in 0:n-1, j in 0:k
        x0, y0 = _pos(k, j)
        for jc in (j, j + 1)
            _, y1 = _pos(k + 1, jc)
            plot!(plt, [x0, x0 + 1], [y0, y1]; color = :gray60, linewidth = 1, label = "")
        end
    end

    nodes = [(k, j) for k in 0:n for j in 0:k]
    pts = _pos.(first.(nodes), last.(nodes))
    scatter!(plt, first.(pts), last.(pts); color = :steelblue, markersize = 5, label = "")
    for ((k, j), (x, y)) in zip(nodes, pts)
        annotate!(plt, x, y + 0.5, text(@sprintf("%.2f", M[j+1, k+1]), 7, :center))
    end

    ex = [(k, j) for (k, j) in nodes if exercise[j+1, k+1]]
    if isempty(ex)
        title!(plt, title * "\nno early-exercise nodes")
    else
        ex_pts = _pos.(first.(ex), last.(ex))
        scatter!(plt, first.(ex_pts), last.(ex_pts); color = :red, markershape = :star5,
                 markersize = 9, label = "early exercise optimal")
    end

    savefig(plt, path)
    return path
end

"""
    save_tree_charts(dir, res, info) -> Vector{String}

Write `stock_tree.png` and `option_tree.png` to `dir` from the result of
`price_option`. `info` is a short description put in the chart titles.
"""
function save_tree_charts(dir::AbstractString, res, info::AbstractString)
    mkpath(dir)
    stock = _tree_chart(res.S, res.exercise, "Stock price tree\n" * info,
                        joinpath(dir, "stock_tree.png"))
    option = _tree_chart(res.V, res.exercise, "Option value tree\n" * info,
                         joinpath(dir, "option_tree.png"))
    return [stock, option]
end
