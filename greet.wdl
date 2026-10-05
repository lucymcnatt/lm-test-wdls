version 1.0

task greet {
  input {
    String name
  }

  command <<<
    echo "Hello, ~{name}!"
  >>>

  output {
    String greeting = read_string(stdout())
  }

  runtime {
    docker: "ubuntu:22.04"
  }
}
