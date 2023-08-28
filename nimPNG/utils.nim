proc newStringWithDefault*(x: int): string =
  # newString will create uninitialized string
  result = newString(0)
  setLen(result, x)
