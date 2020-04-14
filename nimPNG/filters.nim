import math, ../nimPNG/nimz

type
  PNGFilter* = enum
    FLT_NONE,
    FLT_SUB,
    FLT_UP,
    FLT_AVERAGE,
    FLT_PAETH

  PNGPass* = object
    w*, h*: array[0..6, int]
    filterStart*, paddedStart*, start*: array[0..7, int]

const
  # shared values used by multiple Adam7 related functions
  ADAM7_IX = [ 0, 4, 0, 2, 0, 1, 0 ] # x start values
  ADAM7_IY = [ 0, 0, 4, 0, 2, 0, 1 ] # y start values
  ADAM7_DX = [ 8, 8, 4, 4, 2, 2, 1 ] # x delta values
  ADAM7_DY = [ 8, 8, 8, 4, 4, 2, 2 ] # y delta values

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

proc filterMinsum*(output: var openArray[byte], input: openArray[byte], w, h, bpp: int) =
  let lineBytes = (w * bpp + 7) div 8
  let byteWidth = (bpp + 7) div 8

  #adaptive filtering
  var
    sum = [0, 0, 0, 0, 0]
    smallest = 0
    # five filtering attempts, one for each filter type
    attempt: array[0..4, seq[byte]]
    bestType = 0
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

      # calculate the sum of the result
      sum[fType] = 0
      if fType == 0:
        for x in 0..lineBytes-1:
          sum[fType] += int(attempt[fType][x])
      else:
        for x in 0..lineBytes-1:
          # For differences, each byte should be treated as signed, values above 127 are negative
          # (converted to signed char). Filtertype 0 isn't a difference though, so use unsigned there.
          # This means filtertype 0 is almost never chosen, but that is justified.
          let s = int(attempt[fType][x])
          if s < 128: sum[fType] += s
          else: sum[fType] += (255 - s)

      # check if this is smallest sum (or if type == 0 it's the first case so always store the values)
      if(fType == 0) or (sum[fType] < smallest):
        bestType = fType
        smallest = sum[fType]

    prevIndex = inIndex
    # now fill the out values
    # the first byte of a input will be the filter type
    output[y * (lineBytes + 1)] = byte(bestType)
    for x in 0..lineBytes-1:
      output[y * (lineBytes + 1) + 1 + x] = attempt[bestType][x]

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

proc filterBruteForce*(output: var openArray[byte], input: openArray[byte], w, h, bpp: int) =
  let lineBytes = (w * bpp + 7) div 8
  let byteWidth = (bpp + 7) div 8

  # brute force filter chooser.
  # deflate the input after every filter attempt to see which one deflates best.
  # This is very slow and gives only slightly smaller, sometimes even larger, result*/

  var
    size: array[0..4, int]
    # five filtering attempts, one for each filter type
    attempt: array[0..4, seq[byte]]
    smallest = 0
    bestType = 0
    prevIndex = 0

  # use fixed tree on the attempts so that the tree is not adapted to the filtertype on purpose,
  # to simulate the true case where the tree is the same for the whole image. Sometimes it gives
  # better result with dynamic tree anyway. Using the fixed tree sometimes gives worse, but in rare
  # cases better compression. It does make this a bit less slow, so it's worth doing this.

  for i in 0..attempt.high:
    attempt[i] = newSeq[byte](lineBytes)

  for y in 0..h-1:
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

      size[fType] = 0
      var nz = nzCompressInit(attempt[fType])
      let data = zlib_compress(nz)
      size[fType] = data.len

      #check if this is smallest size (or if type == 0 it's the first case so always store the values)
      if(fType == 0) or (size[fType] < smallest):
        bestType = fType
        smallest = size[fType]

    prevIndex = inIndex
    output[y * (lineBytes + 1)] = byte(bestType) # the first byte of a input will be the filter type
    for x in 0..lineBytes-1:
      output[y * (lineBytes + 1) + 1 + x] = attempt[bestType][x]

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

proc readBitFromReversedStream(bitptr: var int, bitstream: openArray[byte]): int =
  result = ((int(bitstream[bitptr shr 3]) shr (7 - (bitptr and 0x7))) and 1)
  inc bitptr

proc readBitsFromReversedStream(bitptr: var int, bitstream: openArray[byte], nbits: int): int =
  result = 0
  var i = nbits - 1
  while i > -1:
    result += readBitFromReversedStream(bitptr, bitstream) shl i
    dec i

proc `&=`(a: var byte, b: byte) =
  a = byte(int(a) and int(b))

proc `|=`(a: var byte, b: byte) =
  a = byte(int(a) or int(b))

proc setBitOfReversedStream0(bitptr: var int, bitstream: var openArray[byte], bit: int) =
  # the current bit in bitstream must be 0 for this to work
  if bit != 0:
    # earlier bit of huffman code is in a lesser significant bit of an earlier byte
    bitstream[bitptr shr 3] |= byte(bit shl (7 - (bitptr and 0x7)))
  inc bitptr

proc setBitOfReversedStream(bitptr: var int, bitstream: var openArray[byte], bit: int) =
  # the current bit in bitstream may be 0 or 1 for this to work
  if bit == 0: bitstream[bitptr shr 3] &= byte(not (1 shl (7 - (bitptr and 0x7))))
  else: bitstream[bitptr shr 3] |= byte(1 shl (7 - (bitptr and 0x7)))
  inc bitptr

proc removePaddingBits(output: var openArray[byte], input: openArray[byte], olinebits, ilinebits, h: int) =
  # After filtering there are still padding bits if scanLines have non multiple of 8 bit amounts. They need
  # to be removed (except at last scanLine of (Adam7-reduced) image) before working with pure image buffers
  # for the Adam7 code, the color convert code and the output to the user.
  # in and out are allowed to be the same buffer, in may also be higher but still overlapping; in must
  # have >= ilinebits*h bits, out must have >= olinebits*h bits, olinebits must be <= ilinebits
  # also used to move bits after earlier such operations happened, e.g. in a sequence of reduced images from Adam7
  # only useful if (ilinebits - olinebits) is a value in the range 1..7

  let diff = ilinebits - olinebits
  var
    ibp = 0
    obp = 0 # input and output bit pointers
  for y in 0..h-1:
    for x in 0..olinebits-1:
      var bit = readBitFromReversedStream(ibp, input)
      setBitOfReversedStream(obp, output, bit)
    inc(ibp, diff)

# Outputs various dimensions and positions in the image related to the Adam7 reduced images.
# passw: output containing the width of the 7 passes
# passh: output containing the height of the 7 passes
# filter_passstart: output containing the index of the start and end of each
# reduced image with filter bytes
# padded_passstart output containing the index of the start and end of each
# reduced image when without filter bytes but with padded scanLines
# passstart: output containing the index of the start and end of each reduced
# image without padding between scanLines, but still padding between the images
# w, h: width and height of non-interlaced image
# bpp: bits per pixel
# "padded" is only relevant if bpp is less than 8 and a scanLine or image does not
# end at a full byte
proc adam7PassValues*(pass: var PNGPass, w, h, bpp: int) =
  # the passstart values have 8 values:
  # the 8th one indicates the byte after the end of the 7th (= last) pass

  # calculate width and height in pixels of each pass
  for i in 0..6:
    pass.w[i] = (w + ADAM7_DX[i] - ADAM7_IX[i] - 1) div ADAM7_DX[i]
    pass.h[i] = (h + ADAM7_DY[i] - ADAM7_IY[i] - 1) div ADAM7_DY[i]
    if pass.w[i] == 0: pass.h[i] = 0
    if pass.h[i] == 0: pass.w[i] = 0

  pass.filterStart[0] = 0
  pass.paddedStart[0] = 0
  pass.start[0] = 0
  for i in 0..6:
    # if passw[i] is 0, it's 0 bytes, not 1 (no filtertype-byte)
    pass.filterStart[i + 1] = pass.filterStart[i]
    if (pass.w[i] != 0) and (pass.h[i] != 0):
      pass.filterStart[i + 1] += pass.h[i] * (1 + (pass.w[i] * bpp + 7) div 8)
    # bits padded if needed to fill full byte at end of each scanLine
    pass.paddedStart[i + 1] = pass.paddedStart[i] + pass.h[i] * ((pass.w[i] * bpp + 7) div 8)
    # only padded at end of reduced image
    pass.start[i + 1] = pass.start[i] + (pass.h[i] * pass.w[i] * bpp + 7) div 8

# input: Adam7 interlaced image, with no padding bits between scanLines, but between
# reduced images so that each reduced image starts at a byte.
# output: the same pixels, but re-ordered so that they're now a non-interlaced image with size w*h
# bpp: bits per pixel
# output has the following size in bits: w * h * bpp.
# input is possibly bigger due to padding bits between reduced images.
# output must be big enough AND must be 0 everywhere if bpp < 8 in the current implementation
# (because that's likely a little bit faster)
# NOTE: comments about padding bits are only relevant if bpp < 8
proc adam7Deinterlace*(output: var openArray[byte], input: openArray[byte], w, h, bpp: int) =
  var pass: PNGPass
  adam7PassValues(pass, w, h, bpp)

  if bpp >= 8:
    for i in 0..6:
      let byteWidth = bpp div 8
      for y in 0..<pass.h[i]:
        for x in 0..<pass.w[i]:
          let inStart  = pass.start[i] + (y * pass.w[i] + x) * byteWidth
          let outStart = ((ADAM7_IY[i] + y * ADAM7_DY[i]) * w + ADAM7_IX[i] + x * ADAM7_DX[i]) * byteWidth
          for b in 0..<byteWidth:
            output[outStart + b] = input[inStart + b]
  else: # bpp < 8: Adam7 with pixels < 8 bit is a bit trickier: with bit pointers
    for i in 0..6:
      let ilinebits = bpp * pass.w[i]
      let olinebits = bpp * w
      for y in 0..<pass.h[i]:
        for x in 0..<pass.w[i]:
          var ibp = (8 * pass.start[i]) + (y * ilinebits + x * bpp)
          var obp = (ADAM7_IY[i] + y * ADAM7_DY[i]) * olinebits + (ADAM7_IX[i] + x * ADAM7_DX[i]) * bpp
          for b in 0..<bpp:
            let bit = readBitFromReversedStream(ibp, input)
            # note that this function assumes the out buffer is completely 0, use setBitOfReversedStream otherwise
            setBitOfReversedStream0(obp, output, bit)

#input: non-interlaced image with size w*h
#output: the same pixels, but re-ordered according to PNG's Adam7 interlacing, with
# no padding bits between scanlines, but between reduced images so that each
# reduced image starts at a byte.
#bpp: bits per pixel
#there are no padding bits, not between scanlines, not between reduced images
#in has the following size in bits: w * h * bpp.
#output is possibly bigger due to padding bits between reduced images
#NOTE: comments about padding bits are only relevant if bpp < 8
proc adam7Interlace*(output: var openArray[byte], input: openArray[byte], w, h, bpp: int) =
  var pass: PNGPass
  adam7PassValues(pass, w, h, bpp)

  if bpp >= 8:
    for i in 0..6:
      let byteWidth = bpp div 8
      for y in 0..<pass.h[i]:
        for x in 0..<pass.w[i]:
          let inStart = ((ADAM7_IY[i] + y * ADAM7_DY[i]) * w + ADAM7_IX[i] + x * ADAM7_DX[i]) * byteWidth
          let outStart = pass.start[i] + (y * pass.w[i] + x) * byteWidth
          for b in 0..<byteWidth:
            output[outStart + b] = input[inStart + b]
  else: # bpp < 8: Adam7 with pixels < 8 bit is a bit trickier: with bit pointers
    for i in 0..6:
      let ilinebits = bpp * pass.w[i]
      let olinebits = bpp * w
      for y in 0..<pass.h[i]:
        for x in 0..<pass.w[i]:
          var ibp = (ADAM7_IY[i] + y * ADAM7_DY[i]) * olinebits + (ADAM7_IX[i] + x * ADAM7_DX[i]) * bpp
          var obp = (8 * pass.start[i]) + (y * ilinebits + x * bpp)
          for b in 0..<bpp:
            let bit = readBitFromReversedStream(ibp, input)
            setBitOfReversedStream(obp, output, bit)
