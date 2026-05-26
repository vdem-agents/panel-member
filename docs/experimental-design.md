# Panel Member: Experimental Design

## Framing: What kind of experiment is Stage 1?

Stage 1 is a **randomized factorial experiment on measurement instrument properties** —
specifically, which rater calibration choices produce LLM outputs that most closely
approximate the human expert panel.

This is not a conjoint experiment. In standard conjoint (HHY), randomized attributes
describe the *stimulus* — the candidate or product being evaluated. Here, randomized
attributes describe the *rater* — the LLM's persona. The object being evaluated
(the country-year's democratic conditions) does not change across configurations. The
AMCE is therefore not the estimand. The estimand is the **average causal effect of each
persona attribute level on coding deviation**, identified by randomization (Rubin 1974;
Holland 1986), not by HHY's AMCE machinery.

The fractional factorial design tools from the conjoint literature (D-efficiency,
orthogonality, interaction detection) apply directly. The identification logic and
the interpretation of coefficients do not require the conjoint framing.

---

## Design

### Attribute set and levels

| Attribute | Levels | Outcome | Predicted direction |
|---|---|---|---|
| `threshold` | strict / neutral / lenient | signed | strict → negative; lenient → positive |
| `reliability` | high / standard | absolute | high → lower |
| `conception` | liberal / majoritarian / participatory / deliberative | signed | indicator-specific (see below) |
| `domestic` | domestic expert / international observer | signed | domestic → negative |
| `diligence` | careful / standard | absolute | careful → lower |
| `packet` | full / partial / minimal | absolute | full → lower |
| `source` | state_dept / state_and_fh | TBD | to be determined |
| `examples` | none / neutral synthetic / calibration-matched | both | see below |

**Total levels**: 3 × 2 × 4 × 2 × 2 × 3 × 2 × 3 = 1,296 (full factorial — do not run all)

### Design matrix generation

Use R `AlgDesign` or `DoE.base` to generate a D-optimal fractional factorial.

**Recommended approach (Option 2 from identification memo)**: generate randomly and
verify orthogonality, redrawing until all pairwise attribute correlations |r| < 0.2.
This is equivalent to Option 1 in practice but easier to explain to political science
reviewers familiar with HHY-style randomization.

```r
library(AlgDesign)

factors <- expand.grid(
  threshold   = c("strict", "neutral", "lenient"),
  reliability = c("high", "standard"),
  conception  = c("liberal", "majoritarian", "participatory", "deliberative"),
  domestic    = c("domestic", "international"),
  diligence   = c("careful", "standard"),
  packet      = c("full", "partial", "minimal"),
  source      = c("state_dept", "state_and_fh"),
  examples    = c("none", "neutral", "calibration_matched")
)

# D-optimal fractional factorial: 48 runs for main effects only
design <- optFederov(
  ~ threshold + reliability + conception + domestic +
    diligence + packet + source + examples,
  data = factors, nTrials = 48, criterion = "D"
)

# If pre-specifying source × domestic interaction: nTrials = 64, add interaction term
# design <- optFederov(
#   ~ threshold + reliability + conception + domestic +
#     diligence + packet + source + examples + source:domestic,
#   data = factors, nTrials = 64, criterion = "D"
# )
```

Save `design$design` to `data/processed/design_matrix.csv` — this is the
pre-registration artifact. Do not modify after running any LLM calls.

### Country-year pool

N_cy = 30–50 country-years with ≥ 8 distinct coders, drawn from 2010–2019
(~130–175 eligible per year; subsampling is trivial). The **same pool** runs across
all configurations — this is the complete-matrix design that enables country-year
fixed effects in the regression at no additional cost.

**Sampling**: stratify by country's latent democracy level (quintiles from v15 θ_ct)
to ensure the pool spans the full ordinal range. This ensures Tier 1b compression
diagnostics are interpretable.

Lock the pool before generating the design matrix. Total LLM calls: 48 configs × 40
CYs = 1,920 calls (~$20–40 frontier API).

---

## Outcome Variables

Use two outcomes in parallel — do not combine. Each attribute should be evaluated
against its theoretically appropriate outcome.

### Outcome 1: Signed deviation (directional attributes)

```
signed_deviation = AI_rating − human_panel_mean
```

Range: −4 to +4 for a 0–4 ordinal scale. Positive = lenient relative to panel;
negative = strict.

**Pre-registered directional predictions** (lock before running):

| Attribute level | Predicted sign | Rationale |
|---|---|---|
| `threshold = strict` | negative | Strict coder rates below panel mean |
| `threshold = lenient` | positive | Lenient coder rates above panel mean |
| `domestic = domestic` | negative | Domestic framing → harsher ratings (V-Dem empirical finding) |
| `examples = calibration_matched strict` | negative | Anchors toward lower end of scale |
| `examples = calibration_matched lenient` | positive | Anchors toward upper end of scale |
| `conception = liberal` (on `v2csreprss`) | negative | Liberal conception emphasizes constraints → stricter on repression |

Directional predictions for `conception` are indicator-specific and must be worked out
theoretically before pre-registration. Liberal conception on civil society repression
(v2csreprss): predicts negative (stricter). Majoritarian: unclear — resolve before locking.

### Outcome 2: Absolute deviation (precision attributes)

```
abs_deviation = |AI_rating − human_panel_mean|
```

Range: 0 to 4. Lower = closer to the panel aggregate.

**Attributes evaluated on absolute deviation**:
- `reliability`: high → lower absolute deviation
- `diligence`: careful → lower absolute deviation  
- `packet`: full → lower absolute deviation

**Note on `examples`**: the calibration-matched example condition has both a directional
prediction (signed deviation) and a precision prediction (the example anchoring should
also reduce absolute deviation in the matched direction). Report both.

---

## Attribute Operationalization

The exact prompt text for each attribute level. These are the strings injected into
the prompt; lock them before pre-registration.

### `threshold`

**`strict`**:
```
Apply a strict standard. Require clear, consistent evidence before assigning higher
categories. When evidence is mixed or ambiguous, assign the lower category.
```

**`neutral`**: [omit threshold instruction — baseline condition]

**`lenient`**:
```
Give countries the benefit of the doubt. When evidence is mixed or ambiguous, assign
the higher category. Consider formal institutional arrangements alongside documented
violations.
```

### `reliability`

**`high`**:
```
Rate each indicator independently. Read the evidence carefully before responding.
Do not anchor your rating on your response to a previous indicator.
```

**`standard`**: [omit reliability instruction]

### `conception`

**`liberal`**:
```
Understand democracy as a system protecting individual rights and civil liberties
against state encroachment. Free and fair elections are necessary but not sufficient;
individual freedoms and rule of law matter equally.
```

**`majoritarian`**:
```
Understand democracy as popular sovereignty expressed through elections. Elected
governments with strong mandates have democratic legitimacy to act decisively.
```

**`participatory`**:
```
Understand democracy as requiring active citizen engagement beyond elections —
through civil society organizations, local governance, and direct participation.
```

**`deliberative`**:
```
Understand democracy as requiring that political decisions emerge from reasoned public
debate, not just from vote counts. The quality of deliberation matters as much as
its outcome.
```

### `domestic`

**`domestic`**:
```
You are a country specialist who has worked extensively in {COUNTRY} or its immediate
region. You are deeply familiar with local political dynamics, informal institutions,
and the gap between formal rules and actual practice on the ground.
```

**`international`**:
```
You are an international observer assessing {COUNTRY} from outside. You rely on
documented evidence and compare {COUNTRY} against international standards.
```

### `diligence`

**`careful`**:
```
Before assigning a score, read all the evidence provided carefully. Consider
each piece of evidence on its own terms before reaching a conclusion.
```

**`standard`**: [omit diligence instruction]

### `packet` (controlled at retrieval, not prompt)

| Level | ChromaDB call |
|---|---|
| `full` | n_chunks=5 (3 State Dept + 2 Freedom House if available) |
| `partial` | n_chunks=3 (State Dept only) |
| `minimal` | n_chunks=1 (State Dept only) |

Chunk size fixed at 400–500 tokens each. The model sees different evidence quantities;
the prompt instruction text is identical across packet levels.

### `source`

**`state_dept`**: retrieve from State Dept collection only

**`state_and_fh`**: retrieve from both State Dept and Freedom House collections;
interleave in the evidence block (State Dept first, then Freedom House)

### `examples`

**`none`**: [omit examples block — zero-shot baseline]

**`neutral_synthetic`**: 2–3 examples constructed from codebook ordinal descriptions,
no real country names. Format:
```
Example: In a country where the government targets specific civil society organizations
(particularly those advocating for political reform) while leaving others untouched,
the appropriate score is 2 because [codebook category 2 description].
```

**`calibration_matched`**: same examples but selected to anchor toward the threshold
tendency of the configuration — strict configurations get examples scored at the lower
end; lenient configurations get examples scored at the upper end. The matched examples
must be pre-constructed and locked in `data/processed/examples_by_threshold.yaml`
before running.

---

## Regression Specification

```r
library(fixest)

# Signed deviation model
signed_model <- feols(
  signed_deviation ~
    i(threshold, ref = "neutral") +
    i(conception, ref = "liberal") +
    i(domestic, ref = "international") +
    i(examples, ref = "none"),
  data    = results,
  fixef   = "country_year",   # country-year FEs included free (same pool all configs)
  cluster = "country_year"
)

# Absolute deviation model
abs_model <- feols(
  abs_deviation ~
    i(reliability, ref = "standard") +
    i(diligence, ref = "standard") +
    i(packet, ref = "minimal"),
  data    = results,
  fixef   = "country_year",
  cluster = "country_year"
)
```

**Estimand**: average causal effect of each attribute level on coding deviation for
this model. Not an AMCE; not an IMCE. A standard factorial treatment effect.

**Country-year fixed effects**: included at no power cost because the same N_cy pool
runs across all configurations. FEs absorb all country-year heterogeneity (panel-level
baseline repressiveness, evidence quality, etc.), isolating the attribute effects.

---

## Identification

Causal identification rests on random assignment (Rubin 1974; Holland 1986), not on
HHY's AMCE machinery. Three HHY identification assumptions are satisfied by design:

1. **No carryover effects**: each (config × country-year) cell is a fresh API call with
   a new context window. No prior task output is passed to any subsequent call.

2. **No profile-order effects**: no shared context across calls; no ordering within any
   single configuration run.

3. **Independent randomization**: the fractional factorial assigns attribute levels
   orthogonally across configurations. Verify the correlation matrix of `design_matrix.csv`
   before running: all pairwise |r| should be < 0.15.

**On temperature**: at temperature = 0, each (config × country-year) cell is
deterministic — one output. There is nothing to average within a cell. Apparent
"variance" across cells is true treatment variance plus country-year variation, both
of which are handled by the regression model. Do not run multiple calls per cell;
that would only replicate identical outputs.

---

## Interaction Pre-specification

The source type × domestic framing interaction must be declared before generating the
design matrix. This is the most theoretically motivated interaction: V-Dem documents
that domestic coders are harsher, and the mechanism may depend on which sources they
access. If pre-specified, bump to 64 configurations and include `source:domestic` in
the `optFederov` formula.

**Decision**: pre-specify source × domestic, or not?

Arguments for: theoretically motivated; required to guarantee estimability; not
recoverable post-hoc if aliased. Arguments against: adds 16 configs (~33%); dilutes
power for main effects; the theory (why would source type modulate domestic framing
in LLM prompts?) is less direct than in human coders.

**Recommendation**: pre-specify if the interaction is a primary hypothesis (it goes in
the abstract); leave as exploratory if it is secondary. Lock this decision before
generating the design matrix.

---

## Progression Rule to Stage 2

An attribute advances from Stage 1 to Stage 2 if it meets **both**:

1. Estimated effect in the theoretically predicted direction
2. p < 0.10 (one-sided test in the predicted direction)

For precision attributes (no directional prediction): advances if estimated effect
is negative (reduces |deviation|) and p < 0.10 (two-sided).

An attribute that reduces absolute deviation but has the wrong sign in signed deviation
is flagged for Stage 2 investigation with a note — it should not be silently dropped.
The wrong sign may indicate the manipulation is working on a different parameter than
expected (e.g., a "strict" framing that reduces variance rather than shifting the mean).

Pre-register the progression rule before running. Do not adjust after seeing results.

---

## Pre-registration Checklist

Lock all of the following before generating the design matrix or running any LLM calls:

**Design**
- [ ] Final attribute set and levels (confirm `examples` attribute is included)
- [ ] N configurations: 48 (main effects) or 64 (with pre-specified interaction)
- [ ] Decision: pre-specify source × domestic interaction?
- [ ] Design matrix generated and saved to `data/processed/design_matrix.csv`
- [ ] Country-year pool: N_cy, sampling strategy (quintile-stratified), locked list
- [ ] Target indicator(s): `v2csreprss` first; others specified before running

**Outcomes**
- [ ] Directional prediction for each attribute level (sign of coefficient in signed deviation)
- [ ] Which attributes are evaluated on signed deviation vs. absolute deviation vs. both
- [ ] Regression specification (formula, FE structure, clustering)

**Progression**
- [ ] Progression rule: direction + p < 0.10 threshold
- [ ] What happens to wrong-sign attributes (flag, don't drop)

**Codebook text**
- [ ] Exact question text for each target indicator in `data/processed/codebook_text.yaml`
- [ ] All ordinal category descriptions (0–4) locked
- [ ] Examples text for `examples` attribute levels locked in `data/processed/examples_by_threshold.yaml`
