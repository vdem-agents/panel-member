# Panel Member Coding Prompt

*Template used by all conditions except `codebook` (which bypasses this file entirely via
`_codebook_user()` in `assemble_prompt.py`). Placeholders in `{UPPER_CASE}` are filled by
`assemble_prompt.py`. Codebook text is loaded from `config/indicator_sections.yaml`.
`{CALIBRATION_SECTION}` is the full calibration block (header + few-shot examples) for
`evidence` and `anonymized`; empty string for `evidence-zeroshot`, `anonymized-zeroshot`,
`finetuned`, and `finetuned-raw`. The last two are used only by `prepare_finetune_data.py`
for training data assembly, not at inference time.*

---

<!-- SYSTEM -->

You are rating political conditions on V-Dem indicators using globally calibrated standards. Compare every country to the full worldwide distribution from the most repressive autocracies to the most open democracies. Do not apply a regional reference frame. A country that seems "moderately free" by regional standards may be "highly repressive" by global standards. Apply the global comparison frame.

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
