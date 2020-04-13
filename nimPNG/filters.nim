type
  PNGFilter* = enum
    FLT_NONE,
    FLT_SUB,
    FLT_UP,
    FLT_AVERAGE,
    FLT_PAETH

# Paeth predicter, used by PNG filter type 4
proc paethPredictor(a, b, c: int): uint =
  let pa = abs(b - c)
  let pb = abs(a - c)
  let pc = abs(a + b - c - c)

  if(pc < pa) and (pc < pb): return c.uint
  elif pb < pa: return b.uint
  result = a.uint

proc filterScanline*(output: var openArray[byte], input: openArray[byte], byteWidth, len: int, filterType: PNGFilter) =
  template currPix: untyped = input[i].uint
  template prevPix: untyped = input[i - byteWidth].uint

  case filterType
  of FLT_NONE:
    for i in 0..<len:
      output[i] = input[i]
  of FLT_SUB:
    for i in 0..<byteWidth:
      output[i] = input[i]
    for i in byteWidth..<len:
      output[i] = byte((currPix - prevPix) and 0xFF)
  of FLT_UP:
    for i in 0..<len:
      output[i] = input[i]
  of FLT_AVERAGE:
    for i in 0..<byteWidth:
      output[i] = input[i]
    for i in byteWidth..<len:
      output[i] = byte((currPix - (prevPix div 2)) and 0xFF)
  of FLT_PAETH:
    for i in 0..<byteWidth:
      output[i] = input[i]
    #paethPredictor(prevPix, 0, 0) is always prevPix
    for i in byteWidth..<len:
      output[i] = byte((currPix - prevPix) and 0xFF)

proc filterScanline*(output: var openArray[byte], input, prevLine: openArray[byte], byteWidth, len: int, filterType: PNGFilter) =
  template currPix: untyped = input[i].uint
  template prevPix: untyped = input[i - byteWidth].uint
  template upPix: untyped = prevLine[i].uint
  template prevPixI: untyped = input[i - byteWidth].int
  template upPixI: untyped = prevLine[i].int
  template prevUpPix: untyped = prevLine[i - byteWidth].int

  case filterType
  of FLT_NONE:
    for i in 0..<len:
      output[i] = input[i]
  of FLT_SUB:
    for i in 0..<byteWidth:
      output[i] = input[i]
    for i in byteWidth..<len:
      output[i] = byte((currPix - prevPix) and 0xFF)
  of FLT_UP:
    for i in 0..<len:
      output[i] = byte((currPix - upPix) and 0xFF)
  of FLT_AVERAGE:
    for i in 0..<byteWidth:
      output[i] = byte((currPix - (upPix div 2)) and 0xFF)
    for i in byteWidth..<len:
      output[i] = byte((currPix - ((prevPix + upPix) div 2)) and 0xFF)
  of FLT_PAETH:
    #paethPredictor(0, upPix, 0) is always upPix
    for i in 0..<byteWidth:
      output[i] = byte((currPix - upPix) and 0xFF)
    for i in byteWidth..<len:
      output[i] = byte((currPix - paethPredictor(prevPixI, upPixI, prevUpPix)) and 0xFF)
#[
proc filterZero(output: var DataBuf, input: DataBuf, w, h, bpp: int) =
  #the width of a input in bytes, not including the filter type
  let lineBytes = (w * bpp + 7) div 8
  #byteWidth is used for filtering, is 1 when bpp < 8, number of bytes per pixel otherwise
  let byteWidth = (bpp + 7) div 8
  var prevLine: DataBuf

  for y in 0..h-1:
    let outindex = (1 + lineBytes) * y #the extra filterbyte added to each row
    let inindex = lineBytes * y
    output[outindex] = byte(int(FLT_NONE)) #filter type byte
    var outp = output.subbuffer(outindex + 1)
    let input = input.subbuffer(inindex)
    filterScanline(outp, input, prevLine, lineBytes, byteWidth, FLT_NONE)
    prevLine = input.subbuffer(inindex)

proc filterMinsum(output: var DataBuf, input: DataBuf, w, h, bpp: int) =
  let lineBytes = (w * bpp + 7) div 8
  let byteWidth = (bpp + 7) div 8

  #adaptive filtering
  var sum = [0, 0, 0, 0, 0]
  var smallest = 0

  #five filtering attempts, one for each filter type
  var attempt: array[0..4, string]
  var bestType = 0
  var prevLine: DataBuf

  for i in 0..attempt.high:
    attempt[i] = newString(lineBytes)

  for y in 0..h-1:
    #try the 5 filter types
    for fType in 0..4:
      var outp = initBuffer(attempt[fType])
      filterScanline(outp, input.subbuffer(y * lineBytes), prevLine, lineBytes, byteWidth, PNGFilter0(fType))
      #calculate the sum of the result
      sum[fType] = 0
      if fType == 0:
        for x in 0..lineBytes-1:
          sum[fType] += ord(attempt[fType][x])
      else:
        for x in 0..lineBytes-1:
          #For differences, each byte should be treated as signed, values above 127 are negative
          #(converted to signed char). Filtertype 0 isn't a difference though, so use unsigned there.
          #This means filtertype 0 is almost never chosen, but that is justified.
          let s = ord(attempt[fType][x])
          if s < 128: sum[fType] += s
          else: sum[fType] += (255 - s)

      #check if this is smallest sum (or if type == 0 it's the first case so always store the values)*/
      if(fType == 0) or (sum[fType] < smallest):
        bestType = fType
        smallest = sum[fType]

    prevLine = input.subbuffer(y * lineBytes)
    #now fill the out values
    #the first byte of a input will be the filter type
    output[y * (lineBytes + 1)] = byte(bestType)
    for x in 0..lineBytes-1:
      output[y * (lineBytes + 1) + 1 + x] = attempt[bestType][x]

proc filterEntropy(output: var DataBuf, input: DataBuf, w, h, bpp: int) =
  let lineBytes = (w * bpp + 7) div 8
  let byteWidth = (bpp + 7) div 8
  var prevLine: DataBuf

  var sum: array[0..4, float]
  var smallest = 0.0
  var bestType = 0
  var attempt: array[0..4, string]
  var count: array[0..255, int]

  for i in 0..attempt.high:
    attempt[i] = newString(lineBytes)

  for y in 0..h-1:
    #try the 5 filter types
    for fType in 0..4:
      var outp = initBuffer(attempt[fType])
      filterScanline(outp, input.subbuffer(y * lineBytes), prevLine, lineBytes, byteWidth, PNGFilter0(fType))
      for x in 0..255: count[x] = 0
      for x in 0..lineBytes-1:
        inc count[ord(attempt[fType][x])]
      inc count[fType] #the filter type itself is part of the input
      sum[fType] = 0
      for x in 0..255:
        let p = float(count[x]) / float(lineBytes + 1)
        if count[x] != 0: sum[fType] += log2(1 / p) * p

      #check if this is smallest sum (or if type == 0 it's the first case so always store the values)
      if (fType == 0) or (sum[fType] < smallest):
        bestType = fType
        smallest = sum[fType]

    prevLine = input.subbuffer(y * lineBytes)
    #now fill the out values*/
    #the first byte of a input will be the filter type
    output[y * (lineBytes + 1)] = byte(bestType)
    for x in 0..lineBytes-1:
      output[y * (lineBytes + 1) + 1 + x] = attempt[bestType][x]

proc filterPredefined(output: var DataBuf, input: DataBuf, w, h, bpp: int, state: PNGEncoder) =
  let lineBytes = (w * bpp + 7) div 8
  let byteWidth = (bpp + 7) div 8
  var prevLine: DataBuf

  for y in 0..h-1:
    let outindex = (1 + lineBytes) * y #the extra filterbyte added to each row
    let inindex = lineBytes * y
    let fType = ord(state.predefinedFilters[y])
    output[outindex] = byte(fType) #filter type byte
    var outp = output.subbuffer(outindex + 1)
    filterScanline(outp, input.subbuffer(inindex), prevLine, lineBytes, byteWidth, PNGFilter0(fType))
    prevLine = input.subbuffer(inindex)

proc filterBruteForce(output: var DataBuf, input: DataBuf, w, h, bpp: int) =
  let lineBytes = (w * bpp + 7) div 8
  let byteWidth = (bpp + 7) div 8
  var prevLine: DataBuf

  #brute force filter chooser.
  #deflate the input after every filter attempt to see which one deflates best.
  #This is very slow and gives only slightly smaller, sometimes even larger, result*/

  var size: array[0..4, int]
  var attempt: array[0..4, string] #five filtering attempts, one for each filter type
  var smallest = 0
  var bestType = 0

  #use fixed tree on the attempts so that the tree is not adapted to the filtertype on purpose,
  #to simulate the true case where the tree is the same for the whole image. Sometimes it gives
  #better result with dynamic tree anyway. Using the fixed tree sometimes gives worse, but in rare
  #cases better compression. It does make this a bit less slow, so it's worth doing this.

  for i in 0..attempt.high:
    attempt[i] = newString(lineBytes)

  for y in 0..h-1:
    #try the 5 filter types
    for fType in 0..4:
      #let testSize = attempt[fType].len
      var outp = initBuffer(attempt[fType])
      filterScanline(outp, input.subbuffer(y * lineBytes), prevLine, lineBytes, byteWidth, PNGFilter0(fType))
      size[fType] = 0

      var nz = nzDeflateInit(attempt[fType])
      let data = zlib_compress(nz)
      size[fType] = data.len

      #check if this is smallest size (or if type == 0 it's the first case so always store the values)
      if(fType == 0) or (size[fType] < smallest):
        bestType = fType
        smallest = size[fType]

    prevLine = input.subbuffer(y * lineBytes)
    output[y * (lineBytes + 1)] = byte(bestType) #the first byte of a input will be the filter type
    for x in 0..lineBytes-1:
      output[y * (lineBytes + 1) + 1 + x] = attempt[bestType][x]
]#

proc unfilterScanline*(output: var openArray[byte], input: openArray[byte], byteWidth, len: int, filterType: PNGFilter) =
  # When the pixels are smaller than 1 byte, the filter works byte per byte (byteWidth = 1)
  # the incoming inputs do NOT include the filtertype byte, that one is given in the parameter filterType instead
  # output and input MAY be the same memory address! output must be disjoint.

  template currPix: untyped = input[i].uint
  template prevPix: untyped = output[i - byteWidth].uint

  case filterType
  of FLT_NONE:
    for i in 0..<len:
      output[i] = input[i]
  of FLT_SUB:
    for i in 0..<byteWidth:
      output[i] = input[i]
    for i in byteWidth..<len:
      output[i] = byte((currPix + prevPix) and 0xFF)
  of FLT_UP:
    for i in 0..<len:
      output[i] = input[i]
  of FLT_AVERAGE:
    for i in 0..<byteWidth:
      output[i] = input[i]
    for i in byteWidth..<len:
      output[i] = byte((currPix + (prevPix div 2)) and 0xFF)
  of FLT_PAETH:
    for i in 0..<byteWidth:
      output[i] = input[i]
    for i in byteWidth..<len:
      # paethPredictor(prevPix, 0, 0) is always prevPix
      output[i] = byte((currPix + prevPix) and 0xFF)

proc unfilterScanline*(output: var openArray[byte], input, prevLine: openArray[byte], byteWidth, len: int, filterType: PNGFilter) =
  # For PNG filter method 0
  # unfilter a PNG image input by input. when the pixels are smaller than 1 byte,
  # the filter works byte per byte (byteWidth = 1)
  # prevLine is the previous unfiltered input, output the result, input the current one
  # the incoming inputs do NOT include the filtertype byte, that one is given in the parameter filterType instead
  # output and input MAY be the same memory address! prevLine must be disjoint.

  template currPix: untyped = input[i].uint
  template prevPix: untyped = output[i - byteWidth].uint
  template upPix: untyped = prevLine[i].uint
  template prevPixI: untyped = output[i - byteWidth].int
  template upPixI: untyped = prevLine[i].int
  template prevUpPix: untyped = prevLine[i - byteWidth].int

  case filterType
  of FLT_NONE:
    for i in 0..<len:
      output[i] = input[i]
  of FLT_SUB:
    for i in 0..<byteWidth:
      output[i] = input[i]
    for i in byteWidth..<len:
      output[i] = byte((currPix + prevPix) and 0xFF)
  of FLT_UP:
    for i in 0..<len:
      output[i] = byte((currPix + upPix) and 0xFF)
  of FLT_AVERAGE:
    for i in 0..<byteWidth:
      output[i] = byte((currPix + upPix div 2) and 0xFF)
    for i in byteWidth..<len:
      output[i] = byte((currPix + ((prevPix + upPix) div 2)) and 0xFF)
  of FLT_PAETH:
    for i in 0..<byteWidth:
      # paethPredictor(0, upPix, 0) is always upPix
      output[i] = byte((currPix + upPix) and 0xFF)
    for i in byteWidth..<len:
      output[i] = byte((currPix + paethPredictor(prevPixI, upPixI, prevUpPix)) and 0xFF)
