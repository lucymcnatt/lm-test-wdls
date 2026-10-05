version 1.0

import "greet.wdl" as greet_task

# This entrypoint lives at the repository root, so its import ("greet.wdl") is
# relative to both the importing file's own directory AND the repo root -- the
# two happen to coincide here. That's why this variant works on Cromwell, works
# on real AWS HealthOmics, and parses locally in pipeline-service's describe
# step. Compare with broken/main.wdl, which breaks this coincidence.
workflow main {
  input {
    String name = "World"
  }

  call greet_task.greet {
    input: name = name
  }

  output {
    String greeting = greet.greeting
  }
}
