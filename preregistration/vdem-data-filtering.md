# V-Dem Coder-Level Data: Filtering Notes

*Written 2026-07-10. Describes how `shared/generate_vdem_data.R` filters the raw
V-Dem v15 coder-level dataset down to `panel_means.csv` and `human_ratings.csv`.*

---

## Starting point

**Raw RDS**: `shared/vdem-data/V-Dem-Coder-Level-v15_rds/Coder-Level-Dataset-v15.rds`
- 766,712 rows × 1,314 columns
- One row per coder-country-year, but with two entries per coder per year
  (Jan 1 and Dec 31) as a structural feature of the dataset

---

## Filter 1: Dec 31 rows only

V-Dem's published end-of-year country scores use the Dec 31 observation.
Keeping both Jan 1 and Dec 31 would double-count each coder's rating without
adding signal, producing inflated N in panel means and ~2× the fine-tuning
examples (identical prompts and ratings).

**Filter**: `format(historical_date, "%m-%d") == "12-31"`
→ 766,712 rows → 348,091 rows

---

## Filter 2: Study period (2010–2024)

The analysis only requires years relevant to the study:

| Use                          | Years        |
|------------------------------|--------------|
| Fine-tuning training window  | 2016–2018    |
| Primary evaluation year     | 2019         |
| Few-shot example selection   | 2020         |
| Attrition reference / thin   | 2015, 2022   |
| Deployment robustness check  | 2024         |

2010 as the start provides a buffer before the training window; historical
V-Dem data (1789–2009) is excluded as irrelevant to the current study.

**Filter**: `year %in% 2010:2024`
→ 348,091 rows → **52,552 coder-country-year rows**

---

## Filter 3: Type C indicators only

The 1,314 columns include many non-indicator columns (metadata, anchor
questions, aggregate index scores) and non-C-type variables.

**Type C** (`vartype == "C"` in `vdemdata::codebook`) are the expert-coded
ordinal indicators — the only ones with meaningful coder-level variation for
panel means and fine-tuning. Other types excluded:

| Type | Description                        | Example          |
|------|------------------------------------|------------------|
| A    | Country-date (government stats)    | `e_*`            |
| B    | Binary expert survey (yes/no)      | some `v2*`       |
| D    | Interval-scale expert survey       | some `v2*`       |

`vdemdata::codebook` contains **302 Type C tags** total. Of these:

- **273** are present as columns in the coder-level RDS and are numeric
- **29** are absent from the RDS — these fall into four categories:
  - *Multi-select variables* stored as split binary columns in the RDS
    (e.g., `v2smorgtypes` → `v2smorgtypes_0` through `v2smorgtypes_9`)
  - *Change/delta variables* measuring year-over-year differences
    (e.g., `v2clrgstch`, `v2csanmvch`, `v2edideolch_rec`)
  - *Conditionally-asked variables* only applicable under certain regime
    types or election occurrences (e.g., `v2elsnless`, `v2exctlhg`)
  - *V3 module variables* using a different naming convention
    (`v3equavolc`, `v3equavouc`)

None of the 29 absent indicators are in the training or evaluation sets.

**Identification**: `cl |> select(all_of(intersect(type_c_tags, names(cl)))) |> select(where(is.numeric))`

---

## Outputs

### panel_means.csv (16 MB)

One row per (country_text_id, year, indicator). Columns:

| Column          | Description                                          |
|-----------------|------------------------------------------------------|
| country_text_id | ISO 3-letter country code                            |
| year            | Calendar year (2010–2024)                            |
| indicator       | V-Dem indicator tag (e.g., `v2csreprss`)             |
| raw_mean        | Mean of coder ratings (Dec 31, rounded to 4 dp)      |
| n_coders        | Number of distinct coders contributing               |
| theta_quintile  | Quintile of v2x_polyarchy within 2010–2024 (1–5; 0 if unmatched) |
| v2x_regime      | Regime type: 0 closed autocracy → 3 liberal democracy |

**Row count**: 538,967 rows across **249 indicators**
(24 of 273 Type C indicators have no ratings in 2010–2024, likely
conditionally-asked or newly introduced indicators).

Average n_coders per cell: 4,404,442 ÷ 538,967 ≈ **8.2 coders per CYI**.

`theta_quintile` and `v2x_regime` come from `vdemdata::vdem` joined on
(country_text_id, year). Quintiles are computed within 2010–2024 so
they reflect the contemporary democracy distribution, not the historical
1789–2024 range.

### human_ratings.csv (130 MB)

One row per (country_text_id, year, indicator, coder_id). Columns:

| Column          | Description                            |
|-----------------|----------------------------------------|
| country_text_id | ISO 3-letter country code (= iso3)     |
| iso3            | ISO 3-letter code (alias, for lookups) |
| year            | Calendar year (2010–2024)              |
| indicator       | V-Dem indicator tag                    |
| coder_id        | V-Dem coder identifier                 |
| rating          | Individual coder's ordinal rating      |

**Row count**: 4,404,442 rows. No NA values in `rating` — the
`filter(!is.na(rating))` after `pivot_longer` drops unrated cells before
writing. Sparsity in the wide format (coders only rate their assigned
module's indicators) is resolved at this stage; the long format contains
only cells where a rating exists.

---

## Downstream filtering (applied by the Python pipeline, not in R)

The two CSVs contain all Type C indicators for 2010–2024. Further filtering
is applied downstream:

| Filter                        | File affected         | Applied in                    |
|-------------------------------|-----------------------|-------------------------------|
| Strong + partial coverage     | human_ratings.csv     | `prepare_finetune_data.py`    |
| Training years (2016–2018)    | human_ratings.csv     | `prepare_finetune_data.py`    |
| Evaluation indicators (~25–30)| panel_means.csv       | `substitution_eval.py`        |
| ≥8 coders (replacement pool)  | panel_means.csv       | `replacement_experiment.py`   |

The ~174 training indicator set (strong + partial coverage, ≥6 median
coders per country in 2020) is defined in
`initial-exploration/explore-indicators/02-indicator-selection.qmd`.
The ~25–30 evaluation indicators are TBD pending qualitative section-mapping
review; see `docs/todo.md`.
