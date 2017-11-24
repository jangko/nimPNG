# Package
version       = "0.2.0"
author        = "Andri Lim"
description   = "PNG encoder and decoder"
license       = "MIT"

# Deps
requires "nim >= 0.11.2"

task tests, "Run tests":
    withDir("tester"):
        exec "nim c -r test.nim"
        exec "nim c -r testCodec.nim"
        exec "nim c -r testSuite.nim"
