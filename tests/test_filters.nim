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

    #of LFS_ZERO: filterZero(output, input, w, h, bpp)
    #of LFS_MINSUM: filterMinsum(output, input, w, h, bpp)
    #of LFS_ENTROPY: filterEntropy(output, input, w, h, bpp)
    #of LFS_BRUTE_FORCE: filterBruteForce(output, input, w, h, bpp)
    #of LFS_PREDEFINED: filterPredefined(output, input, w, h, bpp, state)

proc main() =
  testFilterScanline()

main()

