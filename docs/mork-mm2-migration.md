# MORK/MM2 migration boundary

The current work is split into two MORK branches:

- `mm2-generic-runtime` is based on `upstream/main` and contains only generic
  runtime facilities intended for upstream review.
- `mm2-pln-runtime` is stacked on the generic branch and retains the remaining
  PLN-specific formulas, evidence semantics, proof revision, and distribution
  operations behind MORK's `pln` feature.

## Generic MORK facilities

The upstream-oriented branch currently provides:

- `head` and `tail` input sources;
- ordered `group-collect` into canonical `pcons` lists;
- explicitly ordered grouped floating-point reductions;
- ordered vector floating-point sums through `vfsum`;
- parameterized binomial-estimate, product/ratio variance, and
  confidence-from-variance numerical primitives;
- compact `Display` formatting for floating-point results;
- initialized substitution buffers for aggregate sinks.

`group-collect` has the form:

```text
(group-collect OUTPUT RESULT-SLOT GROUP asc|desc ORDER ITEM)
```

`vfsum` has the form:

```text
(vfsum OUTPUT RESULT-SLOT (VALUE ...) ORDER)
```

Both group by the grounded output/result template and use the explicit order
term to make floating-point aggregation and proof construction deterministic.

## Moved into MM2

The MM2 runtime now owns:

- modus-ponens strength arithmetic;
- negative-branch strength arithmetic;
- And, Or, and marginal-projection scalar arithmetic.

The corresponding native MORK operators have been removed from the PLN branch.

The unguarded base-rate fold was also translated to MM2 as an experiment, then
reverted after the base-rate-heavy fixture regressed by about 11%. Both guarded
and unguarded folds therefore remain in the custom `fold-base-rate` sink. The
generic `vfsum` facility added for that experiment remains useful and belongs
on the upstream-oriented branch.

## Benchmark checkpoints

All values below are gross medians in milliseconds. They include PeTTa process
startup for harness fixtures, so comparisons use identical five-run commands
and should be interpreted as directional rather than microbenchmarks.

| Checkpoint | STV implication | Base-rate cache |
|---|---:|---:|
| Before MM2 base-rate fold | 1434 | 1615 |
| MM2 fold with two scalar reductions | 1473 | 1807 |
| MM2 fold with one `vfsum` | 1462 | 1820 |
| Plus MM2 negative-branch strength | 1458 | 1796 |
| Base-rate MM2 fold reverted | 1475 | 1783 |

The light implication case regressed about 2%, while the deliberately
base-rate-heavy cache fixture regressed about 11%. Combining the reducers did
not materially change that result, showing that additional MM2 phases and
intermediate atoms dominate the cost rather than repeated scanning inside the
reduction sink.

The generic direct-MORK first-answer benchmark showed no meaningful idle cost
from registering `group-collect`: chain depth 4 changed from 183 to 182 ms,
chain depth 8 from 298 to 294 ms, and adapter width 8 from 161 to 160 ms.

After translating the five projection helpers, five-run gross medians were
2592 ms for `test_backward_dag_helpers` and 1941 ms for `test_logic_config`.
Those are below the last stored corpus samples (2669 and 1972 ms), so this
conversion shows no evidence of a slowdown, although the stored samples are
not a controlled paired benchmark.

An inversion-formula translation was rejected and reverted. In five-run
measurements, `test_idealized_confidence` increased from 2039 to 2391 ms
(about 17%) and `test_implication_inversion` from 1475 to 1703 ms (about 15%).
The process baseline also drifted upward, but the formula-heavy fixture's
baseline-subtracted median still increased from 581 to 765 ms. The generic
uncertainty primitives remain on the upstream-oriented branch, while the
compact PLN inversion operator remains in the PLN extension.

## Remaining custom PLN boundary

Good next migration candidates are scalar confidence/projection formulas once
their repeated subexpressions can be named without adding many runtime phases.
The following should remain custom until stronger generic facilities exist:

- inversion confidence and consistency, until MM2 supports local bindings or
  fused formula evaluation without nested interpreter overhead;
- guarded alpha-equivalent evidence filtering;
- shared-evidence proof factoring, which evaluates proof graphs against a
  consistent fact/proof snapshot and counterfactual premise overrides;
- distribution Cartesian convolution if an MM2 implementation proves too
  expensive;
- evidence-aware conjunction pooling until generic canonical set operations
  are available.

Pair-count, Or, and total-evidence aggregation also need a generic way to turn
dynamic `pcons` lists into variadic expressions and to substitute a computed
value into a stored output template. Those should be generic MORK expression
facilities rather than more PLN-named sinks.
