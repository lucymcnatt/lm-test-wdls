version 1.0

# Mirrors the real import shape used by theiagen/public_health_bioinformatics
# (the repo named in the original bug report): workflows live under
# workflows/<category>/wf_*.wdl and tasks live under tasks/<category>/task_*.wdl,
# so a workflow imports a task by going UP out of its own directory tree and
# back DOWN into a sibling tree, e.g. "../../tasks/qc/task_qc.wdl" --
# NOT a sibling file in the same directory, which is all broken/ and
# deep-nested/ tested (and which worked live on HealthOmics). This is the one
# import shape from the real-world repo that hasn't been tried yet.
import "../../tasks/qc/task_qc.wdl" as qc_task

workflow main {
  input {
    String name = "World"
  }

  call qc_task.qc {
    input: name = name
  }

  output {
    String result = qc.result
  }
}
