# Package
version       = "0.2.5"
author        = "Andri Lim"
description   = "PNG encoder and decoder"
license       = "MIT"
skipDirs      = @["apng", "suite", "tester", "docs"]

# Deps
requires "nim >= 0.19.0"

task tests, "Run tests":
  withDir("tester"):
    exec "nim c -r test.nim"
    exec "nim c -r testCodec.nim"
    exec "nim c -r testSuite.nim"
    
    exec "nim c -r -d:release test.nim"
    exec "nim c -r -d:release testCodec.nim"
    exec "nim c -r -d:release testSuite.nim"
