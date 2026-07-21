# Panel Member Coding Prompt

*Template used by all conditions except `codebook` (which bypasses this file entirely via
`_codebook_user()` in `assemble_prompt.py`). Placeholders in `{UPPER_CASE}` are filled by
`assemble_prompt.py`. Codebook text is loaded from `config/indicator_sections.yaml`.
`{CALIBRATION_SECTION}` is the full calibration block (header + few-shot examples) for
`evidence`, `anonymized`, and `summarized`; empty string for all other conditions.
`finetuned-anon`, `finetuned-raw`, and `finetuned-summ` are used only by
`prepare_finetune_data.py` for training data assembly, not at inference time.*

---

<!-- SYSTEM -->

Your task is to provide ratings for V-Dem indicators. Read the codebook question and response categories carefully. Then assign the rating that best matches the conditions in the available information.

<!-- USER -->

## Coding task

You will rate **{FOCAL_COUNTRY}** in **{FOCAL_YEAR}** on the following V-Dem indicator.

**Indicator**: {INDICATOR_NAME} (`{INDICATOR_CODE}`)

**Question**: {CODEBOOK_QUESTION}

**Response categories**:

{RESPONSE_CATEGORIES}

{CLARIFICATION_BLOCK}

---

{CALIBRATION_SECTION}

## Evidence for {FOCAL_COUNTRY}, {FOCAL_YEAR}

**State Department Human Rights Report**

{STATE_DEPT_EVIDENCE}

---

**Freedom House Freedom in the World**

{FH_EVIDENCE}

---

## Output

Rate {FOCAL_COUNTRY} in {FOCAL_YEAR} on {INDICATOR_CODE}.

Respond with JSON only — no preamble, no code fences:

{"rating": <integer 0–{MAX_RATING}>, "justification": "<one sentence citing specific evidence above>"}
