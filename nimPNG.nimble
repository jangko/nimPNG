# Package
version       = "0.2.6"
author        = "Andri Lim"
description   = "PNG encoder and decoder"
license       = "MIT"
skipDirs      = @["tests", "docs"]

# Deps
requires "nim >= 0.19.0"

task tests, "Run tests":
  exec "nim c -r tests/test_apng.nim"
  exec "nim c -r tests/test_codec.nim"
  exec "nim c -r tests/test_suite.nim"
  exec "nim c -r tests/test_nimz.nim"
  exec "nim c -r tests/test_filters.nim"

  exec "nim c -r -d:release tests/test_apng.nim"
  exec "nim c -r -d:release tests/test_codec.nim"
  exec "nim c -r -d:release tests/test_suite.nim"
  exec "nim c -r -d:release tests/test_nimz.nim"
  exec "nim c -r -d:release tests/test_filters.nim"

  exec "nim c -r --gc:arc -d:release tests/test_nimz.nim"
  exec "nim c -r --gc:arc -d:release tests/test_filters.nim"
