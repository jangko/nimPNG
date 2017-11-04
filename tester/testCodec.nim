import nimPNG, streams, math, strutils, tables, base64, os
import private.buffer

type
  Image = ref object
    data: string
    width, height: int
    colorType: PNGcolorType
    bitDepth: int

proc fromBase64(input: string): string =
  result = base64.decode(input)

proc assertEquals[T, U](expected: T, actual: U, message = "") =
  if expected != actual:
    echo "Error: Not equal! Expected ", expected, " got ", actual, ". ",
      "Message: ", message
    quit()

proc getNumColorChannels(colorType: PNGcolorType): int =
  case colorType
  of LCT_GREY: result = 1
  of LCT_RGB: result = 3
  of LCT_PALETTE: result = 1
  of LCT_GREY_ALPHA: result = 2
  of LCT_RGBA: result = 4
  else: result = 0

proc generateTestImage(width, height: int, colorType = LCT_RGBA, bitDepth = 8): Image =
  new(result)
  result.width = width
  result.height = height
  result.colorType = colorType
  result.bitDepth = bitDepth

  let bits = bitDepth * getNumColorChannels(colorType)
  let size = (width * height * bits + 7) div 8
  result.data = newString(size)

  var value = 128
  for i in 0..<size:
    result.data[i] = chr(value mod 255)
    value.inc

proc assertPixels(image: Image, decoded: string, message: string) =
  for i in 0..image.data.high:
    var byte_expected = ord(image.data[i])
    var byte_actual = ord(decoded[i])

    #last byte is special due to possible random padding bits which need not to be equal
    if i == image.data.high:
      let numbits = getNumColorChannels(image.colorType) * image.bitDepth * image.width * image.height
      let padding = 8 - (numbits - 8 * (numbits div 8))
      if padding != 8:
        #set all padding bits of both to 0
        for j in 0..<padding:
          byte_expected = (byte_expected and (not (1 shl j))) mod 256
          byte_actual = (byte_actual and (not (1 shl j))) mod 256

    assertEquals(byte_expected, byte_actual, message & " " & $i)

proc doCodecTest(image: Image, state: PNGEncoder) =
  var png = encodePNG(image.data, image.colorType, image.bitDepth, image.width, image.height, state)
  var s = newStringStream()
  png.writeChunks s

  #if the image is large enough, compressing it should result in smaller size
  #if image.data.len > 512:
    #assertTrue(s.data.len < image.data.len, "compressed size")

  s.setPosition 0
  var decoded = s.decodePNG(image.colorType, image.bitDepth)

  assertEquals(image.width, decoded.width)
  assertEquals(image.height, decoded.height)

  if state == nil:
    assertPixels(image, decoded.data, "Pixels")
  else:
    assertPixels(image, decoded.data, "Pixels Interlaced")

#Test PNG encoding and decoding the encoded result
proc doCodecTest(image: Image) =
  doCodecTest(image, nil)

  var state = makePNGEncoder()
  state.interlaceMethod = IM_INTERLACED
  doCodecTest(image, state)

#Test PNG encoding and decoding using some image generated with the given parameters
proc codecTest(width, height: int, colorType = LCT_RGBA, bitDepth = 8) =
  echo "codec test ", width, " ", height
  var image = generateTestImage(width, height, colorType, bitDepth)
  image.doCodecTest()

proc testOtherPattern1() =
  echo "codec other pattern 1"

  var image: Image
  new(image)

  let w = 192
  let h = 192
  image.width = w
  image.height = h
  image.colorType = LCT_RGBA
  image.bitDepth = 8
  image.data = newString(w * h * 4)

  for y in 0..h-1:
    for x in 0..w-1:
      image.data[4 * w * y + 4 * x + 0] = chr(int(127 * (1 + math.sin(float(                    x * x +                     y * y) / (float(w * h) / 8.0)))))
      image.data[4 * w * y + 4 * x + 1] = chr(int(127 * (1 + math.sin(float((w - x - 1) * (w - x - 1) +                     y * y) / (float(w * h) / 8.0)))))
      image.data[4 * w * y + 4 * x + 2] = chr(int(127 * (1 + math.sin(float(                    x * x + (h - y - 1) * (h - y - 1)) / (float(w * h) / 8.0)))))
      image.data[4 * w * y + 4 * x + 3] = chr(int(127 * (1 + math.sin(float((w - x - 1) * (w - x - 1) + (h - y - 1) * (h - y - 1)) / (float(w * h) / 8.0)))))

  doCodecTest(image)

proc testOtherPattern2() =
  echo "codec other pattern 2"

  var image: Image
  new(image)

  let w = 192
  let h = 192
  image.width = w
  image.height = h
  image.colorType = LCT_RGBA
  image.bitDepth = 8
  image.data = newString(w * h * 4)

  for y in 0..h-1:
    for x in 0..w-1:
      image.data[4 * w * y + 4 * x + 0] = chr(255 * not (x and y) and 0xFF)
      image.data[4 * w * y + 4 * x + 1] = chr((x xor y) and 0xFF)
      image.data[4 * w * y + 4 * x + 2] = chr((x or y) and 0xFF)
      image.data[4 * w * y + 4 * x + 3] = chr(255)

  doCodecTest(image)

proc testSinglePixel(r, g, b, a: int) =
  echo "codec single pixel " , r , " " , g , " " , b , " " , a
  var pixel: Image
  new(pixel)

  pixel.width = 1
  pixel.height = 1
  pixel.colorType = LCT_RGBA
  pixel.bitDepth = 8
  pixel.data = newString(4)
  pixel.data[0] = r.chr
  pixel.data[1] = g.chr
  pixel.data[2] = b.chr
  pixel.data[3] = a.chr

  doCodecTest(pixel)

proc testColor(r, g, b, a: int) =
  echo "codec test color ", r , " " , g , " " , b , " " , a
  var image: Image
  new(image)

  let w = 20
  let h = 20
  image.width = w
  image.height = h
  image.colorType = LCT_RGBA
  image.bitDepth = 8
  image.data = newString(w * h * 4)

  for y in 0..h-1:
    for x in 0..w-1:
      image.data[20 * 4 * y + 4 * x + 0] = r.chr
      image.data[20 * 4 * y + 4 * x + 0] = g.chr
      image.data[20 * 4 * y + 4 * x + 0] = b.chr
      image.data[20 * 4 * y + 4 * x + 0] = a.chr

  doCodecTest(image)

  image.data[3] = 0.chr #one fully transparent pixel
  doCodecTest(image)

  image.data[3] = 128.chr #one semi transparent pixel
  doCodecTest(image)

  var image3: Image
  new(image3)
  image3.width = image.width
  image3.height = image.height
  image3.colorType = image.colorType
  image3.bitDepth = image.bitDepth
  image3.data = image.data

  #add 255 different colors
  for i in 0..254:
    image.data[i * 4 + 0] = i.chr
    image.data[i * 4 + 1] = i.chr
    image.data[i * 4 + 2] = i.chr
    image.data[i * 4 + 3] = 255.chr

  doCodecTest(image3)

  #a 256th color
  image3.data[255 * 4 + 0] = 255.chr
  image3.data[255 * 4 + 1] = 255.chr
  image3.data[255 * 4 + 2] = 255.chr
  image3.data[255 * 4 + 3] = 255.chr

  doCodecTest(image3)

  testSinglePixel(r, g, b, a)

proc testSize(w, h: int) =
  echo "codec test size ", w, " ", h
  var image: Image
  new(image)

  image.width = w
  image.height = h
  image.colorType = LCT_RGBA
  image.bitDepth = 8
  image.data = newString(w * h * 4)

  for y in 0..h-1:
    for x in 0..w-1:
      image.data[w * 4 * y + 4 * x + 0] = (x mod 256).chr
      image.data[w * 4 * y + 4 * x + 0] = (y mod 256).chr
      image.data[w * 4 * y + 4 * x + 0] = 255.chr
      image.data[w * 4 * y + 4 * x + 0] = 255.chr

  doCodecTest(image)

proc testPNGCodec() =
  codecTest(1, 1)
  codecTest(2, 2)
  codecTest(1, 1, LCT_GREY, 1)
  codecTest(7, 7, LCT_GREY, 1)
  codecTest(127, 127)
  codecTest(127, 127, LCT_GREY, 1)
  testOtherPattern1()
  testOtherPattern2()

  testColor(255, 255, 255, 255)
  testColor(0, 0, 0, 255)
  testColor(1, 2, 3, 255)
  testColor(255, 0, 0, 255)
  testColor(0, 255, 0, 255)
  testColor(0, 0, 255, 255)
  testColor(0, 0, 0, 255)
  testColor(1, 1, 1, 255)
  testColor(1, 1, 1, 1)
  testColor(0, 0, 0, 128)
  testColor(255, 0, 0, 128)
  testColor(127, 127, 127, 255)
  testColor(128, 128, 128, 255)
  testColor(127, 127, 127, 128)
  testColor(128, 128, 128, 128)
  #transparent single pixels
  testColor(0, 0, 0, 0)
  testColor(255, 0, 0, 0)
  testColor(1, 2, 3, 0)
  testColor(255, 255, 255, 0)
  testColor(254, 254, 254, 0)

  #This is mainly to test the Adam7 interlacing
  for h in 1..11:
    for w in 1..12:
      testSize(w, h)

proc doPngSuiteTinyTest(b64: string, w, h, r, g, b, a: int) =
  var input = fromBase64(b64)
  var s = newStringStream(input)
  var decoded = s.decodePNG(LCT_RGBA, 8)

  assertEquals(w, decoded.width)
  assertEquals(h, decoded.height)
  assertEquals(r, decoded.data[0].int)
  assertEquals(g, decoded.data[1].int)
  assertEquals(b, decoded.data[2].int)
  assertEquals(a, decoded.data[3].int)

  var state = makePNGEncoder()
  state.autoConvert = false
  var png = encodePNG(decoded.data, LCT_RGBA, 8, w, h, state)
  s = newStringStream()
  png.writeChunks s
  s.setPosition 0

  var decoded2 = s.decodePNG(LCT_RGBA, 8)
  for i in 0..decoded.data.high:
    assertEquals(decoded.data[i], decoded2.data[i])

#checks that both png suite images have the exact same pixel content, e.g. to check that
#it decodes an interlaced and non-interlaced corresponding png suite image equally
proc doPngSuiteEqualTest(b64a, b64b: string) =
  var input1 = fromBase64(b64a)
  var s1 = newStringStream(input1)
  var decoded1 = s1.decodePNG(LCT_RGBA, 8)

  var input2 = fromBase64(b64b)
  var s2 = newStringStream(input2)
  var decoded2 = s2.decodePNG(LCT_RGBA, 8)

  assertEquals(decoded1.height, decoded2.height)
  assertEquals(decoded1.width, decoded2.width)

  let size = decoded1.height * decoded1.width * 4
  for i in 0..<size:
    if decoded1.data[i] != decoded2.data[i]:
      echo "x: ", ((i div 4) mod decoded1.width), " y: ", ((i div 4) mod decoded1.width), " c: ", i mod 4
      assertEquals(decoded1.data[i], decoded2.data[i])

proc testPngSuiteTiny() =
  echo "testPngSuiteTiny"

  doPngSuiteTinyTest("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAFS3GZcAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
                     "BAQEd/i1owAAAANQTFRFAAD/injSVwAAAApJREFUeJxjYAAAAAIAAUivpHEAAAAASUVORK5CYII=",
                     1, 1, 0, 0, 255, 255) #s01n3p01.png
  doPngSuiteTinyTest("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
                     "BAQEd/i1owAAAANQTFRFAAD/injSVwAAAApJREFUeJxjYAAAAAIAAUivpHEAAAAASUVORK5CYII=",
                     1, 1, 0, 0, 255, 255) #s01i3p01.png
  doPngSuiteTinyTest("iVBORw0KGgoAAAANSUhEUgAAAAcAAAAHAgMAAAC5PL9AAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
                     "BAQEd/i1owAAAAxQTFRF/wB3AP93//8AAAD/G0OznAAAABpJREFUeJxj+P+H4WoMw605DDfmgEgg" &
                     "+/8fAHF5CrkeXW0HAAAAAElFTkSuQmCC",
                     7, 7, 0, 0, 255, 255) #s07n3p02.png
  doPngSuiteTinyTest("iVBORw0KGgoAAAANSUhEUgAAAAcAAAAHAgMAAAHOO4/WAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
                     "BAQEd/i1owAAAAxQTFRF/wB3AP93//8AAAD/G0OznAAAACVJREFUeJxjOMBwgOEBwweGDQyvGf4z" &
                     "/GFIAcI/DFdjGG7MAZIAweMMgVWC+YkAAAAASUVORK5CYII=",
                     7, 7, 0, 0, 255, 255) #s07i3p02.png
  doPngSuiteTinyTest("iVBORw0KGgoAAAANSUhEUgAAACAAAAAgAgMAAAAOFJJnAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
                     "AQEBfC53ggAAAAxQTFRFAP8A/wAA//8AAAD/ZT8rugAAACJJREFUeJxj+B+6igGEGfAw8MnBGKug" &
                     "LHwMqNL/+BiDzD0AvUl/geqJjhsAAAAASUVORK5CYII=",
                     32, 32, 0, 0, 255, 255) #basn3p02.png
  doPngSuiteTinyTest("iVBORw0KGgoAAAANSUhEUgAAACAAAAAgAQMAAABJtOi3AAAABGdBTUEAAYagMeiWXwAAAAZQTFRF" &
                     "7v8iImb/bBrSJgAAABVJREFUeJxj4AcCBjTiAxCgEwOkDgC7Hz/Bk4JmWQAAAABJRU5ErkJggg==",
                     32, 32, 238, 255, 34, 255) #basn3p01.png
  doPngSuiteTinyTest("iVBORw0KGgoAAAANSUhEUgAAACAAAAAgEAAAAAAGgflrAAAABGdBTUEAAYagMeiWXwAAAF5JREFU" &
                     "eJzV0jEKwDAMQ1E5W+9/xtygk8AoezLVKgSj2Y8/OICnuFcTE2OgOoJgHQiZAN2C9kDKBOgW3AZC" &
                     "JkC3oD2QMgG6BbeBkAnQLWgPpExgP28H7E/0GTjPfwAW2EvYX64rn9cAAAAASUVORK5CYII=",
                     32, 32, 0, 0, 0, 255) #basn0g16.png
  doPngSuiteTinyTest("iVBORw0KGgoAAAANSUhEUgAAACAAAAAgEAAAAAFxhsn9AAAABGdBTUEAAYagMeiWXwAAAOJJREFU" &
                     "eJy1kTsOwjAQRMdJCqj4XYHD5DAcj1Okyg2okCyBRLOSC0BDERKCI7xJVmgaa/X8PFo7oESJEtka" &
                     "TeLDjdjjgCMe7eTE96FGd3AL7HvZsdNEaJMVo0GNGm775bgwW6Afj/SAjAY+JsYNXIHtz2xYxTXi" &
                     "UoOek4AbFcCnDYEK4NMGsgXcMrGHJytkBX5HIP8FAhVANIMVIBVANMPfgUAFEM3wAVyG5cxcecY5" &
                     "/dup3LVFa1HXmA61LY59f6Ygp1Eg1gZGQaBRILYGdxoFYmtAGgXx9YmCfPD+RMHwuuAFVpjuiRT/" &
                     "//4AAAAASUVORK5CYII=",
                     32, 32, 0, 0, 0, 255) #basi0g16.png

  #s01n3p01.png s01i3p01.png
  doPngSuiteEqualTest("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAFS3GZcAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
                      "BAQEd/i1owAAAANQTFRFAAD/injSVwAAAApJREFUeJxjYAAAAAIAAUivpHEAAAAASUVORK5CYII=",
                      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
                      "BAQEd/i1owAAAANQTFRFAAD/injSVwAAAApJREFUeJxjYAAAAAIAAUivpHEAAAAASUVORK5CYII=")

  #s07n3p02.png and s07i3p02.png
  doPngSuiteEqualTest("iVBORw0KGgoAAAANSUhEUgAAAAcAAAAHAgMAAAC5PL9AAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
                      "BAQEd/i1owAAAAxQTFRF/wB3AP93//8AAAD/G0OznAAAABpJREFUeJxj+P+H4WoMw605DDfmgEgg" &
                      "+/8fAHF5CrkeXW0HAAAAAElFTkSuQmCC",
                      "iVBORw0KGgoAAAANSUhEUgAAAAcAAAAHAgMAAAHOO4/WAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
                      "BAQEd/i1owAAAAxQTFRF/wB3AP93//8AAAD/G0OznAAAACVJREFUeJxjOMBwgOEBwweGDQyvGf4z" &
                      "/GFIAcI/DFdjGG7MAZIAweMMgVWC+YkAAAAASUVORK5CYII=")

  #basn0g16.png and basi0g16.png
  doPngSuiteEqualTest("iVBORw0KGgoAAAANSUhEUgAAACAAAAAgEAAAAAAGgflrAAAABGdBTUEAAYagMeiWXwAAAF5JREFU" &
                      "eJzV0jEKwDAMQ1E5W+9/xtygk8AoezLVKgSj2Y8/OICnuFcTE2OgOoJgHQiZAN2C9kDKBOgW3AZC" &
                      "JkC3oD2QMgG6BbeBkAnQLWgPpExgP28H7E/0GTjPfwAW2EvYX64rn9cAAAAASUVORK5CYII=",
                      "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgEAAAAAFxhsn9AAAABGdBTUEAAYagMeiWXwAAAOJJREFU" &
                      "eJy1kTsOwjAQRMdJCqj4XYHD5DAcj1Okyg2okCyBRLOSC0BDERKCI7xJVmgaa/X8PFo7oESJEtka" &
                      "TeLDjdjjgCMe7eTE96FGd3AL7HvZsdNEaJMVo0GNGm775bgwW6Afj/SAjAY+JsYNXIHtz2xYxTXi" &
                      "UoOek4AbFcCnDYEK4NMGsgXcMrGHJytkBX5HIP8FAhVANIMVIBVANMPfgUAFEM3wAVyG5cxcecY5" &
                      "/dup3LVFa1HXmA61LY59f6Ygp1Eg1gZGQaBRILYGdxoFYmtAGgXx9YmCfPD+RMHwuuAFVpjuiRT/" &
                      "//4AAAAASUVORK5CYII=")


#Create a PNG image with all known chunks (except only one of tEXt or zTXt) plus
#unknown chunks, and a palette.
proc createComplexPNG(): string =
  let
    w = 16
    h = 17

  var image = newString(w * h)
  for i in 0..image.high:
    image[i] = chr(i mod 256)

  var state = makePNGEncoder()
  state.modeIn.colorType = LCT_PALETTE
  state.modeIn.bitDepth = 8
  state.modeOut.colorType = LCT_PALETTE
  state.modeOut.bitDepth = 8

  state.autoConvert = false
  state.textCompression = true
  state.addID = true

  for i in 0..255:
    state.modeIn.addPalette(i, i, i ,i)
    state.modeOut.addPalette(i, i, i ,i)

  state.backgroundDefined = true
  state.backgroundR = 127

  state.addText("key0", "string0")
  state.addText("key1", "string1")

  state.addIText("ikey0", "ilangtag0", "itranskey0", "istring0")
  state.addIText("ikey1", "ilangtag1", "itranskey1", "istring1")

  state.timeDefined = true
  state.year = 2012
  state.month = 1
  state.day = 2
  state.hour = 3
  state.minute = 4
  state.second = 5

  state.physDefined = true
  state.physX = 1
  state.physY = 2
  state.physUnit = 1

  state.addUnknownChunk("uNKa", "a01")
  state.addUnknownChunk("uNKb", "b00")
  state.addUnknownChunk("uNKc", "c00")

  var png = encodePNG(image, w, h, state)
  var s = newStringStream()
  png.writeChunks s
  result = s.data

#test that, by default, it chooses filter type zero for all scanlines if the image has a palette
proc testPaletteFilterTypesZero() =
  echo "testPaletteFilterTypesZero"
  var raw = createComplexPNG()
  var s = newStringStream(raw)
  var png = s.decodePNG()
  var filterTypes = png.getFilterTypes()

  assertEquals(17, filterTypes.len)
  for i in 0..16:
    assertEquals(0.chr, filterTypes[i])

proc testComplexPNG() =
  echo "testComplexPNG"
  var raw = createComplexPNG()

  var s = newStringStream(raw)
  var state = makePNGDecoder()
  state.readTextChunks = true
  state.rememberUnknownChunks = true

  var png = s.decodePNG(state)
  var info = png.getInfo()

  assertEquals(16, info.width)
  assertEquals(17, info.height)
  assertEquals(true, info.backgroundDefined)
  assertEquals(127 , info.backgroundR)
  assertEquals(true , info.timeDefined)
  assertEquals(2012 , info.year)
  assertEquals(1 , info.month)
  assertEquals(2 , info.day)
  assertEquals(3 , info.hour)
  assertEquals(4 , info.minute)
  assertEquals(5 , info.second)
  assertEquals(true , info.physDefined)
  assertEquals(1 , info.physX)
  assertEquals(2 , info.physY)
  assertEquals(1 , info.physUnit)

  let chunkNames = png.getChunkNames()
  let expectedNames = "IHDR uNKa PLTE tRNS bKGD pHYs uNKb IDAT tIME zTXt zTXt tEXt iTXt iTXt uNKc IEND"
  assertEquals(expectedNames, chunkNames)

  #TODO: test strings and unknown chunks too

proc testPredefinedFilters() =
  let
    w = 32
    h = 32

  echo "testPredefinedFilters"
  var image = generateTestImage(w, h, LCT_RGBA, 8)

  var state = makePNGEncoder()
  state.filterStrategy = LFS_PREDEFINED
  state.filterPaletteZero = false
  state.predefinedFilters = repeat(chr(3), h) #everything to filter type '3'
  var png = encodePNG(image.data, w, h, state)
  var outFilters = png.getFilterTypes()

  assertEquals(h, outFilters.len)
  for i in 0..<h:
    assertEquals(chr(3), outFilters[i])

# Tests combinations of various colors in different orders
proc testFewColors() =
  echo "codec test few colors"

  var image = new(Image)
  image.width = 20
  image.height = 20
  image.colorType = LCT_RGBA
  image.bitDepth = 8
  image.data = newString(image.width * image.height * 4)

  var colors = newSeq[char]()

  colors.add(0.chr);   colors.add(0.chr);   colors.add(0.chr);   colors.add(255.chr) # black
  colors.add(255.chr); colors.add(255.chr); colors.add(255.chr); colors.add(255.chr) # white
  colors.add(128.chr); colors.add(128.chr); colors.add(128.chr); colors.add(255.chr) # grey
  colors.add(0.chr);   colors.add(0.chr);   colors.add(255.chr); colors.add(255.chr) # blue
  colors.add(255.chr); colors.add(255.chr); colors.add(255.chr); colors.add(1.chr)   # transparent white
  colors.add(255.chr); colors.add(255.chr); colors.add(255.chr); colors.add(1.chr)   # translucent white

  let len = colors.len

  for u in countup(0, len-1, 4):
    for v in countup(0, len-1, 4):
      for w in countup(0, len-1, 4):
        for z in countup(0, len-1, 4):
          for c in 0..<4:
            for y in 0..<image.height:
              for x in 0..<image.width:
                image.data[y * image.width * 4 + x * 4 + c] = if (x xor y) != 0: colors[u + c] else: colors[v + c]

            image.data[c] = colors[w + c]
            image.data[image.data.len - 4 + c] = colors[z + c]
          doCodecTest(image)

proc testColorKeyConvert() =
  echo "testColorKeyConvert"
  let
    w = 32
    h = 32

  var image = newString(w * h * 4)
  let len = w*h
  for i in 0..len-1:
    image[i * 4 + 0] = chr(i mod 256)
    image[i * 4 + 1] = chr(i div 256)
    image[i * 4 + 2] = 0.chr
    image[i * 4 + 3] = if i == 23: 0.chr else: 255.chr

  var raw = encodePNG(image, w, h)
  var s = newStringStream()
  raw.writeChunks s
  s.setPosition 0

  var png = s.decodePNG()
  var info = png.getInfo()
  var image2 = png.convert(LCT_RGBA, 8)

  assertEquals(32 , info.width)
  assertEquals(32 , info.height)
  assertEquals(true  , info.mode.keyDefined)
  assertEquals(23 , info.mode.keyR)
  assertEquals(0  , info.mode.keyG)
  assertEquals(0  , info.mode.keyB)
  assertEquals(image.len , image2.data.len)

  for i in 0..image.high:
    assertEquals(image[i], image2.data[i])

proc removeSpaces(input: string): string =
  result = ""
  for c in input:
    if c != ' ': result.add c

proc bitStringToBytes(input: string): string =
  let bits = removeSpaces(input)
  result = newString((bits.len + 7) div 8)

  for i in 0..bits.high:
    let c = bits[i]
    let j = i div 8
    let k = i mod 8
    if k == 0: result[j] = chr(0)
    if c == '1': result[j] = chr(result[j].ord or (1 shl (7 - k)))

#test color convert on a single pixel. Testing palette and testing color keys is
#not supported by this function. Pixel values given using bits in an std::string
#of 0's and 1's.
proc colorConvertTest(bits_in: string, colorType_in: PNGcolorType, bitDepth_in: int,
    bits_out: string, colorType_out: PNGcolorType, bitDepth_out: int) =

  echo "color convert test ", bits_in, " - ", bits_out
  let expected = bitStringToBytes(bits_out)
  let image = initBuffer(bitStringToBytes(bits_in))
  let modeIn = newColorMode(colorType_in, bitDepth_in)
  let modeOut = newColorMode(colorType_out, bitDepth_out)
  var actual = newString(expected.len)
  var actualView = initBuffer(actual)
  convert(actualView, image, modeOut, modeIn, 1)
  for i in 0..expected.high:
    assertEquals(expected[i].int, actual[i].int, "byte " & $i)

#Tests some specific color conversions with specific color bit combinations
proc testColorConvert() =
  #test color conversions to RGBA8
  colorConvertTest("1", LCT_GREY, 1, "11111111 11111111 11111111 11111111", LCT_RGBA, 8)
  colorConvertTest("10", LCT_GREY, 2, "10101010 10101010 10101010 11111111", LCT_RGBA, 8)
  colorConvertTest("1001", LCT_GREY, 4, "10011001 10011001 10011001 11111111", LCT_RGBA, 8)
  colorConvertTest("10010101", LCT_GREY, 8, "10010101 10010101 10010101 11111111", LCT_RGBA, 8)
  colorConvertTest("10010101 11111110", LCT_GREY_ALPHA, 8, "10010101 10010101 10010101 11111110", LCT_RGBA, 8)
  colorConvertTest("10010101 00000001 11111110 00000001", LCT_GREY_ALPHA, 16, "10010101 10010101 10010101 11111110", LCT_RGBA, 8)
  colorConvertTest("01010101 00000000 00110011", LCT_RGB, 8, "01010101 00000000 00110011 11111111", LCT_RGBA, 8)
  colorConvertTest("01010101 00000000 00110011 10101010", LCT_RGBA, 8, "01010101 00000000 00110011 10101010", LCT_RGBA, 8)
  colorConvertTest("10101010 01010101 11111111 00000000 11001100 00110011", LCT_RGB, 16, "10101010 11111111 11001100 11111111", LCT_RGBA, 8)
  colorConvertTest("10101010 01010101 11111111 00000000 11001100 00110011 11100111 00011000", LCT_RGBA, 16, "10101010 11111111 11001100 11100111", LCT_RGBA, 8)

  #test color conversions to RGB8
  colorConvertTest("1", LCT_GREY, 1, "11111111 11111111 11111111", LCT_RGB, 8)
  colorConvertTest("10", LCT_GREY, 2, "10101010 10101010 10101010", LCT_RGB, 8)
  colorConvertTest("1001", LCT_GREY, 4, "10011001 10011001 10011001", LCT_RGB, 8)
  colorConvertTest("10010101", LCT_GREY, 8, "10010101 10010101 10010101", LCT_RGB, 8)
  colorConvertTest("10010101 11111110", LCT_GREY_ALPHA, 8, "10010101 10010101 10010101", LCT_RGB, 8)
  colorConvertTest("10010101 00000001 11111110 00000001", LCT_GREY_ALPHA, 16, "10010101 10010101 10010101", LCT_RGB, 8)
  colorConvertTest("01010101 00000000 00110011", LCT_RGB, 8, "01010101 00000000 00110011", LCT_RGB, 8)
  colorConvertTest("01010101 00000000 00110011 10101010", LCT_RGBA, 8, "01010101 00000000 00110011", LCT_RGB, 8)
  colorConvertTest("10101010 01010101 11111111 00000000 11001100 00110011", LCT_RGB, 16, "10101010 11111111 11001100", LCT_RGB, 8)
  colorConvertTest("10101010 01010101 11111111 00000000 11001100 00110011 11100111 00011000", LCT_RGBA, 16, "10101010 11111111 11001100", LCT_RGB, 8)

  #test color conversions to RGBA16
  colorConvertTest("1", LCT_GREY, 1, "11111111 11111111 11111111 11111111 11111111 11111111 11111111 11111111", LCT_RGBA, 16)
  colorConvertTest("10", LCT_GREY, 2, "10101010 10101010 10101010 10101010 10101010 10101010 11111111 11111111", LCT_RGBA, 16)

  #test greyscale color conversions
  colorConvertTest("1", LCT_GREY, 1, "11111111", LCT_GREY, 8)
  colorConvertTest("1", LCT_GREY, 1, "1111111111111111", LCT_GREY, 16)
  colorConvertTest("0", LCT_GREY, 1, "00000000", LCT_GREY, 8)
  colorConvertTest("0", LCT_GREY, 1, "0000000000000000", LCT_GREY, 16)
  colorConvertTest("11", LCT_GREY, 2, "11111111", LCT_GREY, 8)
  colorConvertTest("11", LCT_GREY, 2, "1111111111111111", LCT_GREY, 16)
  colorConvertTest("10", LCT_GREY, 2, "10101010", LCT_GREY, 8)
  colorConvertTest("10", LCT_GREY, 2, "1010101010101010", LCT_GREY, 16)
  colorConvertTest("1000", LCT_GREY, 4, "10001000", LCT_GREY, 8)
  colorConvertTest("1000", LCT_GREY, 4, "1000100010001000", LCT_GREY, 16)
  colorConvertTest("10110101", LCT_GREY, 8, "1011010110110101", LCT_GREY, 16)
  colorConvertTest("1011010110110101", LCT_GREY, 16, "10110101", LCT_GREY, 8)

  #others
  colorConvertTest("11111111 11111111 11111111 00000000 00000000 00000000", LCT_RGB, 1, "10", LCT_GREY, 1)

#This tests color conversions from any color model to any color model, with any bit depth
#But it tests only with colors black and white, because that are the only colors every single model supports
proc testColorConvert2() =
  echo "testColorConvert2"

  proc toString(input: openArray[int]): string =
    result = newString(input.len)
    for i in 0..input.high:
      result[i] = chr(input[i])

  const
    combos = [(colorType: LCT_GREY, bitDepth: 1),
      (colorType: LCT_GREY, bitDepth: 2),
      (colorType: LCT_GREY, bitDepth: 4),
      (colorType: LCT_GREY, bitDepth: 8),
      (colorType: LCT_GREY, bitDepth: 16),
      (colorType: LCT_RGB, bitDepth: 8),
      (colorType: LCT_RGB, bitDepth: 16),
      (colorType: LCT_PALETTE, bitDepth: 1),
      (colorType: LCT_PALETTE, bitDepth: 2),
      (colorType: LCT_PALETTE, bitDepth: 4),
      (colorType: LCT_PALETTE, bitDepth: 8),
      (colorType: LCT_GREY_ALPHA, bitDepth: 8),
      (colorType: LCT_GREY_ALPHA, bitDepth: 16),
      (colorType: LCT_RGBA, bitDepth: 8),
      (colorType: LCT_RGBA, bitDepth: 16)]

    eight = initBuffer([0,0,0,255, 255,255,255,255,
      0,0,0,255, 255,255,255,255,
      255,255,255,255, 0,0,0,255,
      255,255,255,255, 255,255,255,255,
      0,0,0,255].toString()) #input in RGBA8

  var
    modeIn = newColorMode()
    modeOut = newColorMode()
    mode_8 = newColorMode()
    input = initBuffer(newString(72))
    output = initBuffer(newString(72))
    eight2 = initBuffer(newString(36))

  for i in 0..255:
    let j = if i == 1: 255 else: i
    modeIn.addPalette(j, j, j, 255)
    modeOut.addPalette(j, j, j, 255)

  for cma in combos:
    modeIn.colorType = cma.colorType
    modeIn.bitDepth = cma.bitDepth

    for cmb in combos:
      modeOut.colorType = cmb.colorType
      modeOut.bitDepth = cmb.bitDepth

      convert(input, eight, modeIn, mode_8, 3 * 3)
      convert(output, input, modeOut, modeIn, 3 * 3) #Test input to output type
      convert(eight2, output, mode_8, modeOut, 3 * 3)
      assertEquals(eight.data, eight2.data)

#tests that there are no crashes with auto color chooser in case of palettes with translucency etc...
proc testPaletteToPaletteConvert() =
  echo "testPaletteToPaletteConvert"
  let
    w = 16
    h = 16

  var image = newString(w * h)
  for i in 0..image.high: image[i] = chr(i mod 256)

  var state = makePNGEncoder()
  state.modeOut.colorType = LCT_PALETTE
  state.modeIn.colorType = LCT_PALETTE
  state.modeOut.bitDepth = 8
  state.modeIn.bitDepth = 8

  assertEquals(true, state.autoConvert)

  for i in 0..255:
    state.modeIn.addPalette(i, i, i, i)
    state.modeOut.addPalette(i, i, i, i)

  discard encodePNG(image, w, h, state)

#for this test, you have to choose palette colors that cause PNG to actually use a palette,
#so don't use all greyscale colors for example
proc doRGBAToPaletteTest(palette: openArray[int], expectedType = LCT_PALETTE) =
  echo "testRGBToPaletteConvert ", palette.len

  let
    w = palette.len div 4
    h = 257 #PNG encodes no palette if image is too small

  var image = newString(w * h * 4)
  for i in 0..image.high:
    image[i] = palette[i mod palette.len].chr

  var raw = encodePNG(image, w, h)
  var s = newStringStream()
  raw.writeChunks s

  s.setPosition 0
  var png2 = s.decodePNG()
  var info = png2.getInfo()
  var image2 = png2.convert(LCT_RGBA, 8)

  assertEquals(image2.data, image)

  assertEquals(expectedType, info.mode.colorType)
  if expectedType == LCT_PALETTE:
    assertEquals((palette.len div 4), info.mode.paletteSize)
    for i in 0..info.mode.palette.high:
      assertEquals(info.mode.palette[i].r, image[i * 4 + 0])
      assertEquals(info.mode.palette[i].g, image[i * 4 + 1])
      assertEquals(info.mode.palette[i].b, image[i * 4 + 2])
      assertEquals(info.mode.palette[i].a, image[i * 4 + 3])

proc testRGBToPaletteConvert() =
  const
    palette1 = [1,2,3,4]
    palette2 = [1,2,3,4, 5,6,7,8]
    palette3 = [1,1,1,255, 20,20,20,255, 20,20,21,255]

  doRGBAToPaletteTest(palette1)
  doRGBAToPaletteTest(palette2)
  doRGBAToPaletteTest(palette3)

  var palette: seq[int] = @[]
  for i in 0..255:
    palette.add(i)
    palette.add(5)
    palette.add(6)
    palette.add(128)

  doRGBAToPaletteTest(palette)
  palette.add(5)
  palette.add(6)
  palette.add(7)
  palette.add(8)
  doRGBAToPaletteTest(palette, LCT_RGBA)

#Test that when decoding to 16-bit per channel, it always uses big endian consistently.
#It should always output big endian, the convention used inside of PNG, even though x86 CPU's are little endian.
proc test16bitColorEndianness() =
  echo "test16bitColorEndianness"

  #basn0g16.png from the PNG test suite
  var base64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgEAAAAAAGgflrAAAABGdBTUEAAYagMeiWXwAAAF5JREFU" &
               "eJzV0jEKwDAMQ1E5W+9/xtygk8AoezLVKgSj2Y8/OICnuFcTE2OgOoJgHQiZAN2C9kDKBOgW3AZC" &
               "JkC3oD2QMgG6BbeBkAnQLWgPpExgP28H7E/0GTjPfwAW2EvYX64rn9cAAAAASUVORK5CYII="

  var png = fromBase64(base64)
  var s = newStringStream(png)

  #Decode from 16-bit grey image to 16-bit per channel RGBA
  var decoded = s.decodePNG(LCT_RGBA, 16)
  assertEquals(0x09, decoded.data[8].ord)
  assertEquals(0x00, decoded.data[9].ord)

  #Decode from 16-bit grey image to 16-bit grey raw image (no conversion)
  var state = makePNGDecoder()
  state.colorConvert = false
  s.setPosition 0
  var raw = s.decodePNG(state)
  assertEquals(0x09, raw.pixels[2].ord)
  assertEquals(0x00, raw.pixels[3].ord)

  #Decode from 16-bit per channel RGB image to 16-bit per channel RGBA
  base64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgEAIAAACsiDHgAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
           "DQ0N0DeNwQAAAH5JREFUeJztl8ENxEAIAwcJ6cpI+q8qKeNepAgelq2dCjz4AdQM1jRcf3WIDQ13" &
           "qUNsiBBQZ1gR0cARUFIz3pug3586wo5+rOcfIaBOsCSggSOgpcB8D4D3R9DgfUyECIhDbAhp4Ajo" &
           "KPD+CBq8P4IG72MiQkCdYUVEA0dAyQcwUyZpXH92ZwAAAABJRU5ErkJggg==" #cs3n2c16.png

  png = fromBase64(base64)
  s = newStringStream(png)
  decoded = s.decodePNG(LCT_RGBA, 16)

  assertEquals(0x1f, decoded.data[258].ord)
  assertEquals(0xf9, decoded.data[259].ord)

  #Decode from 16-bit per channel RGB image to 16-bit per channel RGBA raw image (no conversion)
  s.setPosition 0
  raw = s.decodePNG(state)

  assertEquals(0x1f, raw.pixels[194].ord)
  assertEquals(0xf9, raw.pixels[195].ord)

  #Decode from palette image to 16-bit per channel RGBA
  base64 = "iVBORw0KGgoAAAANSUhEUgAAAAcAAAAHAgMAAAC5PL9AAAAABGdBTUEAAYagMeiWXwAAAANzQklU" &
           "BAQEd/i1owAAAAxQTFRF/wB3AP93//8AAAD/G0OznAAAABpJREFUeJxj+P+H4WoMw605DDfmgEgg" &
           "+/8fAHF5CrkeXW0HAAAAAElFTkSuQmCC" #s07n3p02.png

  png = fromBase64(base64)
  s = newStringStream(png)
  decoded = s.decodePNG(LCT_RGBA, 16)

  assertEquals(0x77, decoded.data[84].ord)
  assertEquals(0x77, decoded.data[85].ord)

proc testNoAutoConvert() =
  echo "testNoAutoConvert"
  let
    w = 32
    h = 32

  var image = newString(w * h * 4)
  let len = w * h
  for i in 0..len-1:
    let c = if (i mod 2) != 0: 255.chr else: 0.chr
    image[i * 4 + 0] = c
    image[i * 4 + 1] = c
    image[i * 4 + 2] = c
    image[i * 4 + 3] = 0.chr

  var state = makePNGEncoder()
  state.modeOut.colorType = LCT_RGBA
  state.modeOut.bitDepth = 8
  state.autoConvert = false
  var png = encodePNG(image, w, h, state)

  var s = newStringStream()
  png.writeChunks s
  s.setPosition 0

  var raw = s.decodePNG()
  var info = raw.getInfo()

  assertEquals(32 , info.width)
  assertEquals(32 , info.height)

  assertEquals(LCT_RGBA , info.mode.colorType)
  assertEquals(8 , info.mode.bitDepth)
  assertEquals(image , raw.pixels)

#colors is in RGBA, inbitDepth must be 8 or 16, the amount of bits per channel.
#colorType and bitDepth are the expected values. insize is amount of pixels. So the amount of bytes is insize * 4 * (inbitDepth / 8)
proc testAutoColorModel(colors: string, inbitDepth: int, colorType: PNGcolorType, bitDepth: int,  key: bool) =
  echo "testAutoColorModel ", inbitDepth, " ", colorType, " ", bitDepth, " ", key
  let innum = colors.len div 4 * inbitDepth div 8
  let num = max(innum, 65536) #Make image bigger so the convert doesn't avoid palette due to small image.
  var colors2 = newString(num * 4 * (inbitDepth div 8))

  for i in 0..colors2.high:
    colors2[i] = colors[i mod colors.len]

  var png = encodePNG(colors2, LCT_RGBA, inbitDepth, num, 1)
  var s = newStringStream()
  png.writeChunks s

  #now extract the color type it chose
  s.setPosition 0
  var raw = s.decodePNG()
  var info = raw.getInfo()
  var decoded = raw.convert(LCT_RGBA, inbitdepth)

  assertEquals(num , info.width)
  assertEquals(1 , info.height)
  assertEquals(colorType , info.mode.colorType)
  assertEquals(bitDepth , info.mode.bitDepth)
  assertEquals(key , info.mode.keyDefined)

  for i in 0..colors.high:
    assertEquals(colors[i], decoded.data[i])

proc addColor(colors: var string, r, g, b, a: int) =
  colors.add r.chr
  colors.add g.chr
  colors.add b.chr
  colors.add a.chr

proc addColor16(colors: var string, r, g, b, a: int) =
  colors.add chr(r and 255)
  colors.add chr((r shr 8) and 255)
  colors.add chr(g and 255)
  colors.add chr((g shr 8) and 255)
  colors.add chr(b and 255)
  colors.add chr((b shr 8) and 255)
  colors.add chr(a and 255)
  colors.add chr((a shr 8) and 255)

proc testAutoColorModels() =
  var grey1 = ""
  for i in 0..1: addColor(grey1, i * 255, i * 255, i * 255, 255)
  testAutoColorModel(grey1, 8, LCT_GREY, 1, false)

  var grey2 = ""
  for i in 0..3: addColor(grey2, i * 85, i * 85, i * 85, 255)
  testAutoColorModel(grey2, 8, LCT_GREY, 2, false)

  var grey4 = ""
  for i in 0..15: addColor(grey4, i * 17, i * 17, i * 17, 255)
  testAutoColorModel(grey4, 8, LCT_GREY, 4, false)

  var grey8 = ""
  for i in 0..255: addColor(grey8, i, i, i, 255)
  testAutoColorModel(grey8, 8, LCT_GREY, 8, false)

  var grey16 = ""
  for i in 0..256: addColor16(grey16, i, i, i, 65535)
  testAutoColorModel(grey16, 16, LCT_GREY, 16, false)

  var palette = ""
  addColor(palette, 0, 0, 1, 255)
  testAutoColorModel(palette, 8, LCT_PALETTE, 1, false)
  addColor(palette, 0, 0, 2, 255)
  testAutoColorModel(palette, 8, LCT_PALETTE, 1, false)
  for i in 3..4: addColor(palette, 0, 0, i, 255)
  testAutoColorModel(palette, 8, LCT_PALETTE, 2, false)
  for i in 5..7: addColor(palette, 0, 0, i, 255)
  testAutoColorModel(palette, 8, LCT_PALETTE, 4, false)
  for i in 8..17: addColor(palette, 0, 0, i, 255)
  testAutoColorModel(palette, 8, LCT_PALETTE, 8, false)
  addColor(palette, 0, 0, 18, 0) #transparent
  testAutoColorModel(palette, 8, LCT_PALETTE, 8, false)
  addColor(palette, 0, 0, 18, 1) #translucent
  testAutoColorModel(palette, 8, LCT_PALETTE, 8, false)

  var rgb = grey8
  addColor(rgb, 255, 0, 0, 255)
  testAutoColorModel(rgb, 8, LCT_RGB, 8, false)

  var rgb_key = rgb
  addColor(rgb_key, 128, 0, 0, 0)
  testAutoColorModel(rgb_key, 8, LCT_RGB, 8, true)

  var rgb_key2 = rgb_key
  addColor(rgb_key2, 128, 0, 0, 255) #same color but opaque ==> no more key
  testAutoColorModel(rgb_key2, 8, LCT_RGBA, 8, false)

  var rgb_key3 = rgb_key
  addColor(rgb_key3, 128, 0, 0, 255) #semi-translucent ==> no more key
  testAutoColorModel(rgb_key3, 8, LCT_RGBA, 8, false)

  var rgb_key4 = rgb_key
  addColor(rgb_key4, 128, 0, 0, 255)
  addColor(rgb_key4, 129, 0, 0, 255) #two different transparent colors ==> no more key
  testAutoColorModel(rgb_key4, 8, LCT_RGBA, 8, false)

  var grey1_key = grey1
  grey1_key[7] = 0.chr
  testAutoColorModel(grey1_key, 8, LCT_GREY, 1, true)

  var grey2_key = grey2
  grey2_key[7] = 0.chr
  testAutoColorModel(grey2_key, 8, LCT_GREY, 2, true)

  var grey4_key = grey4
  grey4_key[7] = 0.chr
  testAutoColorModel(grey4_key, 8, LCT_GREY, 4, true)

  var grey8_key = grey8
  grey8_key[7] = 0.chr
  testAutoColorModel(grey8_key, 8, LCT_GREY, 8, true)

  var small16 = ""
  addColor16(small16, 1, 0, 0, 65535)
  testAutoColorModel(small16, 16, LCT_RGB, 16, false)

  var small16a = ""
  addColor16(small16a, 1, 0, 0, 1)
  testAutoColorModel(small16a, 16, LCT_RGBA, 16, false)

  var not16 = ""
  addColor16(not16, 257, 257, 257, 0)
  testAutoColorModel(not16, 16, LCT_PALETTE, 1, false)

  var alpha16 = ""
  addColor16(alpha16, 257, 0, 0, 10000)
  testAutoColorModel(alpha16, 16, LCT_RGBA, 16, false)

proc testFilter() =
  echo "test Filter"
  let input = "tfilter.png"
  let temp = "temp.png"
  let png = loadPNG32(input)
  discard savePNG32(temp, png.data, png.width, png.height)
  let png2 = loadPNG32(temp)
  if png.data != png2.data:
    echo "testFilter failed"
    quit()

proc testPaletteToPaletteDecode() =
  echo "testPaletteToPaletteDecode"
  # It's a bit big for a 2x2 image... but this tests needs one with 256 palette entries in it.
  let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAMAAABFaP0WAAAAA3NCSVQICAjb4U/gAAADAFBMVEUA" &
               "AAAAADMAAGYAAJkAAMwAAP8AMwAAMzMAM2YAM5kAM8wAM/8AZgAAZjMAZmYAZpkAZswAZv8AmQAA" &
               "mTMAmWYAmZkAmcwAmf8AzAAAzDMAzGYAzJkAzMwAzP8A/wAA/zMA/2YA/5kA/8wA//8zAAAzADMz" &
               "AGYzAJkzAMwzAP8zMwAzMzMzM2YzM5kzM8wzM/8zZgAzZjMzZmYzZpkzZswzZv8zmQAzmTMzmWYz" &
               "mZkzmcwzmf8zzAAzzDMzzGYzzJkzzMwzzP8z/wAz/zMz/2Yz/5kz/8wz//9mAABmADNmAGZmAJlm" &
               "AMxmAP9mMwBmMzNmM2ZmM5lmM8xmM/9mZgBmZjNmZmZmZplmZsxmZv9mmQBmmTNmmWZmmZlmmcxm" &
               "mf9mzABmzDNmzGZmzJlmzMxmzP9m/wBm/zNm/2Zm/5lm/8xm//+ZAACZADOZAGaZAJmZAMyZAP+Z" &
               "MwCZMzOZM2aZM5mZM8yZM/+ZZgCZZjOZZmaZZpmZZsyZZv+ZmQCZmTOZmWaZmZmZmcyZmf+ZzACZ" &
               "zDOZzGaZzJmZzMyZzP+Z/wCZ/zOZ/2aZ/5mZ/8yZ///MAADMADPMAGbMAJnMAMzMAP/MMwDMMzPM" &
               "M2bMM5nMM8zMM//MZgDMZjPMZmbMZpnMZszMZv/MmQDMmTPMmWbMmZnMmczMmf/MzADMzDPMzGbM" &
               "zJnMzMzMzP/M/wDM/zPM/2bM/5nM/8zM////AAD/ADP/AGb/AJn/AMz/AP//MwD/MzP/M2b/M5n/" &
               "M8z/M///ZgD/ZjP/Zmb/Zpn/Zsz/Zv//mQD/mTP/mWb/mZn/mcz/mf//zAD/zDP/zGb/zJn/zMz/" &
               "zP///wD//zP//2b//5n//8z///8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" &
               "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" &
               "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABlenwdAAABAHRSTlP/////////////////////////" &
               "////////////////////////////////////////////////////////////////////////////" &
               "////////////////////////////////////////////////////////////////////////////" &
               "////////////////////////////////////////////////////////////////////////////" &
               "//////////////////////////////////8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" &
               "AAAAAAAAAAAAG8mZagAAAAlwSFlzAAAOTQAADpwB3vacVwAAAA5JREFUCJlj2CLHwHodAATjAa+k" &
               "lTE5AAAAAElFTkSuQmCC"

  let png = fromBase64(base64)
  var s = newStringStream(png)
  let decoded = s.decodePNG(LCT_PALETTE, 8)

  assertEquals(2, decoded.width)
  assertEquals(2, decoded.height)
  assertEquals(180, decoded.data[0].int)
  assertEquals(30,  decoded.data[1].int)
  assertEquals(5,   decoded.data[2].int)
  assertEquals(215, decoded.data[3].int)

# 2-bit palette
proc testPaletteToPaletteDecode2() =
  echo "testPaletteToPaletteDecode2"
  let base64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgAgMAAAAOFJJnAAAADFBMVEX/AAAA/wAAAP/////7AGD2AAAAE0lEQVR4AWMQhAKG3VCALDIqAgDl2WYBCQHY9gAAAABJRU5ErkJggg=="
  let png = fromBase64(base64)
  var s = newStringStream(png)
  let decoded = s.decodePNG(LCT_PALETTE, 8)

  assertEquals(32, decoded.width)
  assertEquals(32, decoded.height)
  assertEquals(0, decoded.data[0].int)
  assertEquals(1, decoded.data[1].int)

  # Now add a user-specified output palette, that differs from the input palette. That should give error 82.
  #LodePNGState state;
  #lodepng_state_init(&state);
  #state.info_raw.colortype = LCT_PALETTE;
  #state.info_raw.bitdepth = 8;
  #lodepng_palette_add(&state.info_raw, 0, 0, 0, 255);
  #lodepng_palette_add(&state.info_raw, 1, 1, 1, 255);
  #lodepng_palette_add(&state.info_raw, 2, 2, 2, 255);
  #lodepng_palette_add(&state.info_raw, 3, 3, 3, 255);
  #unsigned char* image2 = 0;
  #unsigned error2 = lodepng_decode(&image2, &width, &height, &state, &png[0], png.size());
  #ASSERT_EQUALS(82, error2);
  #lodepng_state_cleanup(&state);
  #free(image2);

proc flipBit(c: uint8, bitpos: int): uint8 =
  result = c xor uint8(1 shl bitpos)

# Test various broken inputs. Returned errors are not checked, what is tested is
# that is doesn't crash, and, when run with valgrind, no memory warnings are
# given.
proc testFuzzing() =
  echo "testFuzzing"
  var
    png = createComplexPNG()
    broken = newString(png.len)
    errors = initTable[string, int]()

  copyMem(broken.cstring, png.cstring, png.len)
  var settings = makePNGDecoder()
  settings.ignoreCRC = true
  settings.ignoreAdler32 = true

  for i in 0..<png.len:
    broken[i] = cast[char](not png[i].int)

    try:
      var s = newStringStream(broken)
      discard s.decodePNG(settings)
    except Exception as ex:
      if errors.hasKey(ex.msg):
        inc errors[ex.msg]
      else:
        errors[ex.msg] = 0

    broken[i] = chr(0)

    try:
      var s = newStringStream(broken)
      discard s.decodePNG(settings)
    except Exception as ex:
      if errors.hasKey(ex.msg):
        inc errors[ex.msg]
      else:
        errors[ex.msg] = 0

    for j in 0..<8:
      broken[i] = chr(flipBit(png[i].uint8, j))
      try:
        var s = newStringStream(broken)
        discard s.decodePNG(settings)
      except Exception as ex:
        if errors.hasKey(ex.msg):
          inc errors[ex.msg]
        else:
          errors[ex.msg] = 0

    broken[i] = chr(255)
    try:
      var s = newStringStream(broken)
      discard s.decodePNG(settings)
    except Exception as ex:
      if errors.hasKey(ex.msg):
        inc errors[ex.msg]
      else:
        errors[ex.msg] = 0
    GC_fullcollect()
    echo GC_getStatistics()
    broken[i] = png[i] #fix it again for the next test

  echo "testFuzzing shrinking"
  copyMem(broken.cstring, png.cstring, png.len)
  while broken.len > 0:
    broken.setLen(broken.len - 1)
    try:
      var s = newStringStream(broken)
      discard s.decodePNG(settings)
    except Exception as ex:
      if errors.hasKey(ex.msg):
        inc errors[ex.msg]
      else:
        errors[ex.msg] = 0

  echo GC_getStatistics()
  #For fun, print the number of each error
  echo "Fuzzing error code counts: "
  for key, val in pairs(errors):
    echo key, " : ", val


proc doMain() =
  # PNG
  testPNGCodec()
  testPngSuiteTiny()
  testPaletteFilterTypesZero()
  testComplexPNG()
  testPredefinedFilters()
  testPaletteToPaletteDecode()
  testPaletteToPaletteDecode2()
  #testFuzzing() OOM

  # COLOR
  testFewColors()
  testColorKeyConvert()
  testColorConvert()
  testColorConvert2()
  testPaletteToPaletteConvert()
  testRGBToPaletteConvert()
  test16bitColorEndianness()
  testNoAutoConvert()
  testAutoColorModels()
  testFilter()

doMain()
