import ../nimPNG/filters, ./randutils, unittest

template roundTripFilter(byteWidth: int, filter: PNGFilter) =
  filterScanline(outPix, inPix, byteWidth, lineBytes, filter)
  unfilterScanline(oriPix, outPix, byteWidth, lineBytes, filter)
  check oriPix == inPix

template roundTripFilterP(byteWidth: int, filter: PNGFilter) =
  # with prevLine
  filterScanline(outPix, inPix, prevLine, byteWidth, lineBytes, filter)
  unfilterScanline(oriPix, outPix, prevLine, byteWidth, lineBytes, filter)
  check oriPix == inPix

proc testFilterScanline() =
  suite "filterScanline":
    const
      lineBytes = 128

    let
      inPix = randList(byte, rng(0, 255), lineBytes, unique = false)
      prevLine = randList(byte, rng(0, 255), lineBytes, unique = false)

    var
      outPix = newSeq[byte](lineBytes)
      oriPix = newSeq[byte](lineBytes)

    test "FLT_NONE":
      roundTripFilter(1, FLT_NONE)
      roundTripFilter(2, FLT_NONE)
      roundTripFilter(3, FLT_NONE)
      roundTripFilter(4, FLT_NONE)

    test "FLT_SUB":
      roundTripFilter(1, FLT_SUB)
      roundTripFilter(2, FLT_SUB)
      roundTripFilter(3, FLT_SUB)
      roundTripFilter(4, FLT_SUB)

    test "FLT_UP":
      roundTripFilter(1, FLT_UP)
      roundTripFilter(2, FLT_UP)
      roundTripFilter(3, FLT_UP)
      roundTripFilter(4, FLT_UP)

    test "FLT_AVERAGE":
      roundTripFilter(1, FLT_AVERAGE)
      roundTripFilter(2, FLT_AVERAGE)
      roundTripFilter(3, FLT_AVERAGE)
      roundTripFilter(4, FLT_AVERAGE)

    test "FLT_PAETH":
      roundTripFilter(1, FLT_PAETH)
      roundTripFilter(2, FLT_PAETH)
      roundTripFilter(3, FLT_PAETH)
      roundTripFilter(4, FLT_PAETH)

    test "FLT_NONE with prevLine":
      roundTripFilterP(1, FLT_NONE)
      roundTripFilterP(2, FLT_NONE)
      roundTripFilterP(3, FLT_NONE)
      roundTripFilterP(4, FLT_NONE)

    test "FLT_SUB with prevLine":
      roundTripFilterP(1, FLT_SUB)
      roundTripFilterP(2, FLT_SUB)
      roundTripFilterP(3, FLT_SUB)
      roundTripFilterP(4, FLT_SUB)

    test "FLT_UP with prevLine":
      roundTripFilterP(1, FLT_UP)
      roundTripFilterP(2, FLT_UP)
      roundTripFilterP(3, FLT_UP)
      roundTripFilterP(4, FLT_UP)

    test "FLT_AVERAGE with prevLine":
      roundTripFilterP(1, FLT_AVERAGE)
      roundTripFilterP(2, FLT_AVERAGE)
      roundTripFilterP(3, FLT_AVERAGE)
      roundTripFilterP(4, FLT_AVERAGE)

    test "FLT_PAETH with prevLine":
      roundTripFilterP(1, FLT_PAETH)
      roundTripFilterP(2, FLT_PAETH)
      roundTripFilterP(3, FLT_PAETH)
      roundTripFilterP(4, FLT_PAETH)

proc checkPixels(a, b: openArray[byte], len: int): bool =
  result = true
  for x in 0..<len:
    if a[x] != b[x]:
      return false

template roundTripStrategy(bpp: int, strategy: untyped) =
  block:
    let
      lineBytes = (w * bpp + 7) div 8
      numBytes = h * lineBytes

    strategy(outPix, inPix, w, h, bpp)
    unfilter(oriPix, outPix, w, h, bpp)
    check checkPixels(inPix, oriPix, numBytes)

template roundTripZero(bpp: int) =
  roundTripStrategy(bpp, filterZero)

template roundTripEntropy(bpp: int) =
  roundTripStrategy(bpp, filterEntropy)

template roundTripPredefined(bpp: int) =
  block:
    let
      lineBytes = (w * bpp + 7) div 8
      numBytes = h * lineBytes

    filterPredefined(outPix, inPix, w, h, bpp, predefinedFilters)
    unfilter(oriPix, outPix, w, h, bpp)
    check checkPixels(inPix, oriPix, numBytes)

proc testFilterStrategies() =
  suite "Filter Strategies":
    let
      h = 128
      w = 128
      bpp = 32 # we use largest bpp to avoid reallocation
      lineBytes = (w * bpp + 7) div 8
      numBytes = h * lineBytes
      inPix = randList(byte, rng(0, 255), numBytes, unique = false)
      outBytes = h * (lineBytes + 1) # lineBytes + filterType
      byteFilter = randList(byte, rng(0, 4), h, unique = false)

    var
      outPix = newSeq[byte](outBytes)
      oriPix = newSeq[byte](numBytes)

    test "LFS_ZERO":
      roundTripZero(8)
      roundTripZero(16)
      roundTripZero(24)
      roundTripZero(32)

    test "LFS_PREDEFINED":
      var predefinedFilters = newSeq[PNG_FILTER](h)
      for i in 0..<h: predefinedFilters[i] = byteFilter[i].PNGFilter
      roundTripPredefined(8)
      roundTripPredefined(16)
      roundTripPredefined(24)
      roundTripPredefined(32)

    test "LFS_ENTROPY":
      roundTripEntropy(8)
      roundTripEntropy(16)
      roundTripEntropy(24)
      roundTripEntropy(32)

    #of LFS_MINSUM: filterMinsum(output, input, w, h, bpp)
    #of LFS_BRUTE_FORCE: filterBruteForce(output, input, w, h, bpp)

proc main() =
  testFilterScanline()
  testFilterStrategies()

main()
