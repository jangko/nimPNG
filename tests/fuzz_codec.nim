import testutils/fuzzing, ../nimPNG

proc toString(x: openArray[byte]): string =
  result = newString(x.len)
  if x.len != 0:
    copyMem(result[0].addr, x[0].unsafeAddr, x.len)

test:
  let png = decodePNG32(toString(payload))
