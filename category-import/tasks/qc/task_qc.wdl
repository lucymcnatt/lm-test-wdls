version 1.0

# Lives under tasks/qc/, two directories away from the entrypoint at
# workflows/genomic_characterization/main.wdl, which reaches this file via
# "../../tasks/qc/task_qc.wdl" -- the real-world theiagen-style import shape.
task qc {
  input {
    String name
  }

  command <<<
    echo "Running QC for ~{name} (imported via ../../tasks/qc/ from workflows/genomic_characterization/)..."
  >>>

  output {
    String result = read_string(stdout())
  }

  runtime {
    docker: "ubuntu:22.04"
  }
}
