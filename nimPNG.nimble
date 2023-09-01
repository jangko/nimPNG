# Package
version       = "0.3.6"
author        = "Andri Lim"
description   = "PNG encoder and decoder"
license       = "MIT"
skipDirs      = @["tests", "docs"]

# Deps
requires "nim >= 1.6.0"

### Helper functions
proc test(env, path: string) =
  # Compilation language is controlled by TEST_LANG
  var lang = "c"
  if existsEnv"TEST_LANG":
    lang = getEnv"TEST_LANG"

  if not dirExists "build":
    mkDir "build"
  exec "nim " & lang & " " & env &
    " --outdir:build -r --hints:off --warnings:off " & path

task test, "Run tests":
  exec "nim -v"
  test "-d:release", "tests/all_tests"
  test "--gc:arc -d:release", "tests/all_tests"

task testvcc, "Run tests with vcc compiler":
  test "--cc:vcc -d:release", "tests/all_tests"
