# State Dept and Freedom House Section Coverage: 2016–2023

All coverage counts refer to YAML-mapped sections (the sections actually used by
`get_evidence()` for coding) plus the executive summary. "All present" means every
YAML-mapped section key is found in every file for that source/year combination.

The 16 SD mapped keys are: 1a, 1b, 1c, 1d, 1e, 1f, 2a, 2b, 2c, 2d, 3, 4, 5, 6, 7a, 7e.
The 7 FH mapped keys are: A, B, C, D, E, F, G.

---

## 2016

**SD**: 16 mapped sections present in all files. exec_summary present in 194 of 197 files.

**exec_summary gaps — resolved via PDF extraction (July 2025):**
All three 2016 exec_summary gaps were patched by extracting the executive summary from
PDFs hosted at `www.state.gov/wp-content/uploads/2019/01/` (uploaded to the archive in
Jan 2019 alongside 2017 and 2018 reports) and prepending it to the existing HTML-scraped
file.

| Country | PDF URL |
|---|---|
| Israel | `www.state.gov/…/Israel-and-The-Occupied-Territories.pdf` |
| Malaysia | `www.state.gov/…/Malaysia-1.pdf` |
| Romania | `www.state.gov/…/Romania-1.pdf` |

Note: The Israel PDF is a combined "Israel and the Occupied Territories" report; only the
Israel section exec_summary is used (text before Section 1.).

**Resolution of re-download artifact (July 2025):** The 2025 re-download created
simple-slug files (e.g. `china.txt`) alongside the original variant-slug files (e.g.
`china-includes-tibet-hong-kong-and-macau.txt`). Because `.` sorts after `-` in ASCII,
the simple-slug file won in `build_country_map()` even though the old file had an
exec_summary. Fixed by deleting 9 redundant simple-slug files:
`china`, `kyrgyzstan`, `micronesia`, `north-korea`, `north-macedonia`, `south-korea`,
`bahamas`, `eswatini`, `gambia` (all for 2016). The old variant-slug files now win and
have exec_summaries.

**FH 2016**: FiW 2017 published genuinely abridged reports for ~87 countries — Political
Rights sections (A–C) are absent from both the website and the PDF. The page footer reads:
*"This country report has been abridged for Freedom in the World 2017. For background
information on political rights and civil liberties in [country], see Freedom in the World
2016."* Freedom House cites ongoing budget constraints; abridged reports tend to be stable
democracies and smaller countries where less changed year-to-year.

In practice, sections D–G are also bare headers with no content for abridged countries, so
they behave identically to the 39 micro-states (Andorra, Kiribati, Monaco, etc.) that have
no narrative sections at all. Both groups have only the executive summary as usable content.

The pipeline handles this gracefully: `get_evidence()` returns the exec summary plus whatever
sections are present, skipping missing ones. The A–C gaps appear in `check_section_coverage`
output for 2016 FH and are expected.

Representative abridged URLs (section headers present but no content):
- `https://freedomhouse.org/country/australia/freedom-world/2017`
- `https://freedomhouse.org/country/denmark/freedom-world/2017`

Representative full-report URL (all sections present):
- `https://freedomhouse.org/country/nigeria/freedom-world/2017`

PDF archive reference: https://freedomhouse.org/reports/publication-archives

---

## 2017

**SD**: All 16 mapped sections present in all 196 files. exec_summary present in 190 of 196
files after re-download and cleanup.

**exec_summary gaps — resolved via PDF extraction (July 2025):**
All six 2017 exec_summary gaps were patched from PDFs at the same `2019/01/` upload path.
The 2017 Israel report used a different combined-report filename than 2016.

| Country | PDF URL |
|---|---|
| Colombia | `www.state.gov/…/Colombia-1.pdf` |
| Israel | `www.state.gov/…/Israel-Golan-Heights-West-Bank-and-Gaza.pdf` |
| Jamaica | `2017-2021.state.gov/…/Jamaica-1.pdf` |
| Peru | `2017-2021.state.gov/…/Peru.pdf` |
| Philippines | `www.state.gov/…/Philippines.pdf` |
| Romania | `2017-2021.state.gov/…/Romania.pdf` |

**Resolution of re-download artifact (July 2025):** Same fix as 2016 — deleted 9 redundant
simple-slug files: `china`, `kyrgyzstan`, `micronesia`, `north-korea`, `north-macedonia`,
`south-korea`, `bahamas`, `eswatini`, `gambia` (all for 2017). Old variant-slug files now
win and have exec_summaries.

**FH 2017**: All 7 mapped sections present in all 209 files. Clean.

---

## 2018

**SD**: All 16 mapped sections present in all 195 files. exec_summary present in all files.
Clean.

Four countries required manual fixes after HTML-first ingest:
- **Burundi** — section 1b existed only at a `__trashed` URL; re-fetched directly
- **Jamaica** — re-fetched from `jamaica__trashed/` URL (standard slug returned no content)
- **Peru** — re-fetched from `peru__trashed/` URL
- **Kiribati** — 1f content present but unlabeled in source HTML; `f.` prefix added manually

**FH 2018**: Clean.

---

## 2019

**SD**: All 16 mapped sections present in all 194 files. exec_summary present in all files.
Clean.

Eight countries returned 404 on all URL templates for 2019 and were patched by extracting
exec_summary text from PDFs (via `pdftotext -layout`) and prepending it to the existing HTML
file: Colombia, Côte d'Ivoire, Ghana, Jamaica, Mongolia, Peru, Philippines, Romania.

One manual fix:
- **Tanzania** — section 2b content present but unlabeled in source HTML; `b.` prefix added
  manually. Verified as genuine: Tanzania's 2019 SD report has Freedom of Assembly content
  but does not label it as subsection b.

**FH 2019**: All 7 mapped sections present in all 210 files. Clean.

---

## 2020

**SD**: All 16 mapped sections present in all 195 files. exec_summary present in all files.
Clean.

Re-ingested via HTML-first (replacing original PDF ingest). Two manual fixes required:
- **Romania** — HTML unavailable on both archive sites; fell back to PDF which has a
  word-split artifact (`Secti on 7.`). Fixed in place.
- **Angola** — Section 2b content present but unlabeled in source HTML (`Freedom of Peaceful
  Assembly` header with no `b.` prefix). `b.` prefix added manually.

One non-country file: `download-appendix-d-629-kb-2020-human-rights-report` (no recognized
sections — added to SLUG_OVERRIDES in `country_map.py` as None).

**FH 2020**: Clean.

---

## 2021

**SD**: All 16 mapped sections present in all 194 files. exec_summary present in all files.
Clean.

**FH 2021**: All 7 mapped sections present in all 210 files. Clean.

---

## 2022

**SD**: All 16 mapped sections present in all 194 files. exec_summary present in all files.
Clean.

Slug fixes (same pattern as earlier years — 2020 slug list used as source):
- `bahamas`, `gambia`, `kyrgyzstan` → fetched as `the-bahamas`, `the-gambia`, `kyrgyz-republic`
- `morocco` — transient fetch failure; re-fetched successfully

One manual fix:
- **Iran** — section 1d labeled `D.` (capital) in source HTML; lowercased to `d.` manually

**FH 2022**: All 7 mapped sections present in all 210 files. Clean.

---

## 2023

**SD**: All 16 mapped sections present in all 193 files. exec_summary present in all files.
Clean.

Slug fixes:
- `gambia`, `kyrgyzstan` → fetched as `the-gambia`, `kyrgyz-republic`
- `bahamas` → fetched as `the-bahamas-2` (new variant for 2023)
- `belize` — urllib infinite redirect loop; fetched via `requests` directly

**Burma/Myanmar**: No 2023 SD report available. State Dept archive returns "unavailable"
on the site and "forbidden" from the archive. Genuine absence — 193 countries for 2023
vs 194 in other years.

**FH 2023**: All 7 mapped sections present in all 210 files. Clean.

---

## 2024

**SD**: Completely restructured format — incompatible with 2016–2023 section mappings.

The 2024 State Dept reports reorganized from 7 sections to 3, with entirely new subsection
headings:

| Old (2016–2023) | New (2024) |
|---|---|
| Section 1: Civil Liberties (1a–1h/i) | Section 1: Killing, Coercion, War Crimes (1a–1c) |
| Section 2: Freedoms (press, assembly, religion…) | Section 2: Press, Worker Rights, Disappearance, Religion, Trafficking (2a–2e) |
| Section 3: Electoral/Political | Section 3: Torture, Children, Refugees, Antisemitism, Transnational Repression (3a–3e) |
| Section 4: Corruption | *(eliminated as standalone)* |
| Section 5: Civil Society | *(eliminated as standalone)* |
| Section 6: Discrimination | *(eliminated as standalone)* |
| Section 7: Worker Rights (7a–7e) | *(folded into Section 2b)* |

**Length and emphasis**: Average report dropped from ~59k to ~20k chars (~66% reduction).
Representative country (Nigeria): corruption mentions 9→4, discrimination mentions 15→2,
civil society/NGO mentions 12→7. Topics like corruption, discrimination, and civil society
are still present but no longer have dedicated sections.

**Implication**: 2024 would require an entirely new `indicator_sections.yaml` mapping and
new parser keys. Given that the primary evaluation year is 2019 and the training window is
2016–2018, 2024 is out of scope for the current paper.

**Kenya**: No 2024 SD file — page uses dynamic rendering, scraper returns empty content.
**Burma/Myanmar**: No 2024 SD report.

**FH 2024**: 207 files (3 missing: Crimea, Eastern Donbas, Nagorno-Karabakh — genuine
absences post-2023 geopolitical changes). All 7 mapped sections present in all 207 files.
