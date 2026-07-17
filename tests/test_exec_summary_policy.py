"""
Smoke tests for exec_summary fallback policy in load_anonymized_for_indicator
and load_summarized_for_indicator.

Verifies:
  - exec_summary is EXCLUDED when body sections exist
  - exec_summary is INCLUDED as fallback when no body sections exist
  - SDHRR exec_summary is EXCLUDED even as fallback for 2c-only indicators

Run from project root:
    pytest tests/test_exec_summary_policy.py -v
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

import pipeline.anonymize_section as anon_mod
import pipeline.summarize_indicator as summ_mod


def make_cache(base: Path, year: int, iso: str, source: str, section_id: str, content: str) -> None:
    p = base / str(year) / iso / f"{source}_{section_id}.txt"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)


# ── Anonymized assembly ──────────────────────────────────────────────────────

class TestAnonExecPolicy:
    """load_anonymized_for_indicator exec_summary inclusion rules."""

    def test_exec_excluded_when_body_exists(self, tmp_path):
        """exec_summary must not appear when indicator body sections are cached."""
        base = tmp_path / "anonymized"
        # v2clkill maps state-dept: ["1a", "1b"], freedom-house: ["F"]
        make_cache(base, 2019, "NGA", "state-dept", "exec_summary", "EXEC SD")
        make_cache(base, 2019, "NGA", "state-dept", "1a", "BODY 1a")
        make_cache(base, 2019, "NGA", "freedom-house", "exec_summary", "EXEC FH")
        make_cache(base, 2019, "NGA", "freedom-house", "F", "BODY F")

        with patch.object(anon_mod, "ANON_DIR", base):
            result = anon_mod.load_anonymized_for_indicator("NGA", 2019, "v2clkill")

        assert result is not None
        assert "BODY 1a" in result
        assert "BODY F" in result
        assert "EXEC SD" not in result
        assert "EXEC FH" not in result

    def test_exec_included_as_fallback_when_no_body(self, tmp_path):
        """exec_summary must appear when no body sections are cached."""
        base = tmp_path / "anonymized"
        # v2clkill: body sections 1a, 1b, F — none cached; exec_summary only
        make_cache(base, 2019, "NGA", "state-dept", "exec_summary", "EXEC SD")
        make_cache(base, 2019, "NGA", "freedom-house", "exec_summary", "EXEC FH")

        with patch.object(anon_mod, "ANON_DIR", base):
            result = anon_mod.load_anonymized_for_indicator("NGA", 2019, "v2clkill")

        assert result is not None
        assert "EXEC SD" in result
        assert "EXEC FH" in result

    def test_sdhrr_exec_excluded_for_2c_only_indicator(self, tmp_path):
        """SDHRR exec_summary must not appear for 2c-only indicators even as fallback."""
        base = tmp_path / "anonymized"
        # v2clrelig maps state-dept: ["2c"] only; IRFR not cached here
        make_cache(base, 2019, "NGA", "state-dept", "exec_summary", "EXEC SD")
        # FH body section D is present, so FH exec not needed
        make_cache(base, 2019, "NGA", "freedom-house", "D", "BODY FH D")

        with patch.object(anon_mod, "ANON_DIR", base):
            result = anon_mod.load_anonymized_for_indicator("NGA", 2019, "v2clrelig")

        assert "EXEC SD" not in (result or "")

    def test_irfr_body_used_for_2c(self, tmp_path):
        """When IRFR section is cached, it should appear as body content for 2c indicators."""
        base = tmp_path / "anonymized"
        make_cache(base, 2019, "NGA", "state-dept", "irfr", "IRFR BODY")
        make_cache(base, 2019, "NGA", "state-dept", "exec_summary", "EXEC SD")
        make_cache(base, 2019, "NGA", "freedom-house", "D", "BODY FH D")

        with patch.object(anon_mod, "ANON_DIR", base):
            result = anon_mod.load_anonymized_for_indicator("NGA", 2019, "v2clrelig")

        assert result is not None
        assert "IRFR BODY" in result
        assert "EXEC SD" not in result

    def test_none_when_no_content_at_all(self, tmp_path):
        """None returned when nothing is cached for the indicator."""
        base = tmp_path / "anonymized"

        with patch.object(anon_mod, "ANON_DIR", base):
            result = anon_mod.load_anonymized_for_indicator("NGA", 2019, "v2clkill")

        assert result is None


# ── Summarized assembly ──────────────────────────────────────────────────────

class TestSummExecPolicy:
    """load_summarized_for_indicator exec_summary inclusion rules (mirror of anon)."""

    def test_exec_excluded_when_body_exists(self, tmp_path):
        base = tmp_path / "summarized"
        make_cache(base, 2019, "NGA", "state-dept", "exec_summary", "EXEC SD")
        make_cache(base, 2019, "NGA", "state-dept", "1a", "BODY 1a")
        make_cache(base, 2019, "NGA", "freedom-house", "exec_summary", "EXEC FH")
        make_cache(base, 2019, "NGA", "freedom-house", "F", "BODY F")

        with patch.object(summ_mod, "SUMM_DIR", base):
            result = summ_mod.load_summarized_for_indicator("NGA", 2019, "v2clkill")

        assert result is not None
        assert "BODY 1a" in result
        assert "EXEC SD" not in result
        assert "EXEC FH" not in result

    def test_exec_included_as_fallback_when_no_body(self, tmp_path):
        base = tmp_path / "summarized"
        make_cache(base, 2019, "NGA", "state-dept", "exec_summary", "EXEC SD")
        make_cache(base, 2019, "NGA", "freedom-house", "exec_summary", "EXEC FH")

        with patch.object(summ_mod, "SUMM_DIR", base):
            result = summ_mod.load_summarized_for_indicator("NGA", 2019, "v2clkill")

        assert result is not None
        assert "EXEC SD" in result

    def test_sdhrr_exec_excluded_for_2c_only_indicator(self, tmp_path):
        base = tmp_path / "summarized"
        make_cache(base, 2019, "NGA", "state-dept", "exec_summary", "EXEC SD")
        make_cache(base, 2019, "NGA", "freedom-house", "D", "BODY FH D")

        with patch.object(summ_mod, "SUMM_DIR", base):
            result = summ_mod.load_summarized_for_indicator("NGA", 2019, "v2clrelig")

        assert "EXEC SD" not in (result or "")
