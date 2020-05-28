import ../nimPNG, unittest, os

suite "parse invalid input":
  for x in walkDirRec("tests" / "invalidInput"):
    let y = splitPath(x)
    test y.tail:
      discard loadPNG32(x)
      check true
