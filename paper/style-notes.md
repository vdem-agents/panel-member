# Prose style reference

Derived from *The Race to the Middle* (Teitelbaum & Ravi, under review), the paper whose
Quarto template this project reuses. Source lives at
`/Users/ejt/Library/CloudStorage/Dropbox/shared-files/Ravi-Teitelbaum/Profits Paper/profits-paper`
(`teitelbaum_ravi.qmd`). These notes exist so drafting stays in EJT's voice instead of
Claude's default register. EJT edits this file freely; when in doubt, the reference paper wins.

## Punctuation EJT uses sparingly (the recurring friction points)

- **Em-dashes: avoid.** The reference paper's body prose has almost none. To set off a
  parenthetical, use a comma-bounded clause, parentheses, or a separate sentence. For a real
  digression, use a footnote. Do not reach for `—`.
- **Colons: rare, and functional only.** Acceptable before a displayed equation or a genuine
  vertical list. Not for appositives, not for a punchy mid-paragraph reveal, not to introduce
  a short list inside a sentence.
- **Semicolons: fine, used with restraint.** Joins two tightly linked independent clauses, or
  separates parallel items that carry internal commas (e.g. the enumerated "predicts that..."
  clauses). Not a substitute for the em-dash.
- **No sentence fragments for emphasis.** No "X. Not Y." construction. Short sentences are
  fine; they stay grammatically complete. "Worst of all, ..." style openers are OK occasionally
  when the sentence is whole.
- En-dash for numeric and range spans: `35–44%`, `2018–2023`, `80 and 95 percent`.

## Register and diction

- Plain, precise, academic. No hype adverbs as openers ("Crucially,", "Strikingly,",
  "Notably,", "Importantly,"). Let the claim carry itself.
- One vivid phrase every few paragraphs, not every sentence ("race to the middle", "hiding
  their light under a bushel", "name and shame"). Deployed deliberately, never stacked.
- Coined mechanism labels are italicized on first use and on later re-use: *external oversight
  premium*, *halo hazard*, *negative information dominance*. If this paper names mechanisms,
  follow the same convention.
- First person plural: "We argue", "We test", "We identify three mechanisms". Standard.
- Contractions only inside a rhetorical question ("so why don't firms invest more?"), otherwise
  spelled out.
- Define a term once, then use it. Flag terminology choices to the reader when a shorthand is
  introduced ("for readability we often call the expected-profit estimates 'predictions'").
- No AI/corporate register: "leverage", "delve", "it's worth noting that", "a key insight",
  "this underscores", "robust framework", stacked tricolons. Cut throat-clearing.

## Sentence and paragraph shape

- Paragraphs run 4–8 sentences and develop one point: topic sentence states a claim, middle
  sentences support and cite, last sentence turns to the stake or the implication.
- Sentences are medium length and declarative. Subordinate clauses set off with commas:
  "Because a buyer cannot verify it at the point of sale, its quality becomes known only
  through the signals a firm chooses to send."
- Enumerate expectations/claims as "First, ... Second, ... Third, ... Finally, ..." across
  consecutive paragraphs, not as a bullet list, when each needs a paragraph of development.
- Paragraph and sentence openers that recur: "Yet", "But", "Moreover", "Consequently", "In
  contrast", "Together they...". A rhetorical question can close a setup paragraph to motivate
  the next.

## Structure

- Level-1 headings: title case, short noun phrases ("Estimation Strategy", "Expected Profits",
  "Discussion", "Conclusion"). Experiments/analyses can be their own sections
  ("Experiment 1: Certifications") rather than sitting under a single "Results".
- Level-2 headings: `##`, also title case.
- Introduction ends with a one-sentence roadmap ("The sections that follow develop the theory,
  test it across three conjoint experiments, and return to its implications for regulation.").
- Footnotes carry caveats, definitions, procedural detail, and robustness notes so the body
  stays clean. Use them.
- Discussion and Conclusion are separate sections. Conclusion opens by restating what the
  study set out to explain, then gives limits, then a forward-looking close.

## Numbers and evidence

- Report point estimates and intervals in plain prose: "Predicted profits following positive
  stories ... ($5.54) ... were indistinguishable from the $4.72 baseline." "the 95% credible
  intervals fell entirely outside the baseline range".
- Percent changes as comparisons and ranges: "nearly 50% higher profits", "from a 92% increase
  ... to 185%".
- `%` in body prose; "percent" spelled out in figure captions. Comma thousands separators
  (`2,014 respondents`).

## Figure and table captions

- Full sentences. Order: what the figure shows, then what the visual elements mean, then the
  method. Example: "Points are posterior means; thick bars and thin lines show 80 and 95
  percent credible intervals. The dashed line marks baseline profit. Estimates come from
  hierarchical Bayes profit simulations with Nash equilibrium pricing."

## Title and abstract

- Main title short and evocative; subtitle is the descriptive academic version.
- Abstract is one paragraph, ~180 words, no citations, no numbered results: puzzle, then "We
  explain this puzzle by asking...", then the theory in a sentence, then "We test this theory
  with...", then findings compressed into one or two sentences, then a closing implication.

## Citations

- Pandoc syntax. Bracketed multi-cite is semicolon-separated: `[@ORourke2003; @Locke2013]`.
- Narrative form when the author is the sentence subject: `@Devinney2010 famously dismissed...`.
- Suppressed-author form where needed: `[-@Allenby2014a]`.

## Working method for Claude on this paper

- EJT asked for drafting help here, so drafting prose is in scope (the usual "flag it, let me
  write it" default is relaxed for the paper body). But expect EJT to rewrite drafts into his
  voice; keep drafts plain and short rather than polished-and-ornate.
- When the problem is structural (a claim needs support, two numbers collide, the mechanism is
  ambiguous), say that plainly instead of papering over it with prose.
- Keep chat replies short. Don't restate EJT's own words back to him.
