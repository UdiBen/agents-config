# Vega-Lite chart choices

Read this reference when the conclusion depends on measured magnitude, change, distribution,
correlation, or uncertainty. It compares tables with charts, so loading it does not make `Chart`
plausible or preferred. Start from the question the reviewer must answer, then fetch the generated
`Chart` contract only if that component is selected. These are examples and tie-breakers, not an
exhaustive list of valid Vega-Lite views.

| Example question | Strong starting point |
|---|---|
| Which category or revision is larger? | sorted bars; points or ticks for a few values |
| How does a value change over time, payload size, concurrency, attempts, or releases? | line; area when magnitude or total matters |
| What is the shape of one distribution? | histogram or strip plot |
| How do repeated-run distributions or tails compare? | box plot or precomputed ECDF |
| Do two measured variables correlate or cluster? | scatter plot |
| Where is intensity high across two dimensions? | rect heatmap |
| What interval, stage duration, or request waterfall changed? | ranged bar |
| Where are thresholds or notable events? | rules or ticks |
| How uncertain or variable is the estimate? | error bars, error bands, intervals, or raw points |
| How do parts contribute to a total? | stacked bars or areas; arc for a few clearly distinct slices |
| Where does a measured value occur geographically? | geoshape when location is part of the evidence |
| What are the exact p50, p95, p99, pass/fail, or supported states? | Markdown table, optionally beside a chart |

Prefer a table when exact lookup or categorical state is the point, a chart when the pattern is the
point, and both when the reviewer needs the pattern and exact values. Another valid view may be
better when the measurements and surrounding explanation call for it.

A small before/after matrix with one named exception often starts stronger as a table: every cell is
visible, the exception can be emphasized, and no scale competes with exact lookup. Choose a heatmap
only when the two-dimensional pattern is materially easier to see than to scan and its color scale
keeps every decision-relevant difference visible. Tooltips may add detail, but do not make the
primary evidence hover-only.

Choose the comparison quantity before the mark. Absolute delta answers “how much time or cost was
saved?” Percentage or ratio answers “how large was the change relative to its baseline?” Raw old/new
values answer exact before/after lookup. Label derived values and name their denominator. Percentage
or ratio needs a nonzero baseline whose sign and magnitude make the comparison meaningful; for zero,
near-zero, or sign-changing baselines, prefer raw values and signed delta unless the domain defines a
clearer convention. Do not substitute one claim for another merely because it charts more
dramatically. With a diverging scale, check whether an extreme on one side compresses material
changes on the other; normalize, facet, annotate, or use a table when it does.

Setting `zero: false` does not fix a linear view when a distant outlier still compresses the main
cluster. Choose a scale or composition that keeps both the cluster and tail legible, or use a table
when no honest compact chart does so.

Do not connect unrelated categories. Make a non-zero or logarithmic axis explicit when it is
essential. Never invent measurements or imply unsupported precision. Name the compared revisions
and the methodology details that materially affect interpretation, such as workload, environment,
concurrency, warmup, run count, aggregation, or uncertainty.

Render-check every nontrivial `Chart`: this includes layers, transforms, parameters, custom,
logarithmic, or diverging scales, geographic or image marks, and any density or label layout that
could hide the claim. Structural validation is not a render check. A simple single-view chart with a
standard scale may use source inspection when the contract and request do not require more.

Keep Vega-Lite-native composition in `Chart`. Use `Html` when the required coordination,
specialization, or interaction exceeds the generated `Chart` contract.
