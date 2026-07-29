# Indicator Selection: How We Got to 206

*Synthesized from `initial-exploration/explore-indicators/` QMDs, `section-mapping-notes.md`,
`docs/experimental-design.md`, and `notes/exec-summary-policy-and-summarization-condition.md`.*

---

## Filter chain

Starting from V-Dem v15 Type C indicators — expert-coded ordinal ratings (as opposed
to factual, binary, or interval-scale variables) — the pipeline uses **206 indicators**
defined in `config/indicator_sections.yaml`.

| Step | Action | Count |
|------|--------|-------|
| Start | Type C indicators with data in 2010–2024 (`panel_means.csv`) | 262 |
| −28 | Discontinued modules excluded: `v2reg*` (2), `v2ed*` (20), `v2med*` (6) | 234 |
| −23 | V-Dem 3.0 variables excluded (`v3*` prefix, different module) | 211 |
| −4 | Excluded for thin panel or variable type: 3 below ≥6 median coders in 2020 (`v2clsnlpct`=4, `v2smprivcon`=5, `v2temonitor`=2); 1 delta variable (`v2exdfcbhs_rec`) | 207 |
| +1 | `v2exl_legitideolcr` added from codebook (no 2010–2024 data in panel_means, included as design decision for the exl module) | 208 |
| −2 | Interval-scale indicators excluded at YAML generation: `v2mefemjrn`, `v2svstterr` (responses field is "Percent." — no ordinal categories) | **206** |

The 208 candidates are in `config/indicator_section_mapping.csv`. The 206 final
indicators (excluding the two interval-scale ones) are in `config/indicator_sections.yaml`.

**Evaluable universe: 205, not 206.** The config file lists 206 indicators, but only 205
are ever scored against a panel mean. `v2exl_legitideolcr` (see Training coverage, below)
has zero panel-mean rows in `panel_means.csv` for any year 2010–2024 — not only the
training window. It therefore cannot contribute to the AI MAE metric in the 2019, 2023,
or 2024 evaluation pools either. Every reference elsewhere in the docs to "the
~205-indicator universe" — training or evaluation — refers to this same exclusion, not
an approximation.

**Training coverage**: of the 206 config indicators, **205 have training data**. The
exception is `v2exl_legitideolcr` ("ideology character" — a "check all that apply"
multi-binary follow-up to the ordinal `v2exl_legitideol` that identifies *which type*
of ideology the executive invokes: nationalist, socialist/communist, conservative,
separatist, or religious). It was added to the config from the V-Dem codebook because
it belongs to the `exl` module, but has no 2010–2024 panel ratings so it contributes
zero training rows (`grep -c v2exl_legitideolcr data/processed/training_set_raw.csv`
returns 0). It has real section mappings (SDHRR 2a / FiW D), so the pipeline *could*
assemble evidence and request a rating for it — but since no panel mean exists for it in
any year, that rating has nothing to be scored against. In practice it is excluded from
all quantitative evaluation, not just training; see "Evaluable universe," above.

---

## Why discontinued modules were excluded

| Module | Prefix | Count | Reason |
|--------|--------|-------|--------|
| Regime characteristics | `v2reg*` | 2 | Discontinued after 2018 — no evaluation-year data |
| Education content | `v2ed*` | 20 | Discontinued after 2021; median panel ≤ 2 |
| State media and content | `v2med*` | 6 | Discontinued after 2021; median panel ≤ 2 |

---

## Coverage tiers and the 12 "none"-coverage indicators

All 206 indicators were mapped to SDHRR and FiW sections. Coverage tiers reflect
how consistently the assigned sections address the indicator's question:

| Tier | Count | Characterization |
|------|-------|-----------------|
| Strong | 109 | Dedicated section with systematic, detailed reporting |
| Partial | 65 | Addressed but not systematically — depth varies |
| Weak | 22 | Mentioned in passing or through a structural proxy |
| None | 12 | No section mapping in either source |

The 12 "none"-coverage indicators (7 Deliberation `v2dl*`, 5 Executive legitimation
`v2exl*`) are included in the pipeline — they receive executive summaries as their
evidence packet rather than body sections. See the exec_summary policy note below
and `notes/exec-summary-policy-and-summarization-condition.md`.

Within the 206 total, three indicators have **no section in either source**
(`state-dept: []`, `freedom-house: []`): `v2dlcommon`, `v2dlcountr`, `v2exl_legitlead`.
Twenty-six have **no State Dept section** but do have a FiW mapping; they receive
the FiW body section plus the SDHRR executive summary.

---

## Exec_summary policy

Executive summaries describe country-level context rather than the specific indicator
dimension. Including them in every evidence packet increased top-1 reidentification
rates by 18 pp under summarization (98-CYI experiment, Llama 3.3 70B).

**Policy**: exec_summary is included **only when no body sections exist** for a given
source — either because the indicator config contains `[]` (the 3 fully unmapped and
26 SD-unmapped cases) or because cached section files are missing from disk. It is not
included alongside present body sections. Full rationale: `notes/exec-summary-policy-and-summarization-condition.md`.

FiW 2016 exception: ~87 stable democracies received abridged reports with no section
A–C body text; the exec_summary is used automatically for those country-years.

---

## Key references

- `config/indicator_sections.yaml` — authoritative indicator list with codebook text and section mappings
- `config/indicator_section_mapping.csv` — 208 candidates with coverage tier and module metadata
- `initial-exploration/explore-indicators/section-mapping-notes.md` — indicator-level section assignments (working log)
- `docs/experimental-design.md` — high-level scope and the 3-unmapped / 26-SD-unmapped breakdown
- `notes/exec-summary-policy-and-summarization-condition.md` — exec_summary policy and experiment
