# Preregistration / submission checklist

Running list of follow-ups from the OSF preregistration process. Delete items as done.

## Now / near-term

- [ ] **Approve the pending registration.** Status was "Pending approval" (embargoed). Complete the approval action (OSF email link / "Pending approval" dropdown) so it archives. Do not edit the linked project files until it archives.
- [ ] **Embargo end date:** set ~2 years out (e.g., 2028). Can be lifted early; overshoot is safe, undershoot risks auto-publishing mid-review.

## November APSR submission (double-blind / triple-anonymized)

The enforced part is the anonymized manuscript. Before submitting:

- [ ] Manuscript PDF carries **no author name / affiliation**.
- [ ] **Self-citations anonymized** (no "as we showed in Teitelbaum ...").
- [ ] **Do not** put the named repo URL (`github.com/vdem-agents/panel-member`) or a public OSF link in the manuscript.
- [ ] Cite an **anonymized code link** for review (e.g., anonymous.4open.science).
- [ ] Cite the **OSF anonymized view-only link** for the preregistration (generate from the registration's Contributors/Settings; the "anonymized" option strips contributor names). Works even though the registration is embargoed.

## At acceptance / publication

- [ ] **Lift the OSF embargo** (makes the registration public; cite by DOI).
- [ ] **Make the repo public** (if it was set private for review — currently public).
- [ ] **Mint a Zenodo DOI for the repo:** zenodo.org -> Settings -> GitHub -> toggle on `vdem-agents/panel-member` -> cut a GitHub release -> Zenodo archives a frozen snapshot and issues a DOI. (Do this at/after publication, not during blind review — the Zenodo record carries your name.)
- [ ] **Add the Zenodo DOI to the OSF registration Resources** as type "Analytic Code" (the Resources dialog only accepts a DOI, which is why a bare GitHub URL didn't work).
- [ ] Add the repo to the OSF **project** via the GitHub add-on if a browsable live pointer is also wanted.

## Reference

- Timestamp anchor commit at registration time: `a264e95` (pushed to `origin/main`).
- Repo license: MIT (Emmanuel Teitelbaum, 2026).
- OSF paste-ready field text: `preregistration/osf-paste/`.
