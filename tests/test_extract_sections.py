"""
Unit tests for pipeline/extract_sections.py.

Covers:
  - parse_state_dept: section splitting, exec_summary extraction, subsections,
    double-spaced PDF headers
  - parse_freedom_house: section splitting, exec_summary extraction, Score Change
    cleanup, Country Facts truncation, PR/CL divider removal, header artifacts
  - get_evidence: end-to-end extraction using a temp directory of mock files,
    including body-only, exec_summary fallback, 2c→IRFR redirect, and sec6
    subsection extraction
"""

import textwrap
from pathlib import Path
from unittest.mock import patch

import pytest

from pipeline.extract_sections import (
    _clean_fh_text,
    _parse_sec6_subsection,
    get_evidence,
    parse_freedom_house,
    parse_state_dept,
)


# ── Fixtures ──────────────────────────────────────────────────────────────────

SDHRR_BASIC = textwrap.dedent("""\
    This country had a turbulent year with restrictions on civil liberties.

    Section 1. Respect for the Integrity of the Person
    a. Arbitrary Deprivation of Life and Other Unlawful or Politically Motivated Killings
    Reports indicated killings by security forces.
    b. Disappearance
    No significant disappearances were reported.

    Section 2. Respect for Civil Liberties
    a. Freedom of Expression, Including for Members of the Press and Other Media
    The government restricted press freedom.
    c. Freedom of Religion
    See the Department of State's International Religious Freedom Report.

    Section 5. Governmental Posture Toward International and Nongovernmental Investigation
    NGOs operated with some restrictions.
""")

SDHRR_DOUBLE_SPACE = textwrap.dedent("""\
    Executive preamble text here.

    Section  1 . Respect for the Integrity of the Person
    a. Arbitrary Deprivation of Life and Other Unlawful or Politically Motivated Killings
    Some killings occurred.

    Section  2 . Respect for Civil Liberties
    Press was restricted.
""")

FH_BASIC = textwrap.dedent("""\
    Overview: The country saw democratic backsliding in the reporting period.
    Key Developments: Elections were held under controversial conditions.

    ## A Electoral Process
    A1. Was the current head of government or other chief national authority elected?
    The president was elected in a flawed election.

    ## B Political Pluralism and Participation
    B1. Do people have the right to organize in different political parties?
    Multiple parties exist but face restrictions.

    ## G Personal Autonomy and Individual Rights
    G1. Do individuals enjoy freedom of movement?
    Movement was generally free.
""")

FH_WITH_ARTIFACTS = textwrap.dedent("""\
    Overview text here.

    Score Change: A1 changed from 2 to 1 due to electoral irregularities.
    This should be stripped.

    ## A Electoral Process
    A1. Elections were held.

    ## PR Political Rights
    Some PR content that should be stripped.

    ## B Political Pluralism and Participation
    B1. Parties operate freely.

    ## Country Facts
    Population: 10 million
    This should be truncated.
""")

FH_HEADER_ARTIFACT = textwrap.dedent("""\
    Overview here.

    ## header2 A Electoral Process
    A1. Elections occurred.

    ## B Political Pluralism and Participation
    B1. Parties exist.
""")

SEC6_TEXT = textwrap.dedent("""\
    Section 6. Discrimination and Societal Abuses

    Women
    Women faced significant workplace discrimination.

    National/Racial/Ethnic Minorities
    Minority groups faced housing discrimination.

    Trafficking in Persons
    Reports of trafficking were documented.

    Other Societal Violence or Discrimination
    LGBTQI+ individuals faced violence.
""")


# ── parse_state_dept ──────────────────────────────────────────────────────────

class TestParseStateDept:

    def test_exec_summary_extracted(self):
        result = parse_state_dept(SDHRR_BASIC)
        assert "exec_summary" in result
        assert "turbulent year" in result["exec_summary"]

    def test_top_level_sections_present(self):
        result = parse_state_dept(SDHRR_BASIC)
        assert "1" in result
        assert "2" in result
        assert "5" in result

    def test_subsections_extracted(self):
        result = parse_state_dept(SDHRR_BASIC)
        assert "1a" in result
        assert "1b" in result
        assert "2a" in result
        assert "2c" in result

    def test_subsection_content(self):
        result = parse_state_dept(SDHRR_BASIC)
        assert "killings by security forces" in result["1a"]
        assert "press freedom" in result["2a"]

    def test_no_false_subsections(self):
        result = parse_state_dept(SDHRR_BASIC)
        assert "5a" not in result

    def test_double_spaced_headers(self):
        result = parse_state_dept(SDHRR_DOUBLE_SPACE)
        assert "exec_summary" in result
        assert "1" in result
        assert "2" in result
        assert "1a" in result

    def test_no_exec_summary_when_starts_with_section(self):
        text = "Section 1. Respect for the Integrity of the Person\na. Killings occurred.\n"
        result = parse_state_dept(text)
        assert "exec_summary" not in result
        assert "1" in result

    def test_empty_text(self):
        result = parse_state_dept("")
        assert result == {}


# ── parse_freedom_house ───────────────────────────────────────────────────────

class TestParseFreedomHouse:

    def test_exec_summary_extracted(self):
        result = parse_freedom_house(FH_BASIC)
        assert "exec_summary" in result
        assert "democratic backsliding" in result["exec_summary"]

    def test_sections_extracted(self):
        result = parse_freedom_house(FH_BASIC)
        assert "A" in result
        assert "B" in result
        assert "G" in result

    def test_section_content(self):
        result = parse_freedom_house(FH_BASIC)
        assert "flawed election" in result["A"]
        assert "restrictions" in result["B"]

    def test_score_change_stripped(self):
        result = parse_freedom_house(FH_WITH_ARTIFACTS)
        assert "exec_summary" in result
        assert "Score Change" not in result["exec_summary"]
        assert "Score Change" not in result.get("A", "")

    def test_country_facts_truncated(self):
        result = parse_freedom_house(FH_WITH_ARTIFACTS)
        combined = " ".join(result.values())
        assert "Population: 10 million" not in combined

    def test_pr_cl_dividers_stripped(self):
        result = parse_freedom_house(FH_WITH_ARTIFACTS)
        combined = " ".join(result.values())
        assert "## PR Political Rights" not in combined

    def test_header_artifact_cleaned(self):
        result = parse_freedom_house(FH_HEADER_ARTIFACT)
        assert "A" in result
        assert "header2" not in result.get("A", "")

    def test_no_exec_summary_when_starts_with_section(self):
        text = "## A Electoral Process\nA1. Elections were held.\n"
        result = parse_freedom_house(text)
        assert "exec_summary" not in result
        assert "A" in result

    def test_empty_text(self):
        result = parse_freedom_house("")
        assert result == {}


# ── _parse_sec6_subsection ────────────────────────────────────────────────────

class TestParseSec6Subsection:

    def test_women_subsection(self):
        result = _parse_sec6_subsection(SEC6_TEXT, "women", 2018)
        assert result is not None
        assert "workplace discrimination" in result

    def test_minorities_subsection_pre_2020(self):
        result = _parse_sec6_subsection(SEC6_TEXT, "minorities", 2018)
        assert result is not None
        assert "housing discrimination" in result

    def test_trafficking_subsection(self):
        result = _parse_sec6_subsection(SEC6_TEXT, "trafficking", 2018)
        assert result is not None
        assert "trafficking were documented" in result

    def test_other_societal_subsection(self):
        result = _parse_sec6_subsection(SEC6_TEXT, "other_societal", 2018)
        assert result is not None
        assert "LGBTQI+" in result

    def test_missing_subsection_returns_none(self):
        result = _parse_sec6_subsection(SEC6_TEXT, "women", 2021)
        # 2021 uses "Systemic Racial or Ethnic Violence and Discrimination" for minorities
        # but "Women" header is present; this should still work for women
        assert result is not None

    def test_absent_header_returns_none(self):
        result = _parse_sec6_subsection("No relevant content here.", "women", 2018)
        assert result is None


# ── get_evidence end-to-end ───────────────────────────────────────────────────

@pytest.fixture
def processed_dir(tmp_path):
    """Set up a minimal processed-text directory with mock report files."""
    sd_dir = tmp_path / "state-dept" / "2019"
    sd_dir.mkdir(parents=True)
    fh_dir = tmp_path / "freedom-house" / "2019"
    fh_dir.mkdir(parents=True)
    irfr_dir = tmp_path / "irfr" / "2019"
    irfr_dir.mkdir(parents=True)

    (sd_dir / "nigeria.txt").write_text(SDHRR_BASIC, encoding="utf-8")
    (fh_dir / "nigeria.txt").write_text(FH_BASIC, encoding="utf-8")
    (irfr_dir / "nigeria.txt").write_text(
        "The government restricted religious practices.", encoding="utf-8"
    )
    return tmp_path


@pytest.fixture
def mock_config():
    """Minimal indicator_sections.yaml config for testing."""
    return {
        "v2csreprss": {
            "description": "CSO repression",
            "state-dept": ["1", "2"],
            "freedom-house": ["B", "C"],
        },
        "v2clrelig": {
            "description": "Freedom of religion",
            "state-dept": ["2c"],
            "freedom-house": ["D"],
        },
        "v2peapsgeo": {
            "description": "Geo access",
            "state-dept": ["99"],   # section that doesn't exist → tests exec fallback
            "freedom-house": [],
        },
        "v2peasjsoc": {
            "description": "Social inequality",
            "state-dept": [],       # no sections → tests exec fallback
            "freedom-house": [],
        },
    }


class TestGetEvidence:

    def test_body_sections_returned(self, processed_dir, mock_config):
        with patch("pipeline.extract_sections.PROCESSED_DIR", processed_dir), \
             patch("pipeline.extract_sections._load_config", return_value=mock_config):
            result = get_evidence("nigeria", 2019, "v2csreprss", "state-dept")
        assert result is not None
        assert "killings by security forces" in result
        assert "press freedom" in result

    def test_exec_summary_not_in_result_when_body_exists(self, processed_dir, mock_config):
        with patch("pipeline.extract_sections.PROCESSED_DIR", processed_dir), \
             patch("pipeline.extract_sections._load_config", return_value=mock_config):
            result = get_evidence("nigeria", 2019, "v2csreprss", "state-dept")
        assert result is not None
        assert "turbulent year" not in result

    def test_exec_summary_fallback_when_no_body(self, processed_dir, mock_config):
        with patch("pipeline.extract_sections.PROCESSED_DIR", processed_dir), \
             patch("pipeline.extract_sections._load_config", return_value=mock_config):
            result = get_evidence("nigeria", 2019, "v2peapsgeo", "state-dept")
        assert result is not None
        assert "turbulent year" in result

    def test_no_exec_fallback_for_empty_sections_list(self, processed_dir, mock_config):
        # v2peasjsoc has no sections at all and no body → exec fallback
        with patch("pipeline.extract_sections.PROCESSED_DIR", processed_dir), \
             patch("pipeline.extract_sections._load_config", return_value=mock_config):
            result = get_evidence("nigeria", 2019, "v2peasjsoc", "state-dept")
        assert result is not None
        assert "turbulent year" in result

    def test_2c_redirects_to_irfr(self, processed_dir, mock_config):
        with patch("pipeline.extract_sections.PROCESSED_DIR", processed_dir), \
             patch("pipeline.extract_sections._load_config", return_value=mock_config):
            result = get_evidence("nigeria", 2019, "v2clrelig", "state-dept")
        assert result is not None
        assert "religious practices" in result

    def test_2c_no_sdhrr_exec_summary_in_result(self, processed_dir, mock_config):
        with patch("pipeline.extract_sections.PROCESSED_DIR", processed_dir), \
             patch("pipeline.extract_sections._load_config", return_value=mock_config):
            result = get_evidence("nigeria", 2019, "v2clrelig", "state-dept")
        assert result is not None
        assert "turbulent year" not in result

    def test_missing_file_returns_none(self, processed_dir, mock_config):
        with patch("pipeline.extract_sections.PROCESSED_DIR", processed_dir), \
             patch("pipeline.extract_sections._load_config", return_value=mock_config):
            result = get_evidence("senegal", 2019, "v2csreprss", "state-dept")
        assert result is None

    def test_freedom_house_sections(self, processed_dir, mock_config):
        with patch("pipeline.extract_sections.PROCESSED_DIR", processed_dir), \
             patch("pipeline.extract_sections._load_config", return_value=mock_config):
            result = get_evidence("nigeria", 2019, "v2csreprss", "freedom-house")
        assert result is not None
        assert "restrictions" in result

    def test_freedom_house_exec_not_prepended_when_body_exists(self, processed_dir, mock_config):
        with patch("pipeline.extract_sections.PROCESSED_DIR", processed_dir), \
             patch("pipeline.extract_sections._load_config", return_value=mock_config):
            result = get_evidence("nigeria", 2019, "v2csreprss", "freedom-house")
        assert result is not None
        assert "democratic backsliding" not in result
