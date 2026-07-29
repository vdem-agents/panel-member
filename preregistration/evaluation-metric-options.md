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

## Open question

All three options are defensible. The substantive question is whether the panel mean should be treated as the prediction target (Options 1 and 3, where the AI is compared against it directly) or whether the right comparison is AI-in-each-panel-position (Option 2). Option 3 is the simplest and most standard in computational annotation work. Option 1 is more common in small-n evaluation settings where self-influence is a concern. Option 2 is the most symmetric but the hardest to explain and has a counterintuitive property for perfect predictions.
