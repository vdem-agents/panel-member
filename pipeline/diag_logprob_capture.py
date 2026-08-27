"""
Small probe: does vLLM return usable chat-completion logprobs for a base-style rating call?

Run against a live OpenAI-compatible server (local vLLM). Prints a per-request
breakdown so we can see *where* capture fails:

  A) response.choices[0].logprobs is None / missing
  B) logprobs.content is empty
  C) content present but rating-digit top_logprobs empty / extractor returns None
  D) extractor returns a usable rating_dist

Usage (server already up, env VLLM_BASE_URL / VLLM_API_KEY set):
  python3 -m pipeline.diag_logprob_capture
  N=20 CONCURRENT=8 python3 -m pipeline.diag_logprob_capture
"""
from __future__ import annotations

import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

from openai import OpenAI

from pipeline.code_country_year import _extract_rating_dist

MODEL = os.environ.get(
    "DIAG_MODEL", "meta-llama/Llama-3.3-70B-Instruct"
)
BASE_URL = os.environ.get("VLLM_BASE_URL", "http://localhost:8000/v1")
API_KEY = os.environ.get("VLLM_API_KEY", "local")
N = int(os.environ.get("N", "12"))
CONCURRENT = int(os.environ.get("CONCURRENT", "1"))
TOP_LOGPROBS = int(os.environ.get("TOP_LOGPROBS", "20"))

# Minimal V-Dem-shaped rating prompt. Shared few-shot block is repeated so consecutive
# requests share a large common prefix (the base-model pattern that missed ~65%).
FEWSHOT_BLOCK = """You are coding V-Dem indicators. Reply with JSON only:
{"rating": <integer>, "justification": "<one sentence>"}

Examples (shared prefix — do not copy these ratings blindly):
Country: Alpha, Year: 2010, Indicator: media bias.
Evidence: The press is plural and opposition outlets operate freely.
{"rating": 4, "justification": "Broad, plural coverage of opposition."}

Country: Beta, Year: 2010, Indicator: media bias.
Evidence: Only state media; opposition is never covered.
{"rating": 0, "justification": "No opposition coverage in major media."}

Country: Gamma, Year: 2010, Indicator: media bias.
Evidence: Some critical outlets exist but face harassment.
{"rating": 2, "justification": "Partial criticism with constraints."}
""" + ("# pad " + ("x" * 200) + "\n") * 40  # ~8k chars of shared padding


def _messages(i: int, long_prefix: bool) -> list[dict]:
    system = FEWSHOT_BLOCK if long_prefix else (
        'Reply with JSON only: {"rating": <0-4>, "justification": "<one sentence>"}'
    )
    user = (
        f"Country: ProbeLand-{i}, Year: 2019, Indicator: media bias.\n"
        f"Evidence: Mixed coverage; major outlets mostly favor the incumbent "
        f"but a few critical papers remain. Request id={i}.\n"
        f"What is the rating?"
    )
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]


def _classify(response) -> dict:
    choice = response.choices[0]
    raw = choice.message.content or ""
    lp = choice.logprobs
    out = {
        "text_ok": '"rating"' in raw,
        "logprobs_obj": lp is not None,
        "content_n": None,
        "rating_dist": None,
        "bucket": "A_no_logprobs_obj",
    }
    if lp is None:
        return out
    content = getattr(lp, "content", None)
    if content is None:
        out["bucket"] = "A_no_logprobs_obj"
        return out
    out["content_n"] = len(content)
    if len(content) == 0:
        out["bucket"] = "B_empty_content"
        return out
    # Peek at first digit-ish top_logprobs richness
    n_with_top = sum(1 for t in content if getattr(t, "top_logprobs", None))
    out["tokens_with_top_logprobs"] = n_with_top
    dist = _extract_rating_dist(content, max_rating=4)
    out["rating_dist"] = dist
    if dist is None:
        out["bucket"] = "C_extract_miss"
    else:
        out["bucket"] = "D_ok"
        out["exp"] = round(sum(i * p for i, p in enumerate(dist)), 4)
    return out


def _one(client: OpenAI, i: int, long_prefix: bool) -> dict:
    resp = client.chat.completions.create(
        model=MODEL,
        messages=_messages(i, long_prefix=long_prefix),
        temperature=0,
        max_tokens=128,
        logprobs=True,
        top_logprobs=TOP_LOGPROBS,
    )
    row = _classify(resp)
    row["i"] = i
    row["long_prefix"] = long_prefix
    row["raw_preview"] = (resp.choices[0].message.content or "")[:80].replace("\n", " ")
    return row


def main() -> int:
    print(f"=== logprob capture probe ===")
    print(f"base_url={BASE_URL}  model={MODEL}  N={N}  concurrent={CONCURRENT}  top_logprobs={TOP_LOGPROBS}")
    client = OpenAI(base_url=BASE_URL, api_key=API_KEY)

    # Half short, half long-prefix (base-like)
    jobs = [(i, i >= N // 2) for i in range(N)]
    rows = []
    if CONCURRENT <= 1:
        for i, long_prefix in jobs:
            rows.append(_one(client, i, long_prefix))
            print(f"  [{rows[-1]['bucket']}] i={i} long={long_prefix} content_n={rows[-1]['content_n']} dist={rows[-1]['rating_dist']}")
    else:
        with ThreadPoolExecutor(max_workers=CONCURRENT) as ex:
            futs = {ex.submit(_one, client, i, lp): (i, lp) for i, lp in jobs}
            for fut in as_completed(futs):
                row = fut.result()
                rows.append(row)
                print(f"  [{row['bucket']}] i={row['i']} long={row['long_prefix']} content_n={row['content_n']} dist={row['rating_dist']}")

    from collections import Counter
    counts = Counter(r["bucket"] for r in rows)
    long_ok = sum(1 for r in rows if r["long_prefix"] and r["bucket"] == "D_ok")
    long_n = sum(1 for r in rows if r["long_prefix"])
    short_ok = sum(1 for r in rows if (not r["long_prefix"]) and r["bucket"] == "D_ok")
    short_n = sum(1 for r in rows if not r["long_prefix"])

    print("\n=== SUMMARY ===")
    for k in sorted(counts):
        print(f"  {k}: {counts[k]}/{len(rows)}")
    print(f"  short-prefix OK: {short_ok}/{short_n}")
    print(f"  long-prefix  OK: {long_ok}/{long_n}")
    n_ok = counts.get("D_ok", 0)
    if n_ok == len(rows):
        print("VERDICT: logprobs OK on this server — capture miss is likely batch/path specific.")
        return 0
    if n_ok == 0:
        print("VERDICT: logprobs broken on this server — fix vLLM/API flags before any re-run.")
        return 2
    print("VERDICT: INTERMITTENT — matches the ~50-66% production miss pattern; dig into bucket mix.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
