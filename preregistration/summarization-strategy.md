# Summarization as an Alternative De-identification Strategy

## Why named-entity anonymization has a ceiling

The anonymization pipeline (12-rule named-entity replacement) achieves roughly 60% top-1
re-identification under current rules. The remaining identifiable cases are not failures of
named-entity coverage — the `.out` logs show correctly anonymized surface text — but rather
content fingerprints: distinctive constitutional arrangements, treaty relationships, electoral
structures, and patterns of repression that are unique to specific countries even after all
names are replaced. No additional named-entity rules can remove these because they are not
entity references; they are substantive descriptions of political facts.

Summarization addresses the fingerprint problem by replacing the source text with a
compressed, generic representation of the political conditions it describes, discarding
uniqueness-bearing details while preserving the evaluatively relevant content.

## What summarization does differently

Named-entity anonymization: `"The ruling [RULING PARTY] and the Republika Srpska entity
government frequently clashed with [NGO] monitors..."` — Bosnia still identifiable from
"two-entity structure" and "Dayton" analog phrasing.

Summarization target: `"The government operates under a power-sharing arrangement between
two major ethnopolitical factions. Civil society organizations face pressure from entity-level
authorities. Opposition parties have limited access to state media."` — generic enough to
match many consociational or post-conflict states.

The summarizer is not asked to replace entities but to distill the underlying political
situation into evaluatively sufficient but geographically non-specific language.

## Relationship to Benoit et al. (2026)

Benoit et al. use an almost identical two-stage design for party manifesto scaling: feed the
full original-language document to an LLM summarizer, receive a 300-400 word issue-targeted
English-language summary, then score that summary on a policy scale. Their key design
choices — confirmed through prototyping — map directly onto ours:

- **Per-indicator summaries outperform multi-indicator summaries**: they tested combined
  summaries and found dedicated per-issue summaries produced higher correlations with expert
  benchmarks. We should use per-indicator summarization, not a single generic summary.
- **300-400 words is the right length**: long enough to preserve evaluative content, short
  enough to eliminate uniqueness-bearing specifics. We should match this target.
- **Holistic summarization over the full assembled text**: they feed the full document, not
  sentences or sections, to the summarizer. We should feed the assembled evidence (all
  relevant sections from all sources combined) for the indicator, not section by section.
  This means the summary sees the full picture and can weigh sources coherently. Unlike
  anonymization, which caches at the section level to reuse shared sections across
  indicators, summarization must cache at the indicator level.
- **Fewer stages is better**: they found that inserting a translation step before
  summarization degraded performance. Implication for us: summarize directly from the raw
  assembled evidence, not from the anonymized version (no chaining).

The main difference: Benoit uses the summaries as an intermediate representation for
scoring (their step 4), while our summaries replace the source evidence as the direct
input to the coding model. The summarized text is then picked up by `assemble_prompt.py`
under the `"summarized"` and `"summarized-zeroshot"` conditions exactly as the anonymized
text is under `"anonymized"` and `"anonymized-zeroshot"`. Few-shot calibration examples
are handled by the existing downstream machinery and are not part of the summarization step.

Their leakage concern (identified in our commentary notes) is precisely our motivation:
the summaries may still encode political knowledge if the summarizer's pretraining
represents the country well. Our re-identification test is the empirical check on this.

## Prompt design

The summarization prompt should instruct the model to:

1. Summarize what the evidence says about [V-DEM INDICATOR LABEL] — the specific political
   dimension being coded — based only on the provided text
2. Express each condition at the level of abstraction a comparative politics analyst would
   use generically — e.g., "the executive controls judicial appointments" not "the president
   appoints all Constitutional Court members without parliamentary confirmation"
3. Omit or generalize structural details that carry no evaluative signal: specific treaty
   names, geographic arrangements, constitutional history, population composition
4. Replace all proper names (country, city, party, leader, organization) with generic
   descriptors; do not use any identifying labels
5. Preserve quantitative information and frequency descriptions that bear on the rating
   (e.g., "more than 200 journalists detained over three years")
6. Target length: 300-400 words (following Benoit et al.'s empirically validated target)

The generic variant (no indicator context) is worth testing as a baseline, but
indicator-targeted is the primary approach given Benoit's evidence that per-issue
outperforms multi-issue.

## What the experimental comparison looks like

The summarization strategy produces a third training-data variant alongside the two already
planned (raw and anonymized):

| Variant | Training text | Inference text |
|---------|--------------|----------------|
| Raw | Named text | Named text |
| Anon | Anonymized text | Anonymized text |
| Summary | Summarized text | Summarized text |

The re-identification test runs identically: present the summarized text to the model and
ask for country identification. A successful summarization strategy should yield top-1
re-identification well below 30% (approaching the chance level for ~150 countries, ~0.7%).

The downstream accuracy test runs identically: rate indicators from summarized evidence and
compare against V-Dem panel member ratings. The key trade-off is compression loss vs.
de-identification gain.

## Pipeline architecture

Unlike anonymization, which caches at the section level to share work across indicators,
summarization must operate at the **indicator level**: the summarizer needs the full
assembled evidence to produce a coherent, holistic summary that weighs all sources together.
Summarizing sections independently and then assembling them would produce fragmented output
and miss cross-source context — exactly the intermediate-stage degradation Benoit observed
when adding a translation step.

**Cache layout**: `data/processed-text/summarized/{year}/{iso}/{indicator}.txt`
(one file per country-year-indicator, not per section)

This increases LLM calls relative to anonymization (~11,500 per year vs. ~4,000), but there
is no shortcut: summarization is inherently a holistic compression task.

### New script: `pipeline/summarize_indicator.py`

Distinct from `anonymize_section.py` in structure:

- Accepts `iso`, `slug`, `year`, `indicator` arguments
- Calls `load_raw_for_indicator()` (equivalent to `load_anonymized_for_indicator()` but
  reading from the raw processed-text sections — no anonymization pass)
- Calls the LLM with the assembled evidence + indicator-targeted summarization prompt
- Caches result to `summarized/{year}/{iso}/{indicator}.txt`
- Flag `--variant [targeted|generic]` for indicator-specific vs. generic prompt
- Same OpenAI-compatible API call to Llama 70B local, temperature=0

### Batch runner integration

New `scripts/run_summarize.sh` (parallel to `run_anonymize.sh`) iterates over all
(country, year, indicator) triples. Can reuse the same SLURM array structure.

### Re-identification pipeline

`scripts/run_reidentify.sh` needs `--text-source [anonymized|summarized]` so the same
re-identification logic runs over either text type.

## Evaluation design

Run re-identification on the same 100 CYIs used in the anonymization test, substituting
summarized text. Compare:

| Metric | Anon result | Summary result |
|--------|-------------|----------------|
| Top-1 accuracy | ~58% (corrected) | target: < 30% |
| Top-3 accuracy | ~72% (corrected) | target: < 45% |
| Mean log-rank of true country | TBD | expect higher |

Also compare downstream coding accuracy (MAE vs. panel member ratings) between variants
to assess whether the de-identification gain comes at the cost of evaluative precision.

## Scope and sequencing

1. Write and test `summarize_section.py` on a handful of countries (3–5)
2. Inspect summaries manually: are the evaluatively relevant conditions preserved?
   Are the content fingerprints gone?
3. Run re-identification on the same 100-CYI sample
4. Decide on indicator-targeted vs. generic variant based on re-identification results
5. If re-identification drops below 30%: run full batch for FT-summary training data
6. Downstream accuracy comparison is then a three-way: FT-raw vs. FT-anon vs. FT-summary

The summarization pipeline is independent of the anonymization pipeline — both can remain
in production since the experimental design calls for comparing them.
