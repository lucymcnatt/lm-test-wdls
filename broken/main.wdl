version 1.0

# NOTE: despite the directory name, this is CONFIRMED WORKING on real AWS
# HealthOmics (live-tested: the align task ran and produced output). The
# original theory here was that HealthOmics resolves the entrypoint's own
# imports relative to the repository root rather than relative to this file's
# own directory (broken/) -- that theory is disproven. Kept around as the
# "one layer of nesting, one import" baseline case. See deep-nested/ for the
# untested combination (two layers, multiple imports) this case doesn't cover.
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
