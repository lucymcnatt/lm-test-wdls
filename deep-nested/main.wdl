version 1.0

# Entrypoint with TWO imports (breadth) where one of them (align.wdl) has its
# own import (depth) -- the untested combination from the original bug report:
# "subworkflow imports something" plus "multiple imports".
#
#   main.wdl
#   |-- align.wdl   (a subworkflow, called via `call align_wf.align`)
#   |     `-- trim.wdl   (align's own import; main never references this)
#   `-- qc.wdl      (a plain task, called via `call qc_task.qc`)
#
# All imports are written relative to their own importing file (the
# already-confirmed-working convention), at two different depths and with
# two imports at the top level, to check whether that still holds once the
# import graph gets more complicated than a single main -> subworkflow edge.
import "align.wdl" as align_wf
import "qc.wdl" as qc_task

workflow main {
  input {
    String name = "World"
  }

  call align_wf.align {
    input: name = name
  }

  call qc_task.qc {
    input: name = name
  }

  output {
    String align_result = align.result
    String qc_result = qc.result
  }
}
