# Package
version       = "0.3.1"
author        = "Andri Lim"
description   = "PNG encoder and decoder"
license       = "MIT"
skipDirs      = @["tests", "docs"]

# Deps
requires "nim >= 0.19.0"

task tests, "Run tests":
  exec "nim -v"
  exec "nim c -r -d:release tests/all_tests"
  exec "nim c -r --gc:arc -d:release tests/all_tests"
