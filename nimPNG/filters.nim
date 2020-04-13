import math

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
    # paethPredictor(prevPix, 0, 0) is always prevPix
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
    # paethPredictor(0, upPix, 0) is always upPix
    for i in 0..<byteWidth:
      output[i] = byte((currPix - upPix) and 0xFF)
    for i in byteWidth..<len:
      output[i] = byte((currPix - paethPredictor(prevPixI, upPixI, prevUpPix)) and 0xFF)

proc filterZero*(output: var openArray[byte], input: openArray[byte], w, h, bpp: int) =
  # the width of a input in bytes, not including the filter type
  let lineBytes = (w * bpp + 7) div 8
  # byteWidth is used for filtering, is 1 when bpp < 8, number of bytes per pixel otherwise
  let byteWidth = (bpp + 7) div 8

  # line 0
  if h > 0:
    output[0] = byte(FLT_NONE) # filterType byte
    filterScanline(output.toOpenArray(1, output.len-1), # skip filterType
      input, byteWidth, lineBytes, FLT_NONE)

  # next line start from 1
  var prevIndex = 0
  for y in 1..<h:
    let outIndex = (1 + lineBytes) * y # the extra filterType added to each row
    let inIndex = lineBytes * y
    output[outIndex] = byte(FLT_NONE) # filterType byte
    filterScanline(output.toOpenArray(outIndex + 1, output.len-1), # skip filterType
      input.toOpenArray(inIndex, input.len-1),
      input.toOpenArray(prevIndex, input.len-1),
      byteWidth, lineBytes, FLT_NONE)
    prevIndex = inIndex
    
#[
proc filterMinsum*(output: var openArray[byte], input: openArray[byte], w, h, bpp: int) =
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
]#

proc filterEntropy*(output: var openArray[byte], input: openArray[byte], w, h, bpp: int) =
  let lineBytes = (w * bpp + 7) div 8
  let byteWidth = (bpp + 7) div 8

  var
    sum: array[0..4, float]
    smallest = 0.0
    bestType = 0
    attempt: array[0..4, seq[byte]]
    count: array[0..255, int]
    prevIndex = 0

  for i in 0..attempt.high:
    attempt[i] = newSeq[byte](lineBytes)

  for y in 0..<h:
    # try the 5 filter types
    let inIndex = y * lineBytes
    for fType in 0..4:
      if y == 0:
        filterScanline(attempt[fType],
          input.toOpenArray(inIndex, input.len-1),
          byteWidth, lineBytes, PNGFilter(fType))
      else:
        filterScanline(attempt[fType],
          input.toOpenArray(inIndex, input.len-1),
          input.toOpenArray(prevIndex, input.len-1),
          byteWidth, lineBytes, PNGFilter(fType))

      for x in 0..255: count[x] = 0
      for x in 0..lineBytes-1:
        inc count[int(attempt[fType][x])]

      inc count[fType] # the filterType itself is part of the input
      sum[fType] = 0
      for x in 0..255:
        let p = float(count[x]) / float(lineBytes + 1)
        if count[x] != 0: sum[fType] += log2(1 / p) * p

      # check if this is smallest sum (or if type == 0 it's the first case so always store the values)
      if (fType == 0) or (sum[fType] < smallest):
        bestType = fType
        smallest = sum[fType]

    prevIndex = inIndex
    # now fill the out values
    # the first byte of a input will be the filter type
    output[y * (lineBytes + 1)] = byte(bestType)
    for x in 0..<lineBytes:
      output[y * (lineBytes + 1) + 1 + x] = attempt[bestType][x]

proc filterPredefined*(output: var openArray[byte], input: openArray[byte],
  w, h, bpp: int, predefinedFilters: openArray[PNGFilter]) =

  let lineBytes = (w * bpp + 7) div 8
  let byteWidth = (bpp + 7) div 8

  # line 0
  if h > 0:
    output[0] = byte(predefinedFilters[0]) # filterType byte
    filterScanline(output.toOpenArray(1, output.len-1), # skip filterType
      input, byteWidth, lineBytes, predefinedFilters[0])

  # next line start from 1
  var prevIndex = 0
  for y in 1..<h:
    let outIndex = (1 + lineBytes) * y # the extra filterType added to each row
    let inIndex = lineBytes * y
    let fType = ord(predefinedFilters[y])
    output[outIndex] = byte(fType) # filterType byte
    filterScanline(output.toOpenArray(outIndex + 1, output.len-1), # skip filterType
      input.toOpenArray(inIndex, input.len-1),
      input.toOpenArray(prevIndex, input.len-1),
      byteWidth, lineBytes, PNGFilter(fType))
    prevIndex = inIndex

#[
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

proc unfilter*(output: var openArray[byte], input: openArray[byte], w, h, bpp: int) =
  # For PNG filter method 0
  # this function unfilters a single image (e.g. without interlacing this is called once, with Adam7 seven times)
  # output must have enough bytes allocated already, input must have the scanLines + 1 filtertype byte per scanLine
  # w and h are image dimensions or dimensions of reduced image, bpp is bits per pixel
  # input and output are allowed to be the same memory address (but aren't the same size since in has the extra filter bytes)

  # byteWidth is used for filtering, is 1 when bpp < 8, number of bytes per pixel otherwise
  let byteWidth = (bpp + 7) div 8
  let lineBytes = (w * bpp + 7) div 8

  # line 0, without prevLine
  if h > 0:
    unfilterScanLine(output,
      input.toOpenArray(1, input.len-1), # skip the filterType
      byteWidth, lineBytes,
      PNGFilter(input[0]))

  # next line start from 1
  var prevIndex = 0
  for y in 1..<h:
    let outIndex = lineBytes * y
    let inIndex = (1 + lineBytes) * y # the extra filterbyte added to each row
    let filterType = PNGFilter(input[inIndex])
    unfilterScanLine(output.toOpenArray(outIndex, output.len-1),
      input.toOpenArray(inIndex + 1, input.len-1), # skip the filterType
      output.toOpenArray(prevIndex, output.len-1), # prevLine
      byteWidth, lineBytes, filterType)
    prevIndex = outIndex
