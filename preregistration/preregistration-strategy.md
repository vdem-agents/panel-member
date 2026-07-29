# Preregistration Strategy: OSF, EGAP, and What to Make Public

*From a design discussion 2026-07-21. Captures the reasoning behind the preregistration
platform choice, how OSF registrations actually work mechanically, the GitHub-linking
plan, and what should and shouldn't be made public and when. Written to be picked back up
later without re-deriving any of this.*

---

## Why no single template fits

This study straddles two preregistration traditions that don't have a shared home:

- **Political science / social science preregistration** (EGAP, OSF's general template,
  the pre-analysis-plan tradition in comparative politics and development economics):
  emphasizes hypotheses, sample, outcome definitions, exclusion criteria, and an analysis
  plan locked before data are touched.
- **NLP/ML evaluation preregistration**: much less standardized as a formal registry
  practice, but the same logic applies to model/prompt/decoding choices — which model
  versions, which prompts, which decoding parameters, which metrics — recorded before
  looking at outputs. No mainstream registry (OSF or otherwise) has form fields for this.

Neither tradition alone covers this study. The plan below leans on OSF for the
structured, citable registration and hypothesis/design content, and treats the exact
technical artifacts (prompts, code, checkpoints) as a separate, linked replication
package rather than trying to force them into form fields that don't fit them.

---

## Template landscape

| Option | What it's for | Verdict |
|---|---|---|
| **OSF Preregistration** | General-purpose, comprehensive; detailed prompts on design, sample, variables, analysis plan. Best default when nothing discipline-specific fits. | **Primary choice.** |
| **OSF: Preregistration for Studies with Existing Data** | Built for secondary-data analysis from public databases or prior research; asks explicitly what you already know about the dataset and what steps you took to avoid contamination from that prior exposure. | Strong alternative/companion — maps almost directly onto the "Pilot work disclosure" section already in `docs/experimental-design.md` (V-Dem v15 coder-level data already exists and is public; source documents for the confirmatory years are already ingested; a 98-CYI re-identification pilot and an unanalyzed 8B smoke test were run before the design was locked). |
| **AsPredicted.org** | Short-form, ~9 questions, minimal justification prompts. | Redundant once the fuller OSF document exists; skip. |
| **EGAP Registry** | Political-science-native registry for experiments and observational studies in governance/politics; simple web form, renders to a static PDF. | Disciplinary visibility your poli-sci reviewers will recognize without explanation, but no versioned project, no preprint/data/publication linking, no embargo mechanism. **Worth registering here too, in addition to OSF, once the OSF version exists** — nothing stops doing both, and EGAP registration is quick once the design text already exists. |

**Recommendation**: register the design on **OSF** as the primary, structured record
(it's the one that supports the full project → registration → preprint → published-article
chain you want), and separately submit the same design to **EGAP** for disciplinary
recognition.

---

## Mapping what already exists onto OSF's fields

Most of the "template-filling" work is already done — `docs/experimental-design.md` reads
close to a full PAP already:

| Typical OSF field | Already drafted |
|---|---|
| Hypotheses | Hypotheses 1–9, `docs/experimental-design.md` |
| Design / conditions / manipulations | 4-condition × 4-model table |
| Sample / eligibility criteria | Evaluation sample section (min-coders, years, pools) |
| Variables (IV/DV/moderators) | Outcome variables table |
| Analysis plan (tests, thresholds, corrections) | Primary outcomes, bootstrap procedure, k=1 divergence threshold, name-swap pairing rule |
| Existing-data disclosure | Pilot work disclosure section |
| Exploratory vs. confirmatory | Part 3 already labels everything exploratory/unregistered explicitly |

Next concrete step (not yet done): port this content into the actual OSF form fields,
section by section.

## The CS/NLP gap the templates don't cover

Neither OSF template has fields for model checkpoints, exact prompt text, decoding
parameters, or adapter hashes. `docs/experimental-design.md` already handles this the
right way by saying weights/hyperparameters/checkpoint IDs belong in the replication
package, not the prereg document itself. Keep that split:

- OSF form → hypotheses, design, sample, analysis plan (the parts a template has fields for).
- A frozen git tag/commit in the GitHub repo → the exact technical artifacts (prompt
  template, condition-assembly code, adapter identifiers once they exist).

---

## How an OSF registration actually works (mechanically)

Not a document upload — an actual structured web form:

1. Create (or select) an OSF **project** — this is the long-lived container for
   data/code/materials, and stays editable indefinitely even after a registration is made.
2. From OSF Registries, **"New Registration"** → pick a template.
3. You get a **draft**: sections listed as tabs across the top, each with its own text
   fields, typed into directly. **Autosaves**; collaborators can be added with
   Read/Read+Write/Admin permissions, so it doesn't need to happen in one sitting.
4. **Submit** → other project admins get 48 hours to approve or reject; auto-approves if
   nobody acts.
5. At submission, choose **public immediately** or **embargo up to 4 years**.
6. Once approved, the registration is an **immutable, timestamped snapshot** — gets a DOI
   (via DataCite) if public, can never be edited again (only "withdrawn," which keeps the
   metadata but marks it retracted).
7. The **project** around it keeps evolving — that's where the eventual preprint and
   published-article links get attached, all cross-referenced back to the frozen
   registration.

### Is any of this blockchain-secured? No.

OSF is a centralized platform run by the Center for Open Science (a nonprofit).
"Immutable" means the application layer disables edits after approval — enforced by
policy and access control, not by cryptography or a decentralized ledger. The trust model
is closer to a notary than a blockchain: you're trusting COS's software and institutional
practices, not verifying anything independently via a hash chain or consensus mechanism.
The DOI (via DataCite) is a real, persistent, citable, resolvable identifier, but DOI
issuance isn't cryptographic either — it's standard scholarly infrastructure. Some
researchers supplement OSF with actual blockchain timestamping (e.g., the academic
Bloxberg consortium, or generic tools like OriginStamp) when they want cryptographic
tamper-evidence, typically for priority-dispute concerns. Not needed here — OSF is the
field standard and reviewers/journals treat it as sufficient.

---

## GitHub linking plan

OSF has a native GitHub add-on, so nothing needs to be duplicated by hand.

**How the add-on works:**
- Connect one GitHub repo per OSF project (additional repos can link to sub-components)
  via OAuth. **Works with private repos** — no requirement that the repo be public.
- The connection is **live and bidirectional** for the ongoing project: edits on GitHub
  show up in OSF and vice versa.
- **At registration time, OSF archives a frozen snapshot** of the connected content into
  the registration (saved into an "Archive of GitHub" folder in OSF Storage). Some
  completeness limits are reported for large repos/certain file types — worth eyeballing
  the archive once it's actually created rather than assuming a byte-perfect mirror.

**The important subtlety**: the archived snapshot's *visibility* is governed by the
**registration's own public/embargo setting** — not by the live GitHub repo's privacy.
Connecting a private repo and later making the *registration* public will expose the
archived snapshot regardless of whether the live GitHub repo itself is ever made public.
The freeze point is **submission time**, not the moment something becomes public — if
embargoed and later unembargoed, what appears is still the original submission-time
snapshot, not a re-sync to whatever the repo looks like by then. Commits pushed after
registration are invisible to it entirely; they only become public whenever the live
GitHub repo (or a later, separate OSF update) is separately made public.

**Practical mitigation**: don't wire the entire repo into what gets archived into the
public-facing registration. Keep the full live GitHub connection as an internal/private
part of the OSF project, and when filling in the registration's materials/data fields,
point to *specific* things — particular files, a particular commit SHA — rather than
letting OSF snapshot the whole tree. GitHub commit-SHA URLs
(`https://github.com/vdem-agents/panel-member/tree/<sha>`) are independently permanent and
verifiable, and give a second, low-tech anchor alongside OSF's own archive.

---

## What to actually make public / link to

**Core materials (link these — the actual instrument of the study):**
- `docs/experimental-design.md` — backs most of the OSF form fields directly
- `docs/overview.md` — framing/motivation
- `prompts/panel-member-coding-prompt.md` — the actual prompt template. Single
  highest-value artifact to make public: for an NLP/CS reader this *is* the instrument,
  the way survey question wording is in a standard poli-sci study.
- `config/indicator_sections.yaml` — the indicator-to-section mapping; an inspectable
  methodological choice, not just an implementation detail.

**Strong value-add (include if comfortable with the code being read closely):**
- `docs/architecture.md` and the core pipeline scripts that define *what the study does*:
  `assemble_prompt.py`, `extract_sections.py`, `anonymize_section.py`,
  `summarize_indicator.py`, `code_country_year.py`, `run_coding_batch.py`. Lets a skeptical
  reader verify there's no hidden researcher-degrees-of-freedom in how conditions are
  constructed.
- The stronger `notes/*.md` files: `evaluation-metrics.md`, `fewshot-example-design.md`,
  `summarization-strategy.md`, `exec-summary-policy-and-summarization-condition.md`,
  `indicator-selection.md`, `vdem-data-filtering.md`, `mechanism-test-design.md`,
  `evaluation-indicator-scope.md`, `data-leakage-contamination.md`,
  `finetune-validation-split-leakage.md`, `finetune-training-target.md`. These would
  strengthen a reader's confidence,
  not just satisfy a formality — genuinely good methodology writeups. The last of these
  documents a defect caught and corrected *before* registration (a coder-row-level
  internal train/eval split in the fine-tuning script, found after three full training
  runs, all discarded without inference or evaluation and disclosed in the design doc's
  Pilot work disclosure). Including it publicly is the right call: it is exactly the
  kind of transparent self-correction preregistration exists to document, and the
  disclosure in `docs/experimental-design.md` already commits us to the fact of the
  discarded runs.

**Lower priority / optional (no harm either way):**
- `docs/implementation-strategy.md`, `slurm/*.sh`, HPC-specific notes
  (`hpc-execution-strategy.md`, `finetuning-epochs.md`, `finetune-preflight-checklist.md`,
  `learning-curve.md`). Useful for literally rerunning the cluster jobs, not informative
  to a general reader.

**Leave out of what gets linked, even though it's accurate:**
- `docs/todo.md` — internal task tracker in tone; not something to hand a reviewer even
  though its content is currently honest and correct.

**Hold back deliberately:**
- `notes/follow-on-benchmarking-paper.md` and `notes/substitution-experiment-future-paper.md`
  — discuss unannounced follow-on work; going public tips off competitors before that work
  is ready to be its own paper.
- Not yet reviewed for public-readiness: `notes/persona-prompting-design-archive.md`,
  `notes/linear-probe-country-identity.md`, `notes/section-coverage.md`,
  `notes/evaluation-metric-options.md`, `notes/loo-mae-computation.md`,
  `notes/hpc-sequencing-strategy.md.archive`. Worth a quick pass before deciding.

**Compliance flag (separate from any style/embarrassment question):** V-Dem's
*coder-level* (disaggregated) dataset may carry its own data-use/redistribution terms
distinct from the standard public country-year V-Dem release. Confirm redistribution is
actually permitted before publicly linking anything containing it — this is a data-provider
compliance question, not a curation choice. `human_ratings.csv` is currently a symlink to
a `shared/` location outside this repo's git tracking, so it wouldn't be swept into a
GitHub snapshot by default, but if it's ever deposited directly as an OSF data component,
that's the moment to check V-Dem's terms.

**Already checked and clean**: searched full git history for `.env`/secret/credential
patterns — nothing was ever committed, and `.env` is properly gitignored. No cleanup
needed on that front before connecting the repo (publicly or privately).

**One general caveat**: git history is permanent even if current files are later edited —
a normal commit that "fixes" something leaves the old version fully recoverable in the
log. If anything ever needs to actually disappear rather than be superseded, that requires
rewriting history and force-pushing, not just a new commit. Nothing currently in the repo
appears to need this.

---

## Open items to pick back up later

1. Decide OSF-only vs. OSF + EGAP (lean: both).
2. Draft the actual field-by-field text for the OSF "Preregistration" (or "Existing Data")
   form, pulling from `docs/experimental-design.md`.
3. Set up the OSF project and connect the GitHub add-on (repo can stay private for now).
4. Do a quick read-through of the not-yet-reviewed `notes/*.md` files listed above before
   deciding what's public-ready.
5. Confirm V-Dem's coder-level data redistribution terms before depositing any derived
   data files publicly.
6. Decide the actual public/embargo timing for both the OSF registration and the GitHub
   repo itself — these are independent decisions and don't need to happen at the same time.

## References

- [Choosing the Right Preregistration Template: A Guide for Researchers](https://www.cos.io/blog/choosing-preregistration-template-guide-for-researchers)
- [Preregistration – Center for Open Science](https://www.cos.io/initiatives/prereg)
- [Registry – EGAP](https://egap.org/registry/)
- [Welcome to Registrations & Preregistrations! – OSF Support](https://help.osf.io/article/330-welcome-to-registrations)
- [Start a Registration – OSF Support](https://help.osf.io/help.osf.io/article/162-start-a-registration)
- [Manage Draft Registrations – OSF Support](https://help.osf.io/article/165-manage-your-draft-registration)
