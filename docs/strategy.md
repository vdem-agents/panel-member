# Panel Member: Research Strategy

## Research question

Which persona attributes causally shift LLM coding behavior relative to a human panel
mean, and can AI personas with those attributes serve as effective synthetic panel members
in V-Dem's IRT measurement model?

## Stage 1: Fractional factorial experiment

### Design

**Unit of analysis**: one LLM instance per (configuration × country-year) cell. Not a
panel of AI coders — a single LLM receives one persona specification and codes one
country-year. The panel mean comparison is across configurations, not within a panel.

**Design type**: algorithmic fractional factorial (R `AlgDesign` or `DoE.base`).
32–48 configurations for main effects only; 64 if the source type × domestic framing
interaction is pre-specified. Random assignment with post-hoc orthogonality check is an
acceptable alternative for a political science audience. Orthogonality affects efficiency
(SE size), not identification — random assignment identifies causal effects regardless.

**Country-year pool**: N_cy = 30–50 country-years with ≥8 distinct coders (2010–2019),
drawn once and held fixed across all configurations. Country-year fixed effects can be
included in the regression at no additional cost since the same pool is used everywhere.

**Total calls**: 32–48 configs × 30–50 CYs ≈ 960–2,400 LLM calls (~$20–50 frontier API).

### Attributes and levels

| Attribute | Levels | Outcome | Predicted direction |
|---|---|---|---|
| Threshold tendency | strict / neutral / lenient | signed | strict → negative; lenient → positive |
| Reliability profile | high / medium / low | absolute | high → lower |
| Democracy conception | liberal / majoritarian / participatory / deliberative | signed | indicator-dependent |
| Domestic framing | domestic coder / international observer | signed | domestic → negative |
| Diligence | careful / standard | absolute | careful → lower |
| Packet richness | full / partial / minimal | absolute | full → lower |
| Source type | State Dept only / + Freedom House | TBD | to be determined |

Pre-specify the **source type × domestic framing** interaction before generating the design
matrix. This is the most theoretically motivated interaction: V-Dem documents that domestic
coders rate more harshly, and the mechanism may depend on which sources they have access to.
Declaring it before the design ensures it is estimable and not aliased with main effects.

### Outcome variables

Two outcomes in parallel — do not combine:

**Signed deviation** = LLM rating − human panel mean (range: −4 to +4 for a 5-point scale).
Used for attributes with directional predictions. A strict persona should rate below the
panel mean; a lenient persona above it. Pre-register the predicted sign for each attribute.

**Absolute deviation** = |LLM rating − human panel mean|.
Used for precision attributes (reliability, diligence, packet richness). A high-reliability
persona should produce ratings closer to the panel mean on average.

### Regression model

```
deviation_ij = α_j + Σ_k β_k × attribute_k_i + ε_ij
```

Where i indexes configurations, j indexes country-years, α_j are country-year fixed
effects (included for free given the complete matrix design). Cluster standard errors
by country-year. The β_k estimates are the average causal effects of each attribute level
on the coding deviation — standard factorial treatment effects.

### Identification

Causal identification rests on random assignment of persona attributes to configurations
(Rubin 1974 / Holland 1986 randomization inference), not on the AMCE machinery from
conjoint analysis. The AMCE framing is not appropriate here because personas are
*rater* attributes being manipulated, not *stimulus* attributes being evaluated. The
right framing is a randomized factorial experiment on measurement instrument properties.

### Indicator selection

Start with v2csreprss (civil society repression): well-studied, strong across-pool
calibration variation documented in the coder composition analysis, and State Dept reports
have clearly relevant content. Expand to additional indicators once Stage 1 is validated.

### Progression rule (to be pre-registered)

An attribute advances to Stage 2 if:
- For directional attributes: the estimated β_k has the pre-specified sign and p < 0.10
- For precision attributes: β_k < 0 (reduces absolute deviation) and p < 0.10

An attribute with the wrong sign in signed deviation may still advance if absolute deviation
is meaningfully reduced — this should be decided before running.

## Stage 2: Sequential replacement test

### Design

Replace human coders one at a time with AI personas matched to empirical coder profiles.
Profiles drawn from β_r and γ_{r,k} posterior distributions (V-Dem CurateND archive).

For each replacement step:
1. Remove one human coder from the panel
2. Draw an AI persona profile from the empirical distribution (matching the removed coder's
   β_r percentile)
3. Generate AI ratings for all N_cy country-years
4. Run IRT on the augmented panel
5. Compute ||θ_aug − θ_full||

Track the trajectory as k = 1, 2, 3, ... coders are replaced. The key output is the
degradation curve: at what k does θ_aug diverge meaningfully from θ_full? This directly
answers "how many human coders can AI replace before quality degrades?"

### IRT implementation

Simplified O-IRT in Stan for Stage 2 development (feasible locally in minutes). Full
V-Dem Stan pipeline for Stage 3 demonstration. The stage 2 simplification is defensible:
if the replacement effect holds in the simplified model, it will hold in the full pipeline.

### Persona construction

Use Stage 1 results to select persona configurations: attributes that significantly reduce
absolute deviation (high calibration) and show the correct sign in signed deviation (correct
directional behavior). Draw β_r and γ_{r,k} from the CurateND posteriors to anchor the
threshold and reliability manipulation to empirically observed coder distributions.

## Stage 3: Deployment

### Target 1: Historical sparse panels (1975–1989)

59% of pre-1990 country-years have ≤3 distinct coders. Adding 3–5 AI ratings moves these
from prior-dominated to data-informed — a categorical improvement.

Evidence packet availability: Freedom House (1972–), State Dept reports (1977–), major
press archives. Practical window ~1975–1989 before the Cold War political framing of
reporting becomes too severe. Pre-1975 is technically feasible for well-documented countries.

### Target 2: Chronic thin-coverage countries (contemporary)

~35 countries with mean panel < 8 in 2010–2024: Haiti, Chad, Guinea-Bissau, Solomon
Islands, Vanuatu, Gulf microstates, small Pacific and Caribbean states. Same evidence packet
sources as the contemporary window. Demonstrate on a subset with clear thin-panel problems
and available State Dept + Freedom House coverage.

### Target 3: Leading-edge gap (2020–present)

V-Dem's current coding year is always based on the thinnest panels (mean ~5.8 in 2024,
declining ~0.5/year). LLM coders as interim ratings for the current wave — operational
use case, immediate practical relevance.

## Information environment

### Source hierarchy

| Phase | Sources | Purpose |
|---|---|---|
| Phase 1 | State Dept Human Rights Reports (2020) | Baseline — already extracted |
| Phase 2 | + Freedom House Freedom in the World | Corrects coverage asymmetry |
| Phase 3 | + historical years (1977–2019) | Stage 3 deployment window |

### Retrieval architecture: vector RAG, per-country

For the panel member, the AI should simulate a country expert reasoning from that country's
information environment. Standard vector RAG (ChromaDB + sentence-transformers), with one
collection per country-year. Indicator-specific retrieval queries constructed from codebook
question text and ordinal category descriptions.

This is the opposite choice from the bridge coder repo, which uses GraphRAG with global
queries. Here, local information framing is correct: the AI is simulating what a
country-specific coder would have access to.

### Packet standardization (important for cross-country comparison)

Fix retrieved chunk count or token budget across countries. If Afghanistan's packet is 10×
longer than Sweden's, the information asymmetry confounds interpretation of cross-country
deviation patterns.

## Model selection

**Frontier (primary)**: Claude Sonnet 4.6. For Stage 1's persona responsiveness test, a
capable model is essential — smaller models may not respond to subtle framing manipulations,
making it impossible to distinguish "attribute has no effect" from "model too weak to
respond."

**Open-source (replication)**: Llama 3.3 70B or Qwen 3 72B, via Together.ai for
immediate access and Pegasus for Stage 3 scale. Run Stage 1 on both and report whether
results replicate.

## Compute

| Task | Platform | Cost/timeline |
|---|---|---|
| Stage 1 factorial (~2,400 calls) | Claude API | ~$20–50, immediate |
| Stage 1 replication | Together.ai (70B) | ~$10, this week |
| Stage 2 IRT (simplified) | Local Stan | Days, after Stage 1 |
| Stage 3 deployment | Pegasus A100 | Free, after Stage 2 |

## Key open questions

- [ ] Download CurateND threshold posteriors (γ_{r,k} and β_r); link to coder IDs
- [ ] Validate that anchor ratings (v2zzdem*) correlate with γ_{r,k} in expected direction
- [ ] Finalize attribute set and generate fractional factorial design matrix
- [ ] Pre-register: directional predictions for each attribute, progression rule, regression
  model, outcome formula — lock all before running anything
- [ ] Decide: pre-specify source type × domestic framing interaction (32 vs. 64 configs)?
- [ ] Indicator selection: confirm v2csreprss as first target; identify 1–2 others
- [ ] Email V-Dem (contact@v-dem.net): domestic/foreign coder indicator availability
