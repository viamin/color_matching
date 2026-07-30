# Printed pair classification vocabulary

Printed pair classifications describe the behavior of **physical printed swatches**. They are not labels for abstract screen RGB colors and do not replace measured or algorithmic results.

## Canonical vocabulary

An **illuminant** is the light under which the printed pair is viewed. The initial canonical values are:

- `lps` — low-pressure sodium
- `red`
- `green`
- `blue`

A **classification** is a human decision about the pair's apparent brightness and illuminant response:

- `strong_metamer` — the pair appears sufficiently similar under one illuminant and separates clearly under another; the strength is subjective.
- `weak_metamer` — the pair shows the same metameric behavior, but the apparent separation is subtle; the strength is subjective.
- `contrasting` — the swatches remain visibly different under the illuminant being classified.

`strong_metamer` and `weak_metamer` must be chosen by a person. The model intentionally has no confidence field. Optional free-form `notes` can record context without becoming part of the primary classification workflow.

## Scope and uniqueness

Each classification belongs to a printed `test_sheet_pair` and a physical reproduction `printer_profile`. A printer profile currently captures print context such as printer, paper, ink, ICC profile, and settings; the association is deliberately named as a reproduction profile so future paint or material profiles remain possible.

A pair may have multiple classifications over time, including historical inactive records. At most one record can be active for each `(printed pair, illuminant, reproduction profile)` combination. Deactivating the current record permits a later classification without deleting history.

## Relationship to pair findings

`PairFinding` and `PairFindingObservation` remain the capture-derived vocabulary of `match`, `near_match`, and `no_match`. They represent observations or computed judgments from the existing capture workflow. `PrintedPairClassification` is a richer, manual product concept that coexists with them: it records a person's illuminant-specific interpretation of physical swatches and does not reinterpret or overwrite capture findings.
