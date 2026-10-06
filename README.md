# healthomics-import-repro

A minimal WDL project for investigating a pipeline-service bug report:
importing a workflow from GitHub for the HealthOmics engine was said to drop
subworkflows referenced via relative imports. This repo holds the test cases
built while investigating it, including one theory that was proposed, tested
live against real HealthOmics, and disproven -- keep reading before trusting
old comments in this repo at face value.

## Status

**Confirmed working on real HealthOmics, live-tested, full execution:**

- `broken/` -- a nested entrypoint importing one sibling subworkflow by
  relative path. The theory that HealthOmics requires the entrypoint's
  imports to be relative to the repo root (unlike Cromwell) is **disproven**
  -- it resolves relative imports the normal WDL way, same as Cromwell.
- `deep-nested/` -- two layers of subworkflow nesting (`align.wdl` imports
  `trim.wdl`, which `main.wdl` never references directly) *and* multiple
  imports at the entrypoint (`align.wdl` + `qc.wdl`). All three tasks ran and
  produced correct output, including `trim`'s output flowing into
  `align_task`. This rules out nesting depth and import count as
  explanations too.

With both breadth and depth confirmed working, a general "HealthOmics drops
subworkflows" platform limitation looks unlikely for same-directory or
nested-subdirectory imports. But there's a shape none of the above actually
tests, and it turns out to be the shape the original bug report's likely
source repo (theiagen/public_health_bioinformatics) actually uses:

- `category-import/` -- an import that goes **up and back down** across
  sibling directory trees (`workflows/genomic_characterization/main.wdl`
  importing `../../tasks/qc/task_qc.wdl`), rather than a sibling file in the
  same directory. **Untested.** Theiagen's own contributing docs describe
  exactly this convention -- tasks under `tasks/<category>/`, workflows under
  `workflows/<category>/`, imported via `../` traversal -- which `broken/` and
  `deep-nested/` don't exercise at all; they only import files sitting next to
  the entrypoint.

Why this matters: if AWS HealthOmics's git-based `CreateWorkflow` packaging
does a sparse checkout or zip scoped to the entrypoint's own subdirectory
(rather than the whole repo) -- the mirror image of the original, disproven
theory -- same-directory imports would keep working exactly as observed, but
`../` traversal trying to escape that subtree would fail to resolve and the
import would get silently dropped. That's consistent with everything
confirmed so far *and* gives a concrete mechanism matching real-world repo
layout, unlike the nesting-depth/import-count theories that are now ruled
out.

**Confirmed, independent of all of the above:** a genuinely missing/
unresolvable import (`missing-import/`) used to be silently swallowed into an
empty input template by pipeline-service's local WDL parsing, rather than
surfaced as an error. That fix doesn't depend on any of the root-relative
theory and remains in place regardless of how the rest of this shakes out.

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

category-import/
  workflows/
    genomic_characterization/
      main.wdl         # imports "../../tasks/qc/task_qc.wdl" -- UNTESTED
  tasks/
    qc/
      task_qc.wdl      # two directories away from the entrypoint
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

### `deep-nested/main.wdl` (two layers, multiple imports -- confirmed working)

`main.wdl` imports both `align.wdl` and `qc.wdl`. `align.wdl` is itself a
subworkflow that imports a third file, `trim.wdl`, which `main.wdl` never
mentions directly:

```
main.wdl
|-- align.wdl   (subworkflow, called via `call align_wf.align`)
|     `-- trim.wdl   (align's own import)
`-- qc.wdl      (plain task, called via `call qc_task.qc`)
```

Live-tested end to end: all three tasks ran, including `trim`'s output
correctly flowing into `align_task` (`"Aligning World using: Trimming reads
for World..."`), plus `qc` running independently. This rules out both nesting
depth and import count as explanations -- HealthOmics correctly pulls in a
file that's only reachable transitively (main doesn't import `trim.wdl`,
`align.wdl` does) and handles multiple imports at the same level fine.

### `category-import/workflows/genomic_characterization/main.wdl` (cross-directory `../` import -- untested)

Imports `../../tasks/qc/task_qc.wdl`: up two directories from the entrypoint's
own location, then back down into a sibling tree. This mirrors the real
directory convention used by theiagen/public_health_bioinformatics (workflows
under `workflows/<category>/`, tasks under `tasks/<category>/`, wired together
with `../` imports per their own contributing docs) rather than the
same-directory imports every other case here uses. Not yet tested against
real HealthOmics -- this is the next thing worth running live.

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

# Two layers, multiple imports -- confirmed working; expect success here too.
curl -X POST "$PIPELINE_SERVICE_URL/api/pipelines/v2/description" \
  -H "x-sc-user-id: you@example.com" -H "x-sc-access-token: $TOKEN" \
  -F "type=github" -F "engine=omics" -F "value=$BASE/deep-nested/main.wdl"

# Genuinely missing import -- expect 400 naming "nonexistent.wdl".
curl -X POST "$PIPELINE_SERVICE_URL/api/pipelines/v2/description" \
  -H "x-sc-user-id: you@example.com" -H "x-sc-access-token: $TOKEN" \
  -F "type=github" -F "engine=omics" -F "value=$BASE/missing-import/main.wdl"

# Cross-directory "../" import, mirroring the real theiagen repo convention --
# UNTESTED. This is the one most likely to actually reproduce the bug report.
curl -X POST "$PIPELINE_SERVICE_URL/api/pipelines/v2/description" \
  -H "x-sc-user-id: you@example.com" -H "x-sc-access-token: $TOKEN" \
  -F "type=github" -F "engine=omics" \
  -F "value=$BASE/category-import/workflows/genomic_characterization/main.wdl"
```

Both `broken/` and `deep-nested/` are now confirmed working end-to-end on
real HealthOmics (live-tested, not just description). But those only cover
same-directory imports. `category-import/` tests the shape actually used by
theiagen/public_health_bioinformatics -- the likely source of the original
bug report -- importing across sibling directories via `../`. Run that one
live before looking anywhere else; if it fails where `broken/` and
`deep-nested/` succeeded, that's the bug, and it points at how HealthOmics's
git-based `CreateWorkflow` scopes its checkout/zip rather than at WDL nesting
or import count. If `category-import/` also succeeds, Nextflow's `include`
resolution (untested -- pipeline-service's Nextflow loader doesn't parse
`include` locally at all) is the next thing to try.
