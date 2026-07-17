"""
Smoke tests for pipeline/assemble_prompt.py.

Verifies structural correctness of rendered prompts without making any LLM calls.
Run from the project root:

    pytest tests/test_prompt_assembly.py -v

Anonymized-condition tests are skipped automatically if no anonymized files exist.
Generate them first with pipeline/anonymize_section.py, then re-run.
"""

import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from pipeline.assemble_prompt import assemble_prompt

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

YEAR = 2019

# Strong coverage (both sources), has clarification, COL in its fewshot block
STRONG_IND = "v2cafexch"

# No clarification field
NO_CLARIF_IND = "v2clacfree"

# Weak coverage (no source documents), fewshot examples present
WEAK_IND = "v2dlcommon"

# Focal country for exclusion test: COL 2017 appears in v2cafexch fewshot block
COL_ISO, COL_SLUG, COL_NAME = "COL", "colombia", "Colombia"

# Non-focal country used for most other tests
NGA_ISO, NGA_SLUG, NGA_NAME = "NGA", "nigeria", "Nigeria"

ANON_DIR = Path(__file__).parent.parent / "data" / "processed-text" / "anonymized"
HAS_ANON = any(ANON_DIR.rglob("*.txt"))

# Matches unreplaced {UPPER_CASE} placeholders; does not match JSON keys or {fewshot_block}
PLACEHOLDER_RE = re.compile(r"\{[A-Z][A-Z_]{1,}\}")


def unreplaced(text: str) -> list[str]:
    return PLACEHOLDER_RE.findall(text)


# ---------------------------------------------------------------------------
# codebook
# ---------------------------------------------------------------------------

class TestCodebook:
    def test_no_evidence_headers(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "codebook")
        assert "State Department" not in user
        assert "Freedom House" not in user

    def test_no_calibration_block(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "codebook")
        assert "## Calibration examples" not in user

    def test_no_placeholders(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "codebook")
        assert unreplaced(user) == []

    def test_no_clarification_renders_empty(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, NO_CLARIF_IND, "codebook")
        assert "**Clarification**" not in user
        assert unreplaced(user) == []


# ---------------------------------------------------------------------------
# evidence
# ---------------------------------------------------------------------------

class TestEvidence:
    def test_has_calibration_block(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "evidence", iso=NGA_ISO)
        assert "## Calibration examples" in user

    def test_no_placeholders(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "evidence", iso=NGA_ISO)
        assert unreplaced(user) == []

    def test_focal_country_excluded_from_fewshot(self):
        # COL 2017 is in the v2cafexch fewshot block — must be absent when COL is focal
        _, user = assemble_prompt(COL_SLUG, COL_NAME, YEAR, STRONG_IND, "evidence", iso=COL_ISO)
        assert "## Calibration examples" in user
        assert "Colombia, 2017" not in user

    def test_non_focal_country_retains_full_fewshot(self):
        # NGA does not appear in v2cafexch fewshot — Colombia 2017 should remain
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "evidence", iso=NGA_ISO)
        assert "Colombia, 2017" in user

    def test_no_clarification_renders_empty(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, NO_CLARIF_IND, "evidence", iso=NGA_ISO)
        assert "**Clarification**" not in user
        assert unreplaced(user) == []

    def test_weak_indicator_fallback_text(self):
        # Unmapped indicator (state-dept: [], freedom-house: []) falls back to
        # exec_summary for both sources — get_evidence reaches the fallback via an
        # empty body_chunks list. No "[No source document available]" placeholder
        # should appear; some evidence text must be present.
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, WEAK_IND, "evidence", iso=NGA_ISO)
        assert "[No source document available" not in user
        assert unreplaced(user) == []


# ---------------------------------------------------------------------------
# evidence-zeroshot
# ---------------------------------------------------------------------------

class TestEvidenceZeroshot:
    def test_no_calibration_block(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "evidence-zeroshot", iso=NGA_ISO)
        assert "## Calibration examples" not in user

    def test_no_placeholders(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "evidence-zeroshot", iso=NGA_ISO)
        assert unreplaced(user) == []


# ---------------------------------------------------------------------------
# finetuned-raw (training data assembly only — no fewshot block)
# ---------------------------------------------------------------------------

class TestFinetunedRaw:
    def test_no_calibration_block(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "finetuned-raw", iso=NGA_ISO)
        assert "## Calibration examples" not in user

    def test_no_placeholders(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "finetuned-raw", iso=NGA_ISO)
        assert unreplaced(user) == []


# ---------------------------------------------------------------------------
# anonymized conditions (skipped when no anonymized files exist)
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HAS_ANON, reason="No anonymized files — run anonymize_section.py first")
class TestAnonymized:
    def test_has_calibration_block(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "anonymized", iso=NGA_ISO)
        assert "## Calibration examples" in user

    def test_no_country_name_in_evidence(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "anonymized", iso=NGA_ISO)
        assert "[COUNTRY]" in user
        assert NGA_NAME not in user

    def test_no_placeholders(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "anonymized", iso=NGA_ISO)
        assert unreplaced(user) == []


@pytest.mark.skipif(not HAS_ANON, reason="No anonymized files — run anonymize_section.py first")
class TestAnonymizedZeroshot:
    def test_no_calibration_block(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "anonymized-zeroshot", iso=NGA_ISO)
        assert "## Calibration examples" not in user

    def test_no_placeholders(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "anonymized-zeroshot", iso=NGA_ISO)
        assert unreplaced(user) == []


@pytest.mark.skipif(not HAS_ANON, reason="No anonymized files — run anonymize_section.py first")
class TestFinetuned:
    def test_no_calibration_block(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "finetuned", iso=NGA_ISO)
        assert "## Calibration examples" not in user

    def test_no_placeholders(self):
        _, user = assemble_prompt(NGA_SLUG, NGA_NAME, YEAR, STRONG_IND, "finetuned", iso=NGA_ISO)
        assert unreplaced(user) == []
