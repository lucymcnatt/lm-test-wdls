version 1.0

task align {
  input {
    String name
  }

  command <<<
    echo "Aligning for ~{name}..."
  >>>

  output {
    String result = read_string(stdout())
  }

  runtime {
    docker: "ubuntu:22.04"
  }
}
