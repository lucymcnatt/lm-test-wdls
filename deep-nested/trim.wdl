version 1.0

# Leaf task -- imported only by align.wdl, never directly by main.wdl. This is
# the "second layer": main imports align, and align (not main) imports this.
task trim {
  input {
    String name
  }

  command <<<
    echo "Trimming reads for ~{name}..."
  >>>

  output {
    String result = read_string(stdout())
  }

  runtime {
    docker: "ubuntu:22.04"
  }
}
