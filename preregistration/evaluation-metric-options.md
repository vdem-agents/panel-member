# Evaluation metric options for AI-vs-human panel comparison

## Background

For each country-year-indicator (CYI) in the evaluation set, a panel of human coders (average ~8) each provides an ordinal rating on a 0–4 scale. The AI provides one rating per CYI. V-Dem's actual country-year scores are produced by a Bayesian IRT model that pools individual coder ratings while accounting for coder-level reliability and threshold idiosyncrasies — the raw panel mean is not what V-Dem reports. This study uses the raw panel mean as the evaluation reference because it is a tractable and interpretable proxy for the panel consensus and because the IRT model is not the target of the substitution claim. The evaluation question is: how closely does the AI approximate the panel consensus, relative to how closely individual human coders approximate it?

---

## Option 1: AI deviation vs. human leave-one-out (LOO) baseline

- AI side: |AI_rating − panel_mean| per CYI, averaged across CYIs
- Human side: for each coder i, |rating_i − mean(panel excluding i)|, averaged across all coders and CYIs

The LOO correction removes self-influence from the human baseline: each human coder is excluded from the mean they are being compared against, because including them would pull the mean toward their own rating and make their deviation appear artificially small.

This creates an asymmetry: the AI is compared against the full panel mean, while humans are compared against an n−1 coder mean. The human LOO baseline is exactly n/(n−1) times larger than it would be without the LOO correction. For a panel of 8, the LOO baseline is 14% larger than the full-panel baseline; for a panel of 5 it is 25% larger. This means the LOO baseline is slightly easier for the AI to beat than the full-panel baseline would be.

The term "AI LOO MAE" is sometimes used in this context but is a misnomer, since the AI was never a panel member and is not being left out of anything.

---

## Option 2: Synthetic AI LOO

- For each fold (each held-out human coder i), evaluate the AI as if it were the held-out coder:
  - AI side: |AI_rating − mean(panel excluding i)| for each fold, averaged across all i and CYIs
  - Human side: |rating_i − mean(panel excluding i)| — standard LOO

Both sides use the same n−1 reference mean for each fold, making the comparison fully symmetric.

A notable property of this approach: even an AI that perfectly matches the full panel mean will show non-zero synthetic LOO MAE, because the n−1 subset means differ from the full panel mean. The measure is therefore sensitive to within-panel variance in a way that is independent of how well the AI actually tracks the consensus. The synthetic AI LOO MAE converges to the simple AI deviation (Option 3) as panel size grows.

---

## Option 3: Both against the full panel mean

- AI side: |AI_rating − panel_mean| per CYI, averaged across CYIs
- Human side: mean of |rating_i − panel_mean| across all coders per CYI, averaged across CYIs

Same target, same metric, directly symmetric. This is the standard approach in the NLP multi-annotator evaluation literature, where the aggregate human annotation (mean or majority vote) is treated as the reference label and both model and individual human annotators are measured against it.

The self-influence issue applies here: each human coder's rating is included in the panel mean they are being compared against, which slightly deflates their apparent deviation. This makes the human baseline slightly smaller — and therefore slightly easier for the AI to match — compared to the LOO baseline. The magnitude is the inverse of the Option 1 inflation: the full-panel human baseline is (n−1)/n times the LOO baseline, so 14% smaller for n=8 and 25% smaller for n=5.

---

## Summary of tradeoffs

| | Asymmetry | Self-influence | Direction of bias for AI | Complexity |
|---|---|---|---|---|
| Option 1 (LOO) | Yes — different reference for AI vs. human | Corrected for humans | Slightly favorable (easier to beat) | Moderate |
| Option 2 (Synthetic LOO) | No | Corrected for both | Slightly unfavorable (harder to beat) | High |
| Option 3 (Full panel mean) | No | Present for humans | Slightly favorable (easier to beat) | Low |

In Options 1 and 3, the bias runs in the same direction: the human baseline is either inflated (Option 1) or deflated (Option 3) relative to the symmetric ideal, making it slightly easier for the AI to match. The magnitude of this bias shrinks as panel size grows and is bounded by the n/(n−1) factor.

---

## Decision (2026-09-21): Option 1

**Option 1 is the registered and reported metric.** Options 2 and 3 get a footnote in §4 and a
robustness row in the appendix. Full reasoning, with the measured cost of each alternative, is in
`notes/loo-benchmark-metric-decision.md`; this section records the conclusion and the principle.

### The principle that picks it

The substantive question posed below — prediction target vs. AI-in-each-panel-position — resolves
on a prior question: *is the rater being scored inside the target they are scored against?*

```
AI     |AI rating − mean of all n coders|        the AI is not one of them
Opt 1  |rating_i  − mean of the other n−1|       coder i is not one of them
Opt 3  |rating_i  − mean of all n, i included|   coder i IS one of them
```

The AI's error is already a leave-one-out quantity: leaving the AI out of the panel mean changes
nothing, because it was never in. So its human counterpart must also be a leave-one-out error.
Option 1 matches on that property. Option 3 matches only on *which number is used*, which is
arithmetic coincidence rather than a structural match. This is the argument in
`preregistration-draft.md`: a human "in a directly analogous position to the AI, i.e. rating an
indicator as a non-panel member."

### Correcting the table above

The "Direction of bias for AI" column marks **Option 3 as "slightly favorable (easier to beat)".
That is backwards.** A smaller human baseline is a *stricter* bar for the AI to come in under.
Measured on the 2019 pool: Option 1's benchmark is 0.708, Option 3's is 0.609, with the AI side
identical in both. Under Option 3 all six FT-raw greedy cells land above the line where five of
six sit below it under Option 1 — a verdict flip on D1. Option 1's row is right: inflating the
human baseline is genuinely favourable to the AI.

### The cost of each alternative, measured

**Option 3.** Benchmark drops 0.708 → 0.609 (the n/(n−1) factor, mean 1.163 across the pool).
Flips D1 on greedy. Raises Figure 4's difficulty slopes ~18% — but only because redefining human
error also re-pins the reference at 1; change the difficulty axis alone and the reference becomes
1.2517, moving the ratio 0.794 → 0.751.

**Option 2.** The human side is *identical* to Option 1's, so the benchmark line does not move at
all. Across all 18 figure cells the AI points shift +0.004 to +0.009 and the slopes +0.006 to
+0.023; two borderline cells cross the line by under 0.001; condition contrasts move ~0.001
against a SESOI of 0.115; Figure 5 is exactly invariant (signed deviations have no absolute value,
so the LOO means average back to the panel mean). The objection is not size but selectivity: the
Jensen penalty lands only on predictions close to consensus, so the fractional persistence rail
takes +0.0734 where the models take +0.005. Option 2 charges precision.

### The paragraph below is preserved as originally written

## Open question

All three options are defensible. The substantive question is whether the panel mean should be treated as the prediction target (Options 1 and 3, where the AI is compared against it directly) or whether the right comparison is AI-in-each-panel-position (Option 2). Option 3 is the simplest and most standard in computational annotation work. Option 1 is more common in small-n evaluation settings where self-influence is a concern. Option 2 is the most symmetric but the hardest to explain and has a counterintuitive property for perfect predictions.
