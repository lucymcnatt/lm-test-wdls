version 1.0

# Imports "align.wdl" relative to THIS file's own directory (-> broken/align.wdl)
# -- the standard WDL-spec convention, and what Cromwell's workflowUrl-based
# HTTP import resolution expects. It resolves fine locally and on Cromwell.
#
# AWS HealthOmics, however, resolves the *entrypoint's own* imports relative to
# the REPOSITORY ROOT, not this file's directory -- it looks for "align.wdl" at
# the repo root, which doesn't exist there (the real file is at
# broken/align.wdl), so HealthOmics fails to build this workflow.
import "align.wdl" as align_task

workflow main {
  input {
    String name = "World"
  }

  call align_task.align {
    input: name = name
  }

  output {
    String result = align.result
  }
}
