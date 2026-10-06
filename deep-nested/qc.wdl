version 1.0

# Second direct import of main.wdl, alongside align.wdl -- tests that *multiple*
# sibling imports at the entrypoint level all resolve, not just one.
task qc {
  input {
    String name
  }

  command <<<
    echo "Running QC for ~{name}..."
  >>>

  output {
    String result = read_string(stdout())
  }

  runtime {
    docker: "ubuntu:22.04"
  }
}
