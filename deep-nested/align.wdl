version 1.0

# This is itself a *subworkflow* (not just a task), and it imports a third
# file relative to its own directory -- "deep-nested/trim.wdl". That's the
# second layer: main.wdl never mentions trim.wdl at all; it only exists
# because align.wdl, which main.wdl imports, imports it in turn.
import "trim.wdl" as trim_task

workflow align {
  input {
    String name
  }

  call trim_task.trim {
    input: name = name
  }

  call align_task {
    input: name = name, trimmed = trim.result
  }

  output {
    String result = align_task.result
  }
}

task align_task {
  input {
    String name
    String trimmed
  }

  command <<<
    echo "Aligning ~{name} using: ~{trimmed}"
  >>>

  output {
    String result = read_string(stdout())
  }

  runtime {
    docker: "ubuntu:22.04"
  }
}
