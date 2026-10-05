# healthomics-import-repro

A minimal WDL project for exercising the pipeline-service bug where importing
a workflow from GitHub for the HealthOmics engine drops subworkflows. It covers
both halves of the fix with three small workflows.

## Layout

```
main.wdl              # entrypoint at the repo root -- the control case, works everywhere
greet.wdl              # subworkflow task used by main.wdl

broken/
  main.wdl             # entrypoint nested one level down -- root-relative mismatch
  align.wdl            # subworkflow task used by broken/main.wdl

missing-import/
  main.wdl             # imports a file that doesn't exist anywhere in the repo
```

### `main.wdl` (control)

Imports `greet.wdl` with `import "greet.wdl"`. Because `main.wdl` lives at the
repo root, "relative to the importing file" and "relative to the repo root"
are the same path, so this works on Cromwell, on real AWS HealthOmics, and in
pipeline-service's local WDL parsing, both before and after the fix. Use this
to confirm the fix didn't break the normal case.

### `broken/main.wdl` (root-relative mismatch -- the bug as reported)

Imports `align.wdl` with `import "align.wdl"` -- relative to its own directory
(`broken/`), the normal WDL-spec convention that Cromwell's `workflowUrl`-based
HTTP import resolution also expects. It resolves fine locally (miniWDL finds
`broken/align.wdl`) and fine on Cromwell. **AWS HealthOmics resolves the
entrypoint's own imports relative to the repository root, not the importing
file's directory**, so it looks for `align.wdl` at the repo root -- which
doesn't exist -- and can't build the workflow.

Because the import resolves fine locally, pipeline-service's own
`/v2/description` parse step has no reason to object pre-fix -- it returns a
full, correct input template. The break only shows up later, opaquely, when
AWS itself rejects the workflow during `create_workflow()`. The fix adds a
pre-flight check (`WDLProjectLoader.validate_imports_relative_to_root`) that
catches this mismatch locally, in both the describe step and workflow
creation, instead of letting AWS fail first.

### `missing-import/main.wdl` (genuinely missing file -- the other half of the fix)

Imports `nonexistent.wdl`, which isn't anywhere in the repo. This is a true
`WDL.Error.ImportError` even under standard (relative-to-file) resolution.
Before the fix, `WDLProjectLoader.get_document()` caught `ImportError` in the
same branch as lenient semantic-validation warnings and silently returned
`None` -- `/v2/description` came back `200` with an *empty* input template,
indistinguishable from "this workflow genuinely takes no inputs." After the
fix, it's raised as a `ValidationException` naming the missing file.

## Setup

Push this directory as its own repo (a throwaway/scratch repo is fine):

```bash
cd healthomics-import-repro
git init
git add .
git commit -m "WDL repro for HealthOmics GitHub import bug"
git branch -M main
git remote add origin git@github.com:<your-user>/healthomics-import-repro.git
git push -u origin main
```

If pipeline-service's GitHub integration needs a specific org/connection (AWS
CodeConnections) to see the repo, push it wherever that connection is scoped to
(see the `omics-github` CodeConnections setup referenced in
`lat.md/pipeline-service/engines.md`).

## Testing against pipeline-service

Hit `POST /api/pipelines/v2/description` with `type=github` and `value` set to
a GitHub blob or raw URL, `engine=omics`. Try all three entrypoints:

```bash
BASE="https://github.com/<your-user>/healthomics-import-repro/blob/main"

# Control -- expect 200 with the "name" parameter, before and after the fix.
curl -X POST "$PIPELINE_SERVICE_URL/api/pipelines/v2/description" \
  -H "x-sc-user-id: you@example.com" -H "x-sc-access-token: $TOKEN" \
  -F "type=github" -F "engine=omics" -F "value=$BASE/main.wdl"

# Root-relative mismatch.
# Before fix: 200, full input template (looks fine; breaks later at AWS).
# After fix:  400, ValidationException naming "align.wdl".
curl -X POST "$PIPELINE_SERVICE_URL/api/pipelines/v2/description" \
  -H "x-sc-user-id: you@example.com" -H "x-sc-access-token: $TOKEN" \
  -F "type=github" -F "engine=omics" -F "value=$BASE/broken/main.wdl"

# Genuinely missing import.
# Before fix: 200, EMPTY input template ({"inputs": []}).
# After fix:  400, ValidationException naming "nonexistent.wdl".
curl -X POST "$PIPELINE_SERVICE_URL/api/pipelines/v2/description" \
  -H "x-sc-user-id: you@example.com" -H "x-sc-access-token: $TOKEN" \
  -F "type=github" -F "engine=omics" -F "value=$BASE/missing-import/main.wdl"
```

Re-run the `broken/main.wdl` request with `-F "engine=cromwell"` -- it should
succeed on Cromwell both before and after the fix (Cromwell fetches `align.wdl`
via a relative HTTP URL against `workflowUrl`, so it never hits the root-
relative requirement). This confirms the asymmetry the original bug report
described: Cromwell already handles it, HealthOmics doesn't.

For a full end-to-end check, `POST /api/pipelines/v2/runs` with the same
`workflow_entrypoint` values and `engine=omics`. `broken/main.wdl` and
`missing-import/main.wdl` should now fail fast with the same
`ValidationException`/400 during `create_workflow()`, instead of reaching AWS
and failing opaquely (or, for `missing-import`, instead of silently trying to
create a workflow nobody actually validated).

## A known gap to be aware of

The pre-flight check (and pipeline-service's local WDL parsing generally) can
only validate the *standard* WDL resolution rule -- relative to the importing
file. AWS's "resolve the entrypoint's imports relative to the repo root" rule
means a workflow with a **nested** main file that deliberately writes its
imports as root-relative text (e.g. `broken/main.wdl` importing
`"broken/align.wdl"` instead of `"align.wdl"`) would actually run fine on real
HealthOmics, but pipeline-service's local miniWDL parse can't resolve that
import at all (miniWDL only knows "relative to the importing file", not "repo
root") and will now raise `ValidationException` for it via the
`WDL.Error.ImportError` fix -- a false rejection of an AWS-valid layout. In
practice this is avoided by keeping the main file at the repo root, as
`main.wdl` above does -- which is also the simplest thing to tell a user who
hits the new validation error.
