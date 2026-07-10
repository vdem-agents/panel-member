#!/usr/bin/env python3
"""
Stage 1: Ingest — extract plain text from State Dept PDF reports.

Freedom House reports are already plain text (.txt) so they don't need ingestion;
they're read directly from data/raw/freedom-house/{year}/ at summarization time.

Reads:  data/raw/state-dept/{year}/*.pdf
Writes: data/processed/text/state-dept/{year}/*.txt

Usage:
  python3 ingest.py --year 2020
  python3 ingest.py --year 2020 --countries nigeria kenya
"""

import argparse
import re
from pathlib import Path

import PyPDF2

RAW_DIR = Path(__file__).parent.parent / "data" / "raw"
PROCESSED_DIR = Path(__file__).parent.parent / "data" / "processed-text"


def extract_pdf_text(pdf_path: Path) -> str | None:
    """Extract plain text from a PDF. Returns None if extraction fails."""
    try:
        with open(pdf_path, "rb") as f:
            reader = PyPDF2.PdfReader(f)
            pages = []
            for page in reader.pages:
                text = page.extract_text()
                if text:
                    pages.append(text)
            full_text = "\n".join(pages).strip()
            return full_text if full_text else None
    except Exception as e:
        print(f"  Error reading {pdf_path.name}: {e}")
        return None


def clean_text(text: str) -> str:
    """Light cleaning: normalize whitespace, remove repeated blank lines."""
    text = re.sub(r"\r\n", "\n", text)
    text = re.sub(r" +", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def ingest_state_dept(year: int, country_filter: list[str] | None = None):
    raw_dir = RAW_DIR / "state-dept" / str(year)
    out_dir = PROCESSED_DIR / "state-dept" / str(year)
    out_dir.mkdir(parents=True, exist_ok=True)

    pdfs = sorted(raw_dir.glob("*.pdf"))
    if country_filter:
        pdfs = [p for p in pdfs if any(f.lower() in p.stem for f in country_filter)]

    print(f"Ingesting {len(pdfs)} State Dept PDFs ({year})...")
    success, failed, skipped = 0, [], []

    for pdf_path in pdfs:
        dest = out_dir / f"{pdf_path.stem}.txt"
        if dest.exists():
            skipped.append(pdf_path.stem)
            continue

        print(f"  {pdf_path.stem}...", end=" ", flush=True)
        text = extract_pdf_text(pdf_path)
        if text:
            dest.write_text(clean_text(text), encoding="utf-8")
            print(f"OK ({len(text):,} chars, {len(text.split())//1000}K words)")
            success += 1
        else:
            print("FAILED")
            failed.append(pdf_path.stem)

    print(f"\nDone: {success} extracted, {len(failed)} failed, {len(skipped)} skipped")
    if failed:
        print("Failed:", failed)


def main():
    parser = argparse.ArgumentParser(description="Ingest State Dept PDFs to plain text")
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument("--countries", nargs="*", default=None)
    args = parser.parse_args()
    ingest_state_dept(args.year, country_filter=args.countries)


if __name__ == "__main__":
    main()
