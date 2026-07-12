#!/usr/bin/env python3
"""
Stage 1: Ingest — extract plain text from State Dept PDF reports and register
Freedom House plain-text files.

State Dept: PDFs are extracted via PyPDF2 and written to processed-text/state-dept/{year}/.
  Fallback: if no PDF exists (or it is not a valid PDF), fetch HTML from the State Dept
  archive at 2017-2021.state.gov or state.gov and extract text directly.
Freedom House: files are already plain text; a symlink is created from
  processed-text/freedom-house/{year}/ → raw/freedom-house/{year}/
  so the rest of the pipeline reads them from the standard processed-text location.

Reads:  data/raw/state-dept/{year}/*.pdf
Writes: data/processed-text/state-dept/{year}/*.txt
Links:  data/processed-text/freedom-house/{year}/ → data/raw/freedom-house/{year}/

Usage:
  python3 -m pipeline.ingest --year 2019
  python3 -m pipeline.ingest --year 2019 --countries nigeria kenya
  python3 -m pipeline.ingest --year 2018 --html-fallback bahamas qatar cote-divoire
"""

import argparse
import re
import time
import urllib.request
from pathlib import Path

import PyPDF2

_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"

# Ordered list of URL templates to try when fetching a country HTML report.
# {year} and {slug} are substituted.  Stop at the first 200 response.
_HTML_URL_TEMPLATES = [
    "https://2017-2021.state.gov/reports/{year}-country-reports-on-human-rights-practices/{slug}/",
    "https://www.state.gov/reports/{year}-country-reports-on-human-rights-practices/{slug}/",
    # Obama-era archive uses a different URL structure (dlid-based); this slug
    # pattern works for 2016 reports published in early 2017 but not earlier years.
    "https://2009-2017.state.gov/reports/{year}-country-reports-on-human-rights-practices/{slug}/",
]

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
    # Replace State Dept page-footer boilerplate with a newline so that any
    # section header following it lands at the start of a line for the parser.
    # Use a lookahead so variants like "Human Rights, and Labor" or "Labo r"
    # (PDF word-split artifact) are all handled by one pattern.
    text = re.sub(
        r"United States Department of State\s*[•·]\s*Bureau of[^\n]*?(?=Section\s+\d|\Z)",
        "\n",
        text,
    )
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def fetch_html_report(slug: str, year: int) -> str | None:
    """
    Fetch the State Dept HTML report for (slug, year) from the archive site.
    Returns extracted plain text in the same format as PDF extraction, or None.
    """
    html = None
    used_url = None
    for tmpl in _HTML_URL_TEMPLATES:
        url = tmpl.format(year=year, slug=slug)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": _UA})
            with urllib.request.urlopen(req, timeout=20) as resp:
                if resp.status == 200:
                    raw = resp.read()
                    html = raw.decode("utf-8", errors="replace")
                    used_url = url
                    break
        except Exception:
            continue

    if not html:
        return None

    # Extract content from <section class="entry-content"> blocks only.
    # These hold the actual report text; nav/header/footer are excluded.
    chunks = re.findall(
        r'<section[^>]*class="[^"]*entry-content[^"]*"[^>]*>(.*?)</section>',
        html,
        re.DOTALL | re.IGNORECASE,
    )
    content = "\n\n".join(chunks) if chunks else html

    # Strip all HTML tags
    text = re.sub(r"<[^>]+>", " ", content)
    # Decode HTML entities
    text = text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    text = text.replace("&nbsp;", " ").replace("&#8217;", "'").replace("&#8220;", '"').replace("&#8221;", '"')
    text = re.sub(r"&#\d+;", " ", text)
    text = re.sub(r"&[a-z]+;", " ", text)

    # Strip per-line leading whitespace so "Section N." always starts at column 0,
    # matching the same structure parse_state_dept() expects from PDF extraction.
    text = "\n".join(line.strip() for line in text.splitlines())
    cleaned = clean_text(text)
    if not cleaned or len(cleaned) < 500:
        return None

    print(f"  (HTML from {used_url})", end=" ")
    time.sleep(1.5)  # avoid rate-limiting the archive servers
    return cleaned


def ingest_state_dept(year: int, country_filter: list[str] | None = None,
                      html_first: bool = False):
    """
    Extract State Dept report text for all countries in a given year.

    When html_first=True (recommended for 2017+), fetch HTML from the archive
    site and fall back to the local PDF only if HTML is unavailable.
    When html_first=False (default, for 2013–2016), extract the local PDF and
    fall back to HTML only if the PDF fails.

    The slug list is always derived from the PDFs present in the raw directory,
    so PDFs must be downloaded before running this function.
    """
    raw_dir = RAW_DIR / "state-dept" / str(year)
    out_dir = PROCESSED_DIR / "state-dept" / str(year)
    out_dir.mkdir(parents=True, exist_ok=True)

    pdfs = sorted(raw_dir.glob("*.pdf"))
    if country_filter:
        pdfs = [p for p in pdfs if any(f.lower() in p.stem for f in country_filter)]

    mode = "HTML→PDF" if html_first else "PDF→HTML"
    print(f"Ingesting {len(pdfs)} State Dept reports ({year}, {mode})...")
    success, failed, skipped = 0, [], []

    for pdf_path in pdfs:
        slug = pdf_path.stem
        dest = out_dir / f"{slug}.txt"
        if dest.exists():
            skipped.append(slug)
            continue

        print(f"  {slug}...", end=" ", flush=True)

        if html_first:
            text = fetch_html_report(slug, year)
            if text is None:
                raw = extract_pdf_text(pdf_path)
                text = clean_text(raw) if raw is not None else None
        else:
            raw = extract_pdf_text(pdf_path)
            text = clean_text(raw) if raw is not None else None
            if text is None:
                text = fetch_html_report(slug, year)

        if text:
            dest.write_text(text, encoding="utf-8")
            print(f"OK ({len(text):,} chars, {len(text.split())//1000}K words)")
            success += 1
        else:
            print("FAILED")
            failed.append(slug)

    print(f"\nDone: {success} extracted, {len(failed)} failed, {len(skipped)} skipped")
    if failed:
        print("Failed:", failed)


def link_freedom_house(year: int) -> None:
    """
    Create processed-text/freedom-house/{year}/ as a symlink to raw/freedom-house/{year}/.
    FH files are plain text and need no conversion; the symlink makes them visible
    to the rest of the pipeline via the standard processed-text path.
    """
    raw_dir = RAW_DIR / "freedom-house" / str(year)
    link = PROCESSED_DIR / "freedom-house" / str(year)

    if not raw_dir.exists():
        print(f"FH raw dir not found: {raw_dir} — download first.")
        return

    if link.exists() or link.is_symlink():
        n = len(list(link.glob("*.txt"))) if link.is_dir() else 0
        print(f"FH {year}: already linked ({n} files)")
        return

    link.parent.mkdir(parents=True, exist_ok=True)
    link.symlink_to(raw_dir.resolve())
    n = len(list(link.glob("*.txt")))
    print(f"FH {year}: linked → {raw_dir} ({n} files)")


def main():
    parser = argparse.ArgumentParser(
        description="Ingest State Dept PDFs and link Freedom House plain-text files"
    )
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument("--countries", nargs="*", default=None)
    parser.add_argument(
        "--html-first", action="store_true",
        help="Fetch HTML from archive site first, fall back to local PDF "
             "(recommended for 2017+)",
    )
    args = parser.parse_args()
    ingest_state_dept(args.year, country_filter=args.countries,
                      html_first=args.html_first)
    if not args.countries:
        link_freedom_house(args.year)


if __name__ == "__main__":
    main()
