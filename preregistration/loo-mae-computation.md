# LOO MAE: Construction and Bootstrap Unit

## Construction

For each country-year-indicator (CYI):

- **Human LOO MAE** = (1/n) × Σᵢ |rating_i − mean(panel \ {i})|
- **AI deviation** = |AI_rating − panel_mean|
- **Difference** = AI deviation − human LOO MAE

The difference is computed at the CYI level, then aggregated across CYIs. Bootstrap CIs are drawn at the CYI level (resample CYIs with replacement).

## Ordering doesn't matter within a CYI

You could equivalently compute (AI_dev − human_dev_i) for each coder and then average across coders. Because AI_dev is constant within a CYI, mean(AI_dev − human_dev_i) = AI_dev − mean(human_dev_i). The two orderings are algebraically identical.

## Efficient computation of mean(panel \ {i})

The naive approach recomputes the panel mean n times (O(n²) per CYI). The standard trick reduces this to O(n):

```python
panel_sum = ratings.sum()
loo_mean_i = (panel_sum - rating_i) / (n - 1)
```

## Why bootstrap at the CYI level, not the coder level

Bootstrapping at the coder level (pooling all individual deviations across CYIs) produces anti-conservative confidence intervals for two reasons:

1. **Within-CYI correlation**: coders in the same panel are not independent — they are rating the same country-year. Treating them as independent understates variance.
2. **Implicit up-weighting of large panels**: panels with more coders contribute more observations to the pool, so high-n CYIs receive disproportionate weight in the bootstrap.

The CYI is the natural unit of observation: one AI rating, one human LOO MAE, one comparison. Bootstrap at that level to weight each CYI equally and respect clustering.
