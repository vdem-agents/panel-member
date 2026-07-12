#!/usr/bin/env Rscript
# Generate config/indicator_sections.yaml from vdemdata::codebook.
#
# Writes codebook text (description, question, clarification, categories) for all
# indicators in indicator_section_mapping.csv. Section mappings (state-dept,
# freedom-house) are left as empty arrays for manual completion.
#
# Run from any directory:
#   Rscript /path/to/panel-member/config/generate_indicator_yaml.R

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(vdemdata)
})

# ── Paths ─────────────────────────────────────────────────────────────────────
args        <- commandArgs(trailingOnly = FALSE)
script_file <- sub("--file=", "", args[grep("--file=", args)])
CONFIG_DIR  <- if (length(script_file) && nzchar(script_file)) {
  normalizePath(dirname(script_file))
} else {
  normalizePath(".")
}

MAPPING_CSV <- file.path(CONFIG_DIR, "indicator_section_mapping.csv")
OUTPUT_YAML <- file.path(CONFIG_DIR, "indicator_sections.yaml")

# ── Load data ─────────────────────────────────────────────────────────────────
mapping <- read.csv(MAPPING_CSV, stringsAsFactors = FALSE)
cat(sprintf("Mapping CSV: %d indicators\n", nrow(mapping)))

cb <- vdemdata::codebook |>
  filter(vartype == "C") |>
  select(tag, name, question, clarification, responses)
cat(sprintf("Codebook: %d Type C indicators\n", nrow(cb)))

df <- mapping |>
  left_join(cb, by = c("indicator" = "tag"))

# Exclude interval-scale indicators (responses field is just "Percent." with no
# ordinal categories) — these cannot be used in the ordinal coding pipeline.
INTERVAL_INDICATORS <- c("v2mefemjrn", "v2svstterr")
excluded <- df[df$indicator %in% INTERVAL_INDICATORS, "indicator"]
if (length(excluded) > 0) {
  cat(sprintf("Excluding %d interval-scale indicators: %s\n",
              length(excluded), paste(excluded, collapse = ", ")))
  df <- df[!df$indicator %in% INTERVAL_INDICATORS, ]
}

n_missing <- sum(is.na(df$question))
if (n_missing > 0) {
  cat(sprintf("Warning: %d indicators not found in codebook:\n", n_missing))
  cat(paste(" ", df$indicator[is.na(df$question)], collapse = "\n"), "\n")
}

# ── Parse responses string into category texts ────────────────────────────────
# Format: "0:  text... 1:  text... 2:  text... 3:  text... 4:  text..."
# Some codebook entries use non-breaking spaces (U+00A0) as separators;
# normalize to ASCII space before splitting.
parse_responses <- function(resp) {
  if (is.na(resp) || !nzchar(trimws(resp))) return(character(0))
  resp    <- gsub(" ", " ", resp)     # normalize non-breaking spaces
  cleaned <- sub("^0:[[:space:]]+", "", resp)
  parts   <- strsplit(cleaned, "[[:space:]]+[1-4]:[[:space:]]+")[[1]]
  trimws(parts)
}

# ── YAML formatting helpers ───────────────────────────────────────────────────
wrap_block <- function(text, indent, width = 76) {
  lines <- strwrap(trimws(text), width = width - nchar(indent))
  paste0(indent, lines, collapse = "\n")
}

format_scalar <- function(text, key, indent = "  ") {
  text <- trimws(text)
  if (is.na(text) || !nzchar(text)) return(sprintf("%s%s: null", indent, key))
  if (nchar(text) <= 72 && !grepl('[\n"]', text)) {
    return(sprintf('%s%s: "%s"', indent, key, text))
  }
  body <- wrap_block(text, paste0(indent, "  "))
  sprintf("%s%s: >-\n%s", indent, key, body)
}

format_clarification <- function(text, indent = "  ") {
  if (is.na(text) || !nzchar(trimws(text))) return(sprintf("%sclarification: null", indent))
  format_scalar(text, "clarification", indent)
}

format_category <- function(text, indent = "    ") {
  text <- trimws(text)
  if (nchar(text) <= 70 && !grepl('[\n"]', text)) {
    return(sprintf('%s- "%s"', indent, text))
  }
  body <- wrap_block(text, paste0(indent, "  "))
  sprintf("%s- >-\n%s", indent, body)
}

make_entry <- function(indicator, name, question, clarification, categories) {
  if (length(categories) == 0) {
    warning(sprintf("%s: no categories parsed — skipping", indicator))
    return(NULL)
  }
  lines <- c(
    sprintf("%s:", indicator),
    format_scalar(name, "description"),
    format_scalar(question, "codebook_question"),
    format_clarification(clarification),
    "  categories:",
    sapply(categories, format_category),
    "  state-dept: []",
    "  freedom-house: []"
  )
  paste(lines, collapse = "\n")
}

# ── Generate entries ──────────────────────────────────────────────────────────
cat(sprintf("\nGenerating YAML entries for %d indicators...\n", nrow(df)))

blocks <- list()
n_skipped <- 0L
for (i in seq_len(nrow(df))) {
  row  <- df[i, ]
  name <- if (!is.na(row$name) && nzchar(trimws(row$name))) row$name else row$ind_name
  cats <- parse_responses(row$responses)
  entry <- make_entry(
    indicator     = row$indicator,
    name          = name,
    question      = row$question,
    clarification = row$clarification,
    categories    = cats
  )
  if (is.null(entry)) { n_skipped <- n_skipped + 1L; next }
  blocks[[length(blocks) + 1L]] <- entry
}
if (n_skipped > 0) cat(sprintf("Skipped %d indicators with no parseable categories.\n", n_skipped))

# ── Write YAML ────────────────────────────────────────────────────────────────
header <- "# config/indicator_sections.yaml
#
# Per-indicator codebook text and source document section mappings for the
# panel-member pipeline. Loaded by pipeline/assemble_prompt.py.
#
# Codebook text generated by config/generate_indicator_yaml.R from vdemdata::codebook
# (V-Dem v15). Do not edit the description, codebook_question, clarification, or
# categories fields manually — re-run the script if corrections are needed.
#
#
# Section mappings (state-dept, freedom-house) must be filled in manually.
# See config/indicator_section_mapping.csv for module-level defaults as a starting
# point.
#
# State Dept section keys:
#   1a: Arbitrary/unlawful deprivation of life
#   1b: Disappearance
#   1c: Torture and cruel, inhuman, or degrading treatment
#   1d: Arbitrary arrest or detention
#   1e: Denial of fair public trial
#   1f: Arbitrary interference with privacy
#   1g: Abuses in internal conflict
#   2a: Freedom of expression, including for the press and internet
#   2b: Freedoms of peaceful assembly and association
#   2c: Freedom of religion
#   2d: Freedom of movement
#   3:  Freedom to participate in the political process
#   4:  Corruption and lack of transparency in government
#   5:  Governmental attitude toward international and NGO scrutiny
#   6:  Discrimination, societal abuses, and trafficking in persons
#   7a–7e: Worker rights subsections
#
# Freedom House section keys: A (Electoral Process), B (Political Pluralism),
#   C (Functioning of Government), D (Freedom of Expression), E (Associational
#   Rights), F (Rule of Law), G (Personal Autonomy)
"

output <- paste0(header, "\n", paste(blocks, collapse = "\n\n"), "\n")
writeLines(output, OUTPUT_YAML)
cat(sprintf("Wrote %d entries to %s\n", length(blocks), OUTPUT_YAML))
