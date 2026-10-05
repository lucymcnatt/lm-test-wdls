version 1.0

# "nonexistent.wdl" does not exist anywhere in this repo -- a genuine typo'd or
# missing import, as opposed to broken/main.wdl's root-vs-file resolution
# mismatch. This exercises the *other* half of the fix: before it,
# WDLProjectLoader.get_document() caught WDL.Error.ImportError in the same
# branch as lenient semantic validation warnings and silently returned None,
# so /v2/description returned 200 with an EMPTY input template -- indistinguishable
# from "this workflow genuinely has no inputs". After the fix, ImportError is
# raised as a ValidationException naming the missing import.
import "nonexistent.wdl" as missing_task

workflow main {
  input {
    String name = "World"
  }

  call missing_task.anything {
    input: name = name
  }

  output {
    String result = anything.result
  }
}
