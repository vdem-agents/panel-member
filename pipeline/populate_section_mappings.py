#!/usr/bin/env python3
"""
populate_section_mappings.py

Reads indicator-to-section mappings from section-mapping-notes.md and fills
the state-dept and freedom-house fields in config/indicator_sections.yaml.
Also strips any held_out flags (holdover from an earlier design).

Run from the panel-member project root after regenerating the YAML:
    python pipeline/populate_section_mappings.py

Optionally pass --dry-run to preview changes without writing.

Design decisions baked in:
  - v2jureview not in notes (binary indicator, missed during mapping exercise)
    → hardcoded to state-dept: ["1e"], freedom-house: ["F", "C"]
  - v2svstterr not in YAML (interval 0-100 scale, excluded in generate_indicator_yaml.R)
    → skipped silently
  - Excluded modules (v2reg*, v2ed*, v2med*) not in YAML → skipped silently
  - Indicators whose notes entry has "—" for a source → empty list []
  - Indicators in YAML but not in notes (e.g. newly added dl/exl entries with
    no section mapping) → left as [] and reported; they will use the default
    executive-summary evidence packet at inference time
"""

import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
NOTES_PATH = (
    PROJECT_ROOT.parent
    / "initial-exploration"
    / "explore-indicators"
    / "section-mapping-notes.md"
)
YAML_PATH = PROJECT_ROOT / "config" / "indicator_sections.yaml"

# Indicators not in notes that need a hardcoded mapping.
HARDCODED: dict[str, tuple[list[str], list[str]]] = {
    "v2jureview": (["1e"], ["F", "C"]),
}


# ── Parsing ───────────────────────────────────────────────────────────────────

def parse_section_list(cell: str) -> list[str]:
    """Parse a table cell like '`1d, 1e`' or '—' into a list of section keys."""
    cell = cell.strip().replace("`", "")
    if cell in ("—", "-", ""):
        return []
    return [p.strip() for p in cell.split(",") if p.strip()]


def parse_notes(notes_path: Path) -> dict[str, tuple[list[str], list[str]]]:
    """
    Parse section-mapping-notes.md into:
        { indicator: (state_dept_keys, fih_keys) }

    Rows from modules explicitly marked EXCLUDED in their section header are
    skipped. All other rows are parsed regardless of coverage tier — indicators
    with empty mappings will receive [] and rely on the default evidence packet.
    """
    mappings: dict[str, tuple[list[str], list[str]]] = {}
    in_excluded = False

    # Matches table rows whose first column is a backtick-wrapped v2* code.
    # Columns: | `v2code` | description | state_dept | fih | [optional status] |
    row_re = re.compile(
        r"^\|\s*`(v2[\w]+)`\s*\|[^|]+\|\s*([^|]+)\|\s*([^|]+)\|"
    )

    with open(notes_path, encoding="utf-8") as fh:
        for line in fh:
            stripped = line.strip()

            # Section header: ## Module name — EXCLUDED  →  enter excluded zone
            if stripped.startswith("## ") and "EXCLUDED" in stripped:
                in_excluded = True
                continue

            # Any other ## header resets the excluded flag
            if stripped.startswith("## "):
                in_excluded = False

            if in_excluded:
                continue

            m = row_re.match(line)
            if not m:
                continue

            indicator = m.group(1)
            sd_keys = parse_section_list(m.group(2))
            fih_keys = parse_section_list(m.group(3))
            mappings[indicator] = (sd_keys, fih_keys)

    return mappings


# ── YAML formatting ───────────────────────────────────────────────────────────

def format_yaml_list(keys: list[str]) -> str:
    """Format section keys as a YAML inline list: [] or ["1e", "F"]."""
    if not keys:
        return "[]"
    items = ", ".join(f'"{k}"' for k in keys)
    return f"[{items}]"


# ── YAML update ───────────────────────────────────────────────────────────────

_INDICATOR_RE = re.compile(r"^(v2[\w]+):$")
_SD_RE        = re.compile(r"^(\s*state-dept:)\s*\[.*\]")
_FIH_RE       = re.compile(r"^(\s*freedom-house:)\s*\[.*\]")
_HELD_OUT_RE  = re.compile(r"^\s*held_out:\s*(true|false)\s*$")


def update_yaml(
    yaml_path: Path,
    mappings: dict[str, tuple[list[str], list[str]]],
    dry_run: bool = False,
) -> tuple[set[str], set[str]]:
    """
    Rewrite yaml_path in place:
      - Strip all held_out: true/false lines
      - Fill state-dept and freedom-house for every indicator present in mappings

    Returns (updated, unmapped) where:
      updated  = indicators whose mappings were written
      unmapped = indicators in YAML but absent from mappings (left as [])
    """
    with open(yaml_path, encoding="utf-8") as fh:
        lines = fh.readlines()

    current_indicator: str | None = None
    out_lines: list[str] = []
    updated: set[str] = set()
    unmapped: set[str] = set()

    for line in lines:
        # Drop held_out lines entirely
        if _HELD_OUT_RE.match(line):
            continue

        # Track current indicator block
        m = _INDICATOR_RE.match(line.rstrip())
        if m:
            current_indicator = m.group(1)

        # Rewrite state-dept
        if current_indicator and _SD_RE.match(line):
            if current_indicator in mappings:
                sd_keys, _ = mappings[current_indicator]
                indent = re.match(r"(\s*)", line).group(1)
                line = f"{indent}state-dept: {format_yaml_list(sd_keys)}\n"
                updated.add(current_indicator)
            else:
                unmapped.add(current_indicator)

        # Rewrite freedom-house
        if current_indicator and _FIH_RE.match(line):
            if current_indicator in mappings:
                _, fih_keys = mappings[current_indicator]
                indent = re.match(r"(\s*)", line).group(1)
                line = f"{indent}freedom-house: {format_yaml_list(fih_keys)}\n"

        out_lines.append(line)

    if not dry_run:
        with open(yaml_path, "w", encoding="utf-8") as fh:
            fh.writelines(out_lines)

    return updated, unmapped


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    dry_run = "--dry-run" in sys.argv

    if not NOTES_PATH.exists():
        sys.exit(f"Notes file not found: {NOTES_PATH}")
    if not YAML_PATH.exists():
        sys.exit(f"YAML file not found: {YAML_PATH}")

    print(f"Parsing {NOTES_PATH.name} ...")
    mappings = parse_notes(NOTES_PATH)
    print(f"  Parsed {len(mappings)} indicator mappings from notes")

    for ind, (sd, fih) in HARDCODED.items():
        mappings[ind] = (sd, fih)
        print(f"  Hardcoded {ind}: state-dept={sd}  freedom-house={fih}")

    print(f"\n{'[DRY RUN] ' if dry_run else ''}Updating {YAML_PATH.name} ...")
    updated, unmapped = update_yaml(YAML_PATH, mappings, dry_run=dry_run)
    print(f"  Mappings written : {len(updated)}")

    if unmapped:
        print(
            f"\n  {len(unmapped)} indicator(s) in YAML but not in notes "
            "(left as [] — will use default executive-summary evidence packet):"
        )
        for ind in sorted(unmapped):
            print(f"    {ind}")

    # Indicators in notes but not in YAML (excluded modules, interval indicators)
    yaml_indicators: set[str] = set()
    with open(YAML_PATH, encoding="utf-8") as fh:
        for line in fh:
            m = _INDICATOR_RE.match(line.rstrip())
            if m:
                yaml_indicators.add(m.group(1))

    notes_not_yaml = set(mappings) - yaml_indicators
    if notes_not_yaml:
        print(
            f"\n  {len(notes_not_yaml)} indicator(s) in notes but not in YAML "
            "(excluded modules / interval-scale — skipped):"
        )
        for ind in sorted(notes_not_yaml):
            print(f"    {ind}")

    print("\nDone.")


if __name__ == "__main__":
    main()
