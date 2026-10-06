# healthomics-import-repro

A minimal WDL project for investigating a pipeline-service bug report:
importing a workflow from GitHub for the HealthOmics engine was said to drop
subworkflows referenced via relative imports. This repo holds the test cases
built while investigating it, including one theory that was proposed, tested
live against real HealthOmics, and disproven -- keep reading before trusting
old comments in this repo at face value.

## Status

**Confirmed working on real HealthOmics:** a nested entrypoint (`broken/`)
importing one sibling subworkflow by relative path. Live-tested: the subworkflow
task ran and produced real output. The theory that HealthOmics requires the
entrypoint's imports to be relative to the repo root (unlike Cromwell) is
**disproven** -- HealthOmics resolves relative imports the normal WDL way, same
as Cromwell, at least for this case.

**Still untested on real HealthOmics:** `deep-nested/` -- two layers of
subworkflow nesting (a subworkflow that itself imports something) plus
multiple imports at the entrypoint. This is the next thing to verify; the
original bug report is still unexplained if this also turns out to work fine.

**Confirmed, independent of the above:** a genuinely missing/unresolvable
import (`missing-import/`) used to be silently swallowed into an empty input
template by pipeline-service's local WDL parsing, rather than surfaced as an
error. That fix is unrelated to the root-relative theory and remains in place.

## Layout

```
main.wdl              # entrypoint at the repo root -- control case, works everywhere
greet.wdl              # subworkflow task used by main.wdl

broken/
  main.wdl             # entrypoint nested one level down, one import -- CONFIRMED WORKING
  align.wdl            # subworkflow task used by broken/main.wdl

deep-nested/
  main.wdl             # entrypoint with TWO imports, one of which is itself nested -- UNTESTED
  align.wdl            # a subworkflow that itself imports trim.wdl
  qc.wdl               # a second, independent import of main.wdl
  trim.wdl             # imported only by align.wdl, never directly by main.wdl

missing-import/
  main.wdl             # imports a file that doesn't exist anywhere in the repo
```

### `main.wdl` (control)

Imports `greet.wdl` with `import "greet.wdl"`. `main.wdl` lives at the repo
root, so this works everywhere unconditionally. Confirms the fix (or lack of
one) didn't break the trivial case.

### `broken/main.wdl` (one layer, one import -- confirmed working)

Imports `align.wdl` with `import "align.wdl"`, relative to its own directory
(`broken/`) -- standard WDL-spec resolution, what Cromwell expects too. This
is the simplest version of the reported bug, and it now has a confirmed,
live, end-to-end pass on real HealthOmics (the `align` task executed and
printed its expected output). The directory name is a holdover from when this
was believed to be the broken case; see `main.wdl`'s own comment.

### `deep-nested/main.wdl` (two layers, multiple imports -- not yet tested)

`main.wdl` imports both `align.wdl` and `qc.wdl`. `align.wdl` is itself a
subworkflow that imports a third file, `trim.wdl`, which `main.wdl` never
mentions directly:

```
main.wdl
|-- align.wdl   (subworkflow, called via `call align_wf.align`)
|     `-- trim.wdl   (align's own import)
`-- qc.wdl      (plain task, called via `call qc_task.qc`)
```

This is the combination the single-layer `broken/` case doesn't cover: does
HealthOmics correctly pull in a file that's only reachable transitively
(main doesn't import trim.wdl, align.wdl does), and does it correctly handle
more than one import at the same level? If this also runs cleanly, that rules
out nesting depth and import count as explanations and points back toward
something repo- or language-specific (Nextflow, submodules, LFS, case
sensitivity) as the real mechanism behind the original report.

### `missing-import/main.wdl` (genuinely missing file)

Imports `nonexistent.wdl`, which isn't anywhere in the repo -- a true
`WDL.Error.ImportError` under standard resolution, not a root-vs-file
question. Before the fix, pipeline-service's `WDLProjectLoader.get_document()`
caught `ImportError` in the same branch as lenient semantic-validation
warnings and silently returned `None` -- `/v2/description` came back `200`
with an *empty* input template, indistinguishable from "this workflow
genuinely takes no inputs." After the fix, it's raised as a
`ValidationException` naming the missing file. This part of the fix is kept
regardless of how the root-relative question resolves.

## Setup

```bash
cd healthomics-import-repro
git add .
git commit -m "Add deep-nested multi-import test case"
git push
```

If pipeline-service's GitHub integration needs a specific org/connection (AWS
CodeConnections) to see the repo, push it wherever that connection is scoped
to (see the `omics-github` CodeConnections setup referenced in
`lat.md/pipeline-service/engines.md`).

## Testing against pipeline-service

Hit `POST /api/pipelines/v2/description` with `type=github`, `engine=omics`,
and `value` set to a GitHub blob or raw URL, or submit a real run via
`POST /api/pipelines/v2/runs` for the full end-to-end check:

```bash
BASE="https://github.com/<your-user>/healthomics-import-repro/blob/main"

# Control -- expect success, parameters/execution both fine.
curl -X POST "$PIPELINE_SERVICE_URL/api/pipelines/v2/description" \
  -H "x-sc-user-id: you@example.com" -H "x-sc-access-token: $TOKEN" \
  -F "type=github" -F "engine=omics" -F "value=$BASE/main.wdl"

# One layer, one import -- confirmed working; expect success here too.
curl -X POST "$PIPELINE_SERVICE_URL/api/pipelines/v2/description" \
  -H "x-sc-user-id: you@example.com" -H "x-sc-access-token: $TOKEN" \
  -F "type=github" -F "engine=omics" -F "value=$BASE/broken/main.wdl"

# Two layers, multiple imports -- the untested case. Run this one all the way
# to a real submission (POST /v2/runs), not just /v2/description, so both
# align_task and qc actually execute and produce output.
curl -X POST "$PIPELINE_SERVICE_URL/api/pipelines/v2/description" \
  -H "x-sc-user-id: you@example.com" -H "x-sc-access-token: $TOKEN" \
  -F "type=github" -F "engine=omics" -F "value=$BASE/deep-nested/main.wdl"

# Genuinely missing import -- expect 400 naming "nonexistent.wdl".
curl -X POST "$PIPELINE_SERVICE_URL/api/pipelines/v2/description" \
  -H "x-sc-user-id: you@example.com" -H "x-sc-access-token: $TOKEN" \
  -F "type=github" -F "engine=omics" -F "value=$BASE/missing-import/main.wdl"
```

If `deep-nested/main.wdl` also runs cleanly end-to-end (both `align_result`
and `qc_result` populated with real command output), nesting depth and import
count are ruled out too, and the original report likely traces to something
this repo doesn't model yet -- worth trying the same shape in Nextflow next.
