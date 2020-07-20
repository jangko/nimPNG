# Portable Network Graphics Encoder and Decoder written in Nim
#
# Copyright (c) 2015-2016 Andri Lim
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# this is a rewrite of LodePNG(www.lodev.org/lodepng)
# to be as idiomatic Nim as possible
# part of nimPDF sister projects
#-------------------------------------

import streams, endians, tables, hashes, math, typetraits
import nimPNG/[buffer, nimz, filters, results]

import strutils

export typetraits, results

const
  NIM_PNG_VERSION = "0.3.1"

type
  PNGChunkType = distinct int32

  Pixels* = seq[uint8]

  PNGColorType* = enum
    LCT_GREY = 0,       # greyscale: 1,2,4,8,16 bit
    LCT_RGB = 2,        # RGB: 8,16 bit
    LCT_PALETTE = 3,    # palette: 1,2,4,8 bit
    LCT_GREY_ALPHA = 4, # greyscale with alpha: 8,16 bit
    LCT_RGBA = 6        # RGB with alpha: 8,16 bit

  PNGSettings = ref object of RootObj

  PNGDecoder* = ref object of PNGSettings
    colorConvert*: bool

    #if false but rememberUnknownChunks is true, they're stored in the unknown chunks
    #(off by default, useful for a png editor)

    readTextChunks*: bool
    rememberUnknownChunks*: bool
    ignoreCRC*: bool
    ignoreAdler32*: bool

  PNGInterlace* = enum
    IM_NONE = 0, IM_INTERLACED = 1

  PNGChunk = ref object of RootObj
    length: int #range[0..0x7FFFFFFF]
    chunkType: PNGChunkType
    crc: uint32
    data: string
    pos: int

  PNGHeader = ref object of PNGChunk
    width, height: int #range[1..0x7FFFFFFF]
    bitDepth: int
    colorType: PNGColorType
    compressionMethod: int
    filterMethod: int
    interlaceMethod: PNGInterlace

  RGBA8* = object
    r*, g*, b*, a*: char

  RGBA16* = object
    r*, g*, b*, a*: uint16

  ColorTree8 = Table[RGBA8, int]

  PNGPalette = ref object of PNGChunk
    palette: seq[RGBA8]

  PNGData = ref object of PNGChunk
    idat: string

  PNGTime = ref object of PNGChunk
    year: int #range[0..65535]
    month: int #range[1..12]
    day: int #range[1..31]
    hour: int #range[0..23]
    minute: int #range[0..59]
    second: int #range[0..60] #to allow for leap seconds

  PNGPhys = ref object of PNGChunk
    physX, physY: int
    unit: int

  PNGTrans = ref object of PNGChunk
    keyR, keyG, keyB: int

  PNGBackground = ref object of PNGChunk
    bkgdR, bkgdG, bkgdB: int

  PNGText = ref object of PNGChunk
    keyword: string
    text: string

  PNGZtxt = ref object of PNGChunk
    keyword: string
    text: string

  PNGItxt = ref object of PNGChunk
    keyword: string
    text: string
    languageTag: string
    translatedKeyword: string

  PNGGamma = ref object of PNGChunk
    gamma: int

  PNGChroma = ref object of PNGChunk
    whitePointX, whitePointY: int
    redX, redY: int
    greenX, greenY: int
    blueX, blueY: int

  PNGStandarRGB = ref object of PNGChunk
    renderingIntent: int

  PNGICCProfile = ref object of PNGChunk
    profileName: string
    profile: string

  PNGSPEntry = object
    red, green, blue, alpha, frequency: int

  PNGSPalette = ref object of PNGChunk
    paletteName: string
    sampleDepth: int
    palette: seq[PNGSPEntry]

  PNGHist = ref object of PNGChunk
    histogram: seq[int]

  PNGSbit = ref object of PNGChunk

  APNGAnimationControl = ref object of PNGChunk
    numFrames: int
    numPlays: int

  APNG_DISPOSE_OP* = enum
    APNG_DISPOSE_OP_NONE
    APNG_DISPOSE_OP_BACKGROUND
    APNG_DISPOSE_OP_PREVIOUS

  APNG_BLEND_OP* = enum
    APNG_BLEND_OP_SOURCE
    APNG_BLEND_OP_OVER

  APNGFrameChunk = ref object of PNGChunk
    sequenceNumber: int

  APNGFrameControl* = ref object of APNGFrameChunk
    width*: int
    height*: int
    xOffset*: int
    yOffset*: int
    delayNum*: int
    delayDen*: int
    disposeOp*: APNG_DISPOSE_OP
    blendOp*: APNG_BLEND_OP

  APNGFrameData = ref object of APNGFrameChunk
    # during decoding frameDataPos points to chunk.data[pos]
    # during encoding frameDataPos points to png.apngPixels[pos] and png.apngChunks[pos]
    frameDataPos: int

  PNGColorMode* = ref object
    colorType*: PNGColorType
    bitDepth*: int
    paletteSize*: int
    palette*: seq[RGBA8]
    keyDefined*: bool
    keyR*, keyG*, keyB*: int

  PNGInfo* = ref object
    width*: int
    height*: int
    mode*: PNGColorMode
    backgroundDefined*: bool
    backgroundR*, backgroundG*, backgroundB*: int

    physDefined*: bool
    physX*, physY*, physUnit*: int

    timeDefined*: bool
    year*: int #range[0..65535]
    month*: int #range[1..12]
    day*: int #range[1..31]
    hour*: int #range[0..23]
    minute*: int #range[0..59]
    second*: int #range[0..60] #to allow for leap seconds

  PNG*[T] = ref object
    # during encoding, settings is PNGEncoder
    # during decoding, settings is PNGDecoder
    settings*: PNGSettings
    chunks*: seq[PNGChunk]
    pixels*: T
    # w & h used during encoding process
    width*, height*: int
    # during encoding, apngChunks contains only fcTL chunks
    # during decoding, apngChunks contains both fcTL and fdAT chunks
    apngChunks*: seq[APNGFrameChunk]
    firstFrameIsDefaultImage*: bool
    isAPNG*: bool
    apngPixels*: seq[T]

  APNGFrame*[T] = ref object
    ctl*: APNGFramecontrol
    data*: T

  PNGResult*[T] = ref object
    width*: int
    height*: int
    data*: T
    frames*: seq[APNGFrame[T]]

  DataBuf = Buffer[string]

  PNGError* = object of CatchableError

proc signatureMaker(): string {. compiletime .} =
  const signatureBytes = [137, 80, 78, 71, 13, 10, 26, 10]
  result = ""
  for c in signatureBytes: result.add chr(c)

proc makeChunkType*(val: string): PNGChunkType =
  assert(val.len == 4)
  result = PNGChunkType((ord(val[0]) shl 24) or (ord(val[1]) shl 16) or (ord(val[2]) shl 8) or ord(val[3]))

proc `$`*(tag: PNGChunkType): string =
  result = newString(4)
  let t = int(tag)
  result[0] = chr(uint32(t shr 24) and 0xFF)
  result[1] = chr(uint32(t shr 16) and 0xFF)
  result[2] = chr(uint32(t shr 8) and 0xFF)
  result[3] = chr(uint32(t) and 0xFF)

proc `==`*(a, b: PNGChunkType): bool = int(a) == int(b)
#proc isAncillary(a: PNGChunkType): bool = (int(a) and (32 shl 24)) != 0
#proc isPrivate(a: PNGChunkType): bool = (int(a) and (32 shl 16)) != 0
#proc isSafeToCopy(a: PNGChunkType): bool = (int(a) and 32) != 0

proc crc32(crc: uint32, buf: string): uint32 =
  const kcrc32 = [ 0'u32, 0x1db71064, 0x3b6e20c8, 0x26d930ac, 0x76dc4190,
    0x6b6b51f4, 0x4db26158, 0x5005713c, 0xedb88320'u32, 0xf00f9344'u32, 0xd6d6a3e8'u32,
    0xcb61b38c'u32, 0x9b64c2b0'u32, 0x86d3d2d4'u32, 0xa00ae278'u32, 0xbdbdf21c'u32]

  var crcu32 = not crc
  for b in buf:
    crcu32 = (crcu32 shr 4) xor kcrc32[int((crcu32 and 0xF) xor (uint32(b) and 0xF'u32))]
    crcu32 = (crcu32 shr 4) xor kcrc32[int((crcu32 and 0xF) xor (uint32(b) shr 4'u32))]

  result = not crcu32

template newStorage[T](size: int): T =
  when T is string:
    newString(size)
  else:
    newSeq[uint8](size)

template newStorageOfCap[T](size: int): T =
  when T is string:
    newStringOfCap(size)
  else:
    newSeqOfCap[uint8](size)

const
  PNGSignature = signatureMaker()
  IHDR = makeChunkType("IHDR")
  IEND = makeChunkType("IEND")
  PLTE = makeChunkType("PLTE")
  IDAT = makeChunkType("IDAT")
  tRNS = makeChunkType("tRNS")
  bKGD = makeChunkType("bKGD")
  pHYs = makeChunkType("pHYs")
  tIME = makeChunkType("tIME")
  iTXt = makeChunkType("iTXt")
  zTXt = makeChunkType("zTXt")
  tEXt = makeChunkType("tEXt")
  gAMA = makeChunkType("gAMA")
  cHRM = makeChunkType("cHRM")
  sRGB = makeChunkType("sRGB")
  iCCP = makeChunkType("iCCP")
  sBIT = makeChunkType("sBIT")
  sPLT = makeChunkType("sPLT")
  hIST = makeChunkType("hIST")

  # APNG chunks
  acTL = makeChunkType("acTL")
  fcTL = makeChunkType("fcTL")
  fdAT = makeChunkType("fdAT")

template PNGFatal(msg: string): untyped =
  newException(PNGError, msg)

proc newColorMode*(colorType=LCT_RGBA, bitDepth=8): PNGColorMode =
  new(result)
  result.keyDefined = false
  result.keyR = 0
  result.keyG = 0
  result.keyB = 0
  result.colorType = colorType
  result.bitDepth = bitDepth
  result.paletteSize = 0

proc copyTo*(src, dest: PNGColorMode) =
  dest.keyDefined = src.keyDefined
  dest.keyR = src.keyR
  dest.keyG = src.keyG
  dest.keyB = src.keyB
  dest.colorType = src.colorType
  dest.bitDepth = src.bitDepth
  dest.paletteSize = src.paletteSize
  newSeq(dest.palette, src.paletteSize)
  for i in 0..src.palette.len-1: dest.palette[i] = src.palette[i]

proc newColorMode*(mode: PNGColorMode): PNGColorMode =
  new(result)
  mode.copyTo(result)

proc addPalette*(mode: PNGColorMode, r, g, b, a: int) =
  mode.palette.add RGBA8(r: chr(r), g: chr(g), b: chr(b), a: chr(a))
  mode.paletteSize = mode.palette.len

proc `==`(a, b: PNGColorMode): bool =
  if a.colorType != b.colorType: return false
  if a.bitDepth != b.bitDepth: return false
  if a.keyDefined != b.keyDefined: return false
  if a.keyDefined:
    if a.keyR != b.keyR: return false
    if a.keyG != b.keyG: return false
    if a.keyB != b.keyB: return false
  if a.paletteSize != b.paletteSize: return false
  for i in 0..a.palette.len-1:
    if a.palette[i] != b.palette[i]: return false
  result = true

proc `!=`(a, b: PNGColorMode): bool = not (a == b)

proc readInt32(s: PNGChunk): int =
  if s.pos + 4 > s.data.len: raise PNGFatal("index out of bound 4")
  result = ord(s.data[s.pos]) shl 8
  result = (result + ord(s.data[s.pos + 1])) shl 8
  result = (result + ord(s.data[s.pos + 2])) shl 8
  result = result + ord(s.data[s.pos + 3])
  inc(s.pos, 4)

proc readInt16(s: PNGChunk): int =
  if s.pos + 2 > s.data.len: raise PNGFatal("index out of bound 2")
  result = ord(s.data[s.pos]) shl 8
  result = result + ord(s.data[s.pos + 1])
  inc(s.pos, 2)

when defined(js):
  {.emit: """
  var gEndianConverterFrom = new Uint32Array(1);
  var gEndianConverter = new DataView(gEndianConverterFrom.buffer);
  """.}
  proc bigEndian32(dst, src: ptr int32) =
    {.emit: """
    gEndianConverterFrom[0] = `src`[`src`_Idx];
    `dst`[`dst`_Idx] = gEndianConverter.getInt32(0);
    """.}

proc readInt32BE(s: Stream): int =
  var val = s.readInt32()
  var tmp : int32
  bigEndian32(addr(tmp), addr(val))
  result = tmp

proc readByte(s: PNGChunk): int =
  if s.pos + 1 > s.data.len: raise PNGFatal("index out of bound 1")
  result = ord(s.data[s.pos])
  inc s.pos

template readEnum(s: PNGChunk, T: type): untyped =
  let typ = readByte(s).int
  if typ < low(T).int or typ > high(T).int:
    raise PNGFatal("Wrong " & T.name & " value " & $typ)
  T(typ)

proc setPosition(s: PNGChunk, pos: int) =
  if pos < 0 or pos > s.data.len: raise PNGFatal("set position error")
  s.pos = pos

proc hasChunk*(png: PNG, chunkType: PNGChunkType): bool =
  for c in png.chunks:
    if c.chunkType == chunkType: return true
  result = false

proc apngHasChunk*(png: PNG, chunkType: PNGChunkType): bool =
  for c in png.apngChunks:
    if c.chunkType == chunkType: return true
  result = false

proc getChunk*(png: PNG, chunkType: PNGChunkType): PNGChunk =
  for c in png.chunks:
    if c.chunkType == chunkType: return c

proc apngGetChunk*(png: PNG, chunkType: PNGChunkType): PNGChunk =
  for c in png.apngChunks:
    if c.chunkType == chunkType: return c

proc bitDepthAllowed(colorType: PNGColorType, bitDepth: int): bool =
  case colorType
  of LCT_GREY   : result = bitDepth in {1, 2, 4, 8, 16}
  of LCT_PALETTE: result = bitDepth in {1, 2, 4, 8}
  else: result = bitDepth in {8, 16}

proc validateChunk(header: PNGHeader, png: PNG): bool =
  if header.width < 1 or header.width > 0x7FFFFFFF:
    raise PNGFatal("image width not allowed: " & $header.width)
  if header.height < 1 or header.height > 0x7FFFFFFF:
    raise PNGFatal("image width not allowed: " & $header.height)
  if header.colorType notin {LCT_GREY, LCT_RGB, LCT_PALETTE, LCT_GREY_ALPHA, LCT_RGBA}:
    raise PNGFatal("color type not allowed: " & $int(header.colorType))
  if not bitDepthAllowed(header.colorType, header.bitDepth):
    raise PNGFatal("bit depth not allowed: " & $header.bitDepth)
  if header.compressionMethod != 0:
    raise PNGFatal("unsupported compression method")
  if header.filterMethod != 0:
    raise PNGFatal("unsupported filter method")
  if header.interlaceMethod notin {IM_NONE, IM_INTERLACED}:
    raise PNGFatal("unsupported interlace method")
  result = true

proc parseChunk(chunk: PNGHeader, png: PNG): bool =
  if chunk.length != 13: return false
  chunk.width = chunk.readInt32()
  chunk.height = chunk.readInt32()
  chunk.bitDepth = chunk.readByte()
  chunk.colorType = chunk.readEnum(PNGColorType)
  chunk.compressionMethod = chunk.readByte()
  chunk.filterMethod = chunk.readByte()
  chunk.interlaceMethod = PNGInterlace(chunk.readByte())
  result = true

proc parseChunk(chunk: PNGPalette, png: PNG): bool =
  let paletteSize = chunk.length div 3
  if paletteSize > 256: raise PNGFatal("palette size to big")
  newSeq(chunk.palette, paletteSize)
  for px in mitems(chunk.palette):
    px.r = chr(chunk.readByte())
    px.g = chr(chunk.readByte())
    px.b = chr(chunk.readByte())
    px.a = chr(255)
  result = true

proc numChannels(colorType: PNGColorType): int =
  case colorType
  of LCT_GREY: result = 1
  of LCT_RGB : result = 3
  of LCT_PALETTE: result = 1
  of LCT_GREY_ALPHA: result = 2
  of LCT_RGBA: result = 4

proc LCTBPP(colorType: PNGColorType, bitDepth: int): int =
  # bits per pixel is amount of channels * bits per channel
  result = numChannels(colorType) * bitDepth

proc getBPP(header: PNGHeader): int =
  # calculate bits per pixel out of colorType and bitDepth
  result = LCTBPP(header.colorType, header.bitDepth)

proc getBPP(color: PNGColorMode): int =
  # calculate bits per pixel out of colorType and bitDepth
  result = LCTBPP(color.colorType, color.bitDepth)

proc idatRawSize(w, h: int, header: PNGHeader): int =
  result = h * ((w * getBPP(header) + 7) div 8)

proc getRawSize(w, h: int, color: PNGColorMode): int =
  result = (w * h * getBPP(color) + 7) div 8

#proc getRawSizeLct(w, h: int, colorType: PNGColorType, bitDepth: int): int =
#  result = (w * h * LCTBPP(colorType, bitDepth) + 7) div 8

proc validateChunk(chunk: PNGData, png: PNG): bool =
  var header = PNGHeader(png.getChunk(IHDR))

  var predict = 0
  if header.interlaceMethod == IM_NONE:
    # The extra header.height is added because this are the filter bytes every scanLine starts with
    predict = idatRawSize(header.width, header.height, header) + header.height
  else:
    # Adam-7 interlaced: predicted size is the sum of the 7 sub-images sizes
    let w = header.width
    let h = header.height
    predict += idatRawSize((w + 7) div 8, (h + 7) div 8, header) + (h + 7) div 8
    if w > 4: predict += idatRawSize((w + 3) div 8, (h + 7) div 8, header) + (h + 7) div 8
    predict += idatRawSize((w + 3) div 4, (h + 3) div 8, header) + (h + 3) div 8
    if w > 2: predict += idatRawSize((w + 1) div 4, (h + 3) div 4, header) + (h + 3) div 4
    predict += idatRawSize((w + 1) div 2, (h + 1) div 4, header) + (h + 1) div 4
    if w > 1: predict += idatRawSize((w + 0) div 2, (h + 1) div 2, header) + (h + 1) div 2
    predict += idatRawSize((w + 0) div 1, (h + 0) div 2, header) + (h + 0) div 2

  if chunk.idat.len != predict: raise PNGFatal("Decompress size doesn't match predict")
  result = true

proc parseChunk(chunk: PNGData, png: PNG): bool =
  var nz = nzInflateInit(chunk.data)
  nz.ignoreAdler32 = PNGDecoder(png.settings).ignoreAdler32
  chunk.idat = zlib_decompress(nz)
  result = true

proc parseChunk(chunk: PNGTrans, png: PNG): bool =
  var header = PNGHeader(png.getChunk(IHDR))
  if header == nil: return false

  if header.colorType == LCT_PALETTE:
    var plte = PNGPalette(png.getChunk(PLTE))
    if plte == nil: return false
    # error: more alpha values given than there are palette entries
    if chunk.length > plte.palette.len:
      raise PNGFatal("more alpha value than palette entries")
    #can contain fewer values than palette entries
    for i in 0..chunk.length-1: plte.palette[i].a = chr(chunk.readByte())
  elif header.colorType == LCT_GREY:
    # error: this chunk must be 2 bytes for greyscale image
    if chunk.length != 2: raise PNGFatal("tRNS must be 2 bytes")
    chunk.keyR = chunk.readInt16()
    chunk.keyG = chunk.keyR
    chunk.keyB = chunk.keyR
  elif header.colorType == LCT_RGB:
    # error: this chunk must be 6 bytes for RGB image
    if chunk.length != 6: raise PNGFatal("tRNS must be 6 bytes")
    chunk.keyR = chunk.readInt16()
    chunk.keyG = chunk.readInt16()
    chunk.keyB = chunk.readInt16()
  else:
    raise PNGFatal("tRNS chunk not allowed for other color models")

  result = true

proc parseChunk(chunk: PNGBackground, png: PNG): bool =
  var header = PNGHeader(png.getChunk(IHDR))
  if header.colorType == LCT_PALETTE:
    # error: this chunk must be 1 byte for indexed color image
    if chunk.length != 1: raise PNGFatal("bkgd must be 1 byte")
    chunk.bkgdR = chunk.readByte()
    chunk.bkgdG = chunk.bkgdR
    chunk.bkgdB = chunk.bkgdR
  elif header.colorType in {LCT_GREY, LCT_GREY_ALPHA}:
    # error: this chunk must be 2 bytes for greyscale image
    if chunk.length != 2: raise PNGFatal("bkgd must be 2 byte")
    chunk.bkgdR = chunk.readInt16()
    chunk.bkgdG = chunk.bkgdR
    chunk.bkgdB = chunk.bkgdR
  elif header.colorType in {LCT_RGB, LCT_RGBA}:
    # error: this chunk must be 6 bytes for greyscale image
    if chunk.length != 6: raise PNGFatal("bkgd must be 6 byte")
    chunk.bkgdR = chunk.readInt16()
    chunk.bkgdG = chunk.readInt16()
    chunk.bkgdB = chunk.readInt16()
  result = true

proc initChunk(chunk: PNGChunk, chunkType: PNGChunkType, data: string, crc: uint32) =
  chunk.length = data.len
  chunk.crc = crc
  chunk.chunkType = chunkType
  chunk.data = data
  chunk.pos = 0

proc validateChunk(chunk: PNGTime, png: PNG): bool =
  if chunk.year < 0 or chunk.year > 65535: raise PNGFatal("invalid year range[0..65535]")
  if chunk.month < 1 or chunk.month > 12: raise PNGFatal("invalid month range[1..12]")
  if chunk.day < 1 or chunk.day > 31: raise PNGFatal("invalid day range[1..32]")
  if chunk.hour < 0 or chunk.hour > 23: raise PNGFatal("invalid hour range[0..23]")
  if chunk.minute < 0 or chunk.minute > 59: raise PNGFatal("invalid minute range[0..59]")
  #to allow for leap seconds
  if chunk.second < 0 or chunk.second > 60: raise PNGFatal("invalid second range[0..60]")
  result = true

proc parseChunk(chunk: PNGTime, png: PNG): bool =
  if chunk.length != 7: raise PNGFatal("tIME must be 7 bytes")
  chunk.year   = chunk.readInt16()
  chunk.month  = chunk.readByte()
  chunk.day    = chunk.readByte()
  chunk.hour   = chunk.readByte()
  chunk.minute = chunk.readByte()
  chunk.second = chunk.readByte()
  result = true

proc parseChunk(chunk: PNGPhys, png: PNG): bool =
  if chunk.length != 9: raise PNGFatal("pHYs must be 9 bytes")
  chunk.physX = chunk.readInt32()
  chunk.physY = chunk.readInt32()
  chunk.unit  = chunk.readByte()
  result = true

proc validateChunk(chunk: PNGText, png: PNG): bool =
  if(chunk.keyword.len < 1) or (chunk.keyword.len > 79):
    raise PNGFatal("keyword too short or too long")
  result = true

proc parseChunk(chunk: PNGText, png: PNG): bool =
  var len = 0
  while(len < chunk.length) and (chunk.data[len] != chr(0)): inc len
  if(len < 1) or (len > 79): raise PNGFatal("keyword too short or too long")
  chunk.keyword = chunk.data.substr(0, len)

  var textBegin = len + 1 # skip keyword null terminator
  chunk.text = chunk.data.substr(textBegin)
  result = true

proc validateChunk(chunk: PNGZtxt, png: PNG): bool =
  if(chunk.keyword.len < 1) or (chunk.keyword.len > 79):
    raise PNGFatal("keyword too short or too long")
  result = true

proc parseChunk(chunk: PNGZtxt, png: PNG): bool =
  var len = 0
  while(len < chunk.length) and (chunk.data[len] != chr(0)): inc len
  if(len < 1) or (len > 79): raise PNGFatal("keyword too short or too long")
  chunk.keyword = chunk.data.substr(0, len)

  var compproc = ord(chunk.data[len + 1]) # skip keyword null terminator
  if compproc != 0: raise PNGFatal("unsupported comp proc")

  var nz = nzInflateInit(chunk.data.substr(len + 2))
  nz.ignoreAdler32 = PNGDecoder(png.settings).ignoreAdler32
  chunk.text = zlib_decompress(nz)

  result = true

proc validateChunk(chunk: PNGItxt, png: PNG): bool =
  if(chunk.keyword.len < 1) or (chunk.keyword.len > 79):
    raise PNGFatal("keyword too short or too long")
  result = true

proc parseChunk(chunk: PNGItxt, png: PNG): bool =
  if chunk.length < 5: raise PNGFatal("iTXt len too short")

  var len = 0
  while(len < chunk.length) and (chunk.data[len] != chr(0)): inc len

  if(len + 3) >= chunk.length: raise PNGFatal("no null termination char, corrupt?")
  if(len < 1) or (len > 79): raise PNGFatal("keyword too short or too long")
  chunk.keyword = chunk.data.substr(0, len)

  var compressed = ord(chunk.data[len + 1]) == 1 # skip keyword null terminator
  var compproc = ord(chunk.data[len + 2])
  if compproc != 0: raise PNGFatal("unsupported comp proc")

  len = 0
  var i = len + 3
  while(i < chunk.length) and (chunk.data[i] != chr(0)):
    inc len
    inc i

  chunk.languageTag = chunk.data.substr(i, i + len)

  len = 0
  i += len + 1
  while(i < chunk.length) and (chunk.data[i] != chr(0)):
    inc len
    inc i

  chunk.translatedKeyword = chunk.data.substr(i, i + len)

  let textBegin = i + len + 1
  if compressed:
    var nz = nzInflateInit(chunk.data.substr(textBegin))
    nz.ignoreAdler32 = PNGDecoder(png.settings).ignoreAdler32
    chunk.text = zlib_decompress(nz)
  else:
    chunk.text = chunk.data.substr(textBegin)
  result = true

proc parseChunk(chunk: PNGGamma, png: PNG): bool =
  if chunk.length != 4: raise PNGFatal("invalid gAMA length")
  chunk.gamma = chunk.readInt32()
  result = true

proc parseChunk(chunk: PNGChroma, png: PNG): bool =
  if chunk.length != 32: raise PNGFatal("invalid Chroma length")
  chunk.whitePointX = chunk.readInt32()
  chunk.whitePointY = chunk.readInt32()
  chunk.redX = chunk.readInt32()
  chunk.redY = chunk.readInt32()
  chunk.greenX = chunk.readInt32()
  chunk.greenY = chunk.readInt32()
  chunk.blueX = chunk.readInt32()
  chunk.blueY = chunk.readInt32()
  result = true

proc parseChunk(chunk: PNGStandarRGB, png: PNG): bool =
  if chunk.length != 1: raise PNGFatal("invalid sRGB length")
  chunk.renderingIntent = chunk.readByte()
  result = true

proc validateChunk(chunk: PNGICCProfile, png: PNG): bool =
  if(chunk.profileName.len < 1) or (chunk.profileName.len > 79):
    raise PNGFatal("keyword too short or too long")
  result = true

proc parseChunk(chunk: PNGICCProfile, png: PNG): bool =
  var len = 0
  while(len < chunk.length) and (chunk.data[len] != chr(0)): inc len
  if(len < 1) or (len > 79): raise PNGFatal("keyword too short or too long")
  chunk.profileName = chunk.data.substr(0, len)

  var compproc = ord(chunk.data[len + 1]) # skip keyword null terminator
  if compproc != 0: raise PNGFatal("unsupported comp proc")

  var nz = nzInflateInit(chunk.data.substr(len + 2))
  nz.ignoreAdler32 = PNGDecoder(png.settings).ignoreAdler32
  chunk.profile = zlib_decompress(nz)
  result = true

proc parseChunk(chunk: PNGSPalette, png: PNG): bool =
  var len = 0
  while(len < chunk.length) and (chunk.data[len] != chr(0)): inc len
  if(len < 1) or (len > 79): raise PNGFatal("keyword too short or too long")
  chunk.paletteName = chunk.data.substr(0, len)
  chunk.setPosition(len + 1)
  chunk.sampleDepth = chunk.readByte()
  if chunk.sampleDepth notin {8, 16}: raise PNGFatal("palette sample depth error")

  let remainingLength = (chunk.length - (len + 2))
  if chunk.sampleDepth == 8:
    if (remainingLength mod 6) != 0: raise PNGFatal("palette length not divisible by 6")
    let numSamples = remainingLength div 6
    newSeq(chunk.palette, numSamples)
    for p in mitems(chunk.palette):
      p.red   = chunk.readByte()
      p.green = chunk.readByte()
      p.blue  = chunk.readByte()
      p.alpha = chunk.readByte()
      p.frequency = chunk.readInt16()
  else: # chunk.sampleDepth == 16:
    if (remainingLength mod 10) != 0: raise PNGFatal("palette length not divisible by 10")
    let numSamples = remainingLength div 10
    newSeq(chunk.palette, numSamples)
    for p in mitems(chunk.palette):
      p.red   = chunk.readInt16()
      p.green = chunk.readInt16()
      p.blue  = chunk.readInt16()
      p.alpha = chunk.readInt16()
      p.frequency = chunk.readInt16()

  result = true

proc parseChunk(chunk: PNGHist, png: PNG): bool =
  if not png.hasChunk(PLTE): raise PNGFatal("Histogram need PLTE")
  var plte = PNGPalette(png.getChunk(PLTE))
  if plte.palette.len != (chunk.length div 2): raise PNGFatal("invalid histogram length")
  newSeq(chunk.histogram, plte.palette.len)
  for i in 0..chunk.histogram.high:
    chunk.histogram[i] = chunk.readInt16()
  result = true

proc parseChunk(chunk: PNGSbit, png: PNG): bool =
  let header = PNGHEader(png.getChunk(IHDR))
  var expectedLen = 0

  case header.colorType
  of LCT_GREY: expectedLen = 1
  of LCT_RGB: expectedLen = 3
  of LCT_PALETTE: expectedLen = 3
  of LCT_GREY_ALPHA: expectedLen = 2
  of LCT_RGBA: expectedLen = 4
  if chunk.length != expectedLen: raise PNGFatal("invalid sBIT length")
  var expectedDepth = 8 #LCT_PALETTE
  if header.colorType != LCT_PALETTE: expectedDepth = header.bitDepth
  for c in chunk.data:
    if (ord(c) == 0) or (ord(c) > expectedDepth): raise PNGFatal("invalid sBIT value")

  result = true

proc parseChunk(chunk: APNGAnimationControl, png: PNG): bool =
  chunk.numFrames = chunk.readInt32()
  chunk.numPlays = chunk.readInt32()
  result = true

proc parseChunk(chunk: APNGFrameControl, png: PNG): bool =
  chunk.sequenceNumber = chunk.readInt32()
  chunk.width = chunk.readInt32()
  chunk.height = chunk.readInt32()
  chunk.xOffset = chunk.readInt32()
  chunk.yOffset = chunk.readInt32()
  chunk.delayNum = chunk.readInt16()
  chunk.delayDen = chunk.readInt16()
  chunk.disposeOp = chunk.readByte().APNG_DISPOSE_OP
  chunk.blendOp = chunk.readByte().APNG_BLEND_OP
  result = true

proc validateChunk(chunk: APNGFrameControl, png: PNG): bool =
  let header = PNGHEader(png.getChunk(IHDR))
  result = true
  result = result and (chunk.xOffset >= 0)
  result = result and (chunk.yOffset >= 0)
  result = result and (chunk.width > 0)
  result = result and (chunk.height > 0)
  result = result and (chunk.xOffset + chunk.width <= header.width)
  result = result and (chunk.yOffset + chunk.height <= header.height)

proc parseChunk(chunk: APNGFrameData, png: PNG): bool =
  chunk.sequenceNumber = chunk.readInt32()
  chunk.frameDataPos = chunk.pos
  result = true

proc make[T](): T = new(result)

proc createChunk(png: PNG, chunkType: PNGChunkType, data: string, crc: uint32): PNGChunk =
  var settings = PNGDecoder(png.settings)
  result = nil

  case chunkType
  of IHDR: result = make[PNGHeader]()
  of PLTE: result = make[PNGPalette]()
  of IDAT:
    if png.apngHasChunk(fcTL): png.firstFrameIsDefaultImage = true
    if not png.hasChunk(IDAT): result = make[PNGData]()
    else:
      var idat = PNGData(png.getChunk(IDAT))
      idat.data.add data
      return idat
  of tRNS: result = make[PNGTrans]()
  of bKGD: result = make[PNGBackground]()
  of tIME: result = make[PNGTime]()
  of pHYs: result = make[PNGPhys]()
  of tEXt:
    if settings.readTextChunks: result = make[PNGTExt]()
    else:
      if settings.rememberUnknownChunks: new(result)
  of zTXt:
    if settings.readTextChunks: result = make[PNGZtxt]()
    else:
      if settings.rememberUnknownChunks: new(result)
  of iTXt:
    if settings.readTextChunks: result = make[PNGItxt]()
    else:
      if settings.rememberUnknownChunks: new(result)
  of gAMA: result = make[PNGGamma]()
  of cHRM: result = make[PNGChroma]()
  of iCCP: result = make[PNGICCProfile]()
  of sRGB: result = make[PNGStandarRGB]()
  of sPLT: result = make[PNGSPalette]()
  of hIST: result = make[PNGHist]()
  of sBIT: result = make[PNGSbit]()
  of acTL:
    # acTL chunk must precede IDAT chunk
    # to be recognized as APNG
    if not png.hasChunk(IDAT): png.isAPNG = true
    result = make[APNGAnimationControl]()
  of fcTL: result = make[APNGFrameControl]()
  of fdAT: result = make[APNGFrameData]()
  else:
    if settings.rememberUnknownChunks: new(result)

  if result != nil:
    result.initChunk(chunkType, data, crc)

proc makePNGDecoder*(): PNGDecoder =
  var s: PNGDecoder
  new(s)
  s.colorConvert = true
  s.readTextChunks = false
  s.rememberUnknownChunks = false
  s.ignoreCRC = false
  s.ignoreAdler32 = false
  result = s

proc parseChunk(chunk: PNGChunk, png: PNG): bool =
  case chunk.chunkType
  of IHDR: result = parseChunk(PNGHeader(chunk), png)
  of PLTE: result = parseChunk(PNGPalette(chunk), png)
  of IDAT: result = parseChunk(PNGData(chunk), png)
  of tRNS: result = parseChunk(PNGTrans(chunk), png)
  of bKGD: result = parseChunk(PNGBackground(chunk), png)
  of tIME: result = parseChunk(PNGTime(chunk), png)
  of pHYs: result = parseChunk(PNGPhys(chunk), png)
  of tEXt: result = parseChunk(PNGTExt(chunk), png)
  of zTXt: result = parseChunk(PNGZtxt(chunk), png)
  of iTXt: result = parseChunk(PNGItxt(chunk), png)
  of gAMA: result = parseChunk(PNGGamma(chunk), png)
  of cHRM: result = parseChunk(PNGChroma(chunk), png)
  of iCCP: result = parseChunk(PNGICCProfile(chunk), png)
  of sRGB: result = parseChunk(PNGStandarRGB(chunk), png)
  of sPLT: result = parseChunk(PNGSPalette(chunk), png)
  of hIST: result = parseChunk(PNGHist(chunk), png)
  of sBIT: result = parseChunk(PNGSbit(chunk), png)
  of acTL: result = parseChunk(APNGAnimationControl(chunk), png)
  of fcTL: result = parseChunk(APNGFrameControl(chunk), png)
  of fdAT: result = parseChunk(APNGFrameData(chunk), png)
  else: result = true

proc validateChunk(chunk: PNGChunk, png: PNG): bool =
  case chunk.chunkType
  of IHDR: result = validateChunk(PNGHeader(chunk), png)
  of IDAT: result = validateChunk(PNGData(chunk), png)
  of tIME: result = validateChunk(PNGTime(chunk), png)
  of tEXt: result = validateChunk(PNGTExt(chunk), png)
  of zTXt: result = validateChunk(PNGZtxt(chunk), png)
  of iTXt: result = validateChunk(PNGItxt(chunk), png)
  of iCCP: result = validateChunk(PNGICCProfile(chunk), png)
  of fcTL: result = validateChunk(APNGFrameControl(chunk), png)
  else: result = true

proc parsePNG[T](s: Stream, settings: PNGDecoder): PNG[T] =
  var png: PNG[T]
  new(png)
  png.chunks = @[]
  png.apngChunks =  @[]
  if settings == nil: png.settings = makePNGDecoder()
  else: png.settings = settings

  let signature = s.readStr(8)
  if signature != PNGSignature:
    raise PNGFatal("signature mismatch")

  while not s.atEnd():
    let length = s.readInt32BE()
    let chunkType = PNGChunkType(s.readInt32BE())

    let data = if length <= 0: "" else: s.readStr(length)
    let crc = cast[uint32](s.readInt32BE())
    let calculatedCRC = crc32(crc32(0, $chunkType), data)
    if calculatedCRC != crc and not PNGDecoder(png.settings).ignoreCRC:
      raise PNGFatal("wrong crc for: " & $chunkType)
    var chunk = png.createChunk(chunkType, data, crc)

    if chunkType != IDAT and chunk != nil:
      if not chunk.parseChunk(png): raise PNGFatal("error parse chunk: " & $chunkType)
      if not chunk.validateChunk(png): raise PNGFatal("invalid chunk: " & $chunkType)
    if chunk != nil:
      if chunkType == fcTL or chunkType == fdAT:
        png.apngChunks.add APNGFrameChunk(chunk)
      else: png.chunks.add chunk
    if chunkType == IEND: break

  if not png.hasChunk(IHDR): raise PNGFatal("no IHDR found")
  if not png.hasChunk(IDAT): raise PNGFatal("no IDAT found")
  var header = PNGHeader(png.getChunk(IHDR))
  if header.colorType == LCT_PALETTE and not png.hasChunk(PLTE):
    raise PNGFatal("expected PLTE not found")

  # IDAT get special treatment because it can appear in multiple chunk
  var idat = PNGData(png.getChunk(IDAT))
  if not idat.parseChunk(png): raise PNGFatal("IDAT parse error")
  if not idat.validateChunk(png): raise PNGFatal("bad IDAT")
  result = png

proc postProcessScanLines[T, A, B](png: PNG[T]; header: PNGHeader, w, h: int; input: var openArray[A],
  output: var openArray[B]) =
  # This function converts the filtered-padded-interlaced data
  # into pure 2D image buffer with the PNG's colorType.
  # Steps:
  # *) if no Adam7: 1) unfilter 2) remove padding bits (= posible extra bits per scanLine if bpp < 8)
  # *) if adam7: 1) 7x unfilter 2) 7x remove padding bits 3) Adam7_deinterlace
  # NOTE: the input buffer will be overwritten with intermediate data!

  let bpp = header.getBPP()
  let bitsPerLine = w * bpp
  let bitsPerPaddedLine = ((w * bpp + 7) div 8) * 8

  if header.interlaceMethod == IM_NONE:
    if(bpp < 8) and (bitsPerLine != bitsPerPaddedLine):
      unfilter(input, input, w, h, bpp)
      removePaddingBits(output, input, bitsPerLine, bitsPerPaddedLine, h)
    else:
      # we can immediatly filter into the out buffer, no other steps needed
      unfilter(output, input, w, h, bpp)

  else: # interlace_proc is 1 (Adam7)
    var pass: PNGPass
    adam7PassValues(pass, w, h, bpp)

    for i in 0..6:
      unfilter(input.toOpenArray(pass.paddedStart[i], input.len-1),
        input.toOpenArray(pass.filterStart[i], input.len-1),
        pass.w[i], pass.h[i], bpp
      )

      # TODO: possible efficiency improvement:
      # if in this reduced image the bits fit nicely in 1 scanLine,
      # move bytes instead of bits or move not at all
      if bpp < 8:
        # remove padding bits in scanLines; after this there still may be padding
        # bits between the different reduced images: each reduced image still starts nicely at a byte
        removePaddingBits(
          input.toOpenArray(pass.start[i], input.len-1),
          input.toOpenArray(pass.paddedStart[i], input.len-1),
          pass.w[i] * bpp, ((pass.w[i] * bpp + 7) div 8) * 8, pass.h[i]
        )

    adam7Deinterlace(output, input, w, h, bpp)

proc postProcessScanLines[T](png: PNG[T]) =
  var header = PNGHeader(png.getChunk(IHDR))
  let w = header.width
  let h = header.height
  var idat = PNGData(png.getChunk(IDAT))
  png.pixels = newStorage[T](idatRawSize(header.width, header.height, header))

  png.postProcessScanLines(header, w, h,
    idat.idat.toOpenArray(0, idat.idat.len-1), # input
    png.pixels.toOpenArray(0, png.pixels.len-1) # output
    )

proc postProcessScanLines[T](png: PNG[T], ctl: APNGFrameControl, data: var string) =
  # we use var string here to avoid realloc
  # coz we use the input as output too
  var header = PNGHeader(png.getChunk(IHDR))
  let w = ctl.width
  let h = ctl.height
  png.apngPixels.add newStorage[T](idatRawSize(ctl.width, ctl.height, header))

  png.postProcessScanLines(header, w, h,
    data.toOpenArray(0, data.len-1), # input
    png.apngPixels[^1].toOpenArray(0, png.apngPixels[^1].len-1)
  )

proc getColorMode(png: PNG): PNGColorMode =
  var header = PNGHeader(png.getChunk(IHDR))
  var cm = newColorMode(header.colorType, header.bitDepth)
  var plte = PNGPalette(png.getChunk(PLTE))
  if plte != nil:
    cm.paletteSize = plte.palette.len
    newSeq(cm.palette, cm.paletteSize)
    for i in 0..cm.paletteSize-1: cm.palette[i] = plte.palette[i]
  var trans = PNGTrans(png.getChunk(tRNS))
  if trans != nil:
    if cm.colorType in {LCT_GREY, LCT_RGB}:
      cm.keyDefined = true
      cm.keyR = trans.keyR
      cm.keyG = trans.keyG
      cm.keyB = trans.keyB
  result = cm

proc getInfo*(png: PNG): PNGInfo =
  result = new(PNGInfo)
  result.mode = png.getColorMode()
  var header = PNGHeader(png.getChunk(IHDR))
  result.width = header.width
  result.height = header.height
  var bkgd = PNGBackground(png.getChunk(bKGD))
  if bkgd == nil: result.backgroundDefined = false
  else:
    result.backgroundDefined = true
    result.backgroundR = bkgd.bkgdR
    result.backgroundG = bkgd.bkgdG
    result.backgroundB = bkgd.bkgdB

  var phys = PNGPhys(png.getChunk(pHYs))
  if phys == nil: result.physDefined = false
  else:
    result.physDefined = true
    result.physX = phys.physX
    result.physY = phys.physY
    result.physUnit = phys.unit

  var time = PNGTime(png.getChunk(tIME))
  if time == nil: result.timeDefined = false
  else:
    result.timeDefined = true
    result.year = time.year
    result.month = time.month
    result.day = time.day
    result.hour = time.hour
    result.minute = time.minute
    result.second = time.second

proc getChunkNames*(png: PNG): string =
  result = ""
  var i = 0
  for c in png.chunks:
    result.add($c.chunkType)
    if i < png.chunks.high: result.add ' '
    inc i

proc RGBFromGrey8[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 3
    output[x]   = input[i]
    output[x+1] = input[i]
    output[x+2] = input[i]

proc RGBFromGrey16[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 3
    let y = i * 2
    output[x]   = input[y]
    output[x+1] = input[y]
    output[x+2] = input[y]

proc RGBFromGrey124[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  var highest = ((1 shl mode.bitDepth) - 1) # highest possible value for this bit depth
  var obp = 0
  for i in 0..<numPixels:
    let val = T((readBitsFromReversedStream(obp, input, mode.bitDepth) * 255) div highest)
    let x = i * 3
    output[x]   = val
    output[x+1] = val
    output[x+2] = val

proc RGBFromRGB8[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 3
    output[x]   = input[x]
    output[x+1] = input[x+1]
    output[x+2] = input[x+2]

proc RGBFromRGB16[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 3
    let y = i * 6
    output[x]   = T(input[y])
    output[x+1] = T(input[y+2])
    output[x+2] = T(input[y+4])

proc RGBFromPalette8[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 3
    let index = ord(input[i])
    if index >= mode.paletteSize:
      # This is an error according to the PNG spec, but most PNG decoders make it black instead.
      # Done here too, slightly faster due to no error handling needed.
      output[x]   = T(0)
      output[x+1] = T(0)
      output[x+2] = T(0)
    else:
      output[x]   = T(mode.palette[index].r)
      output[x+1] = T(mode.palette[index].g)
      output[x+2] = T(mode.palette[index].b)

proc RGBFromPalette124[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  var obp = 0
  for i in 0..<numPixels:
    let x = i * 3
    let index = readBitsFromReversedStream(obp, input, mode.bitDepth)
    if index >= mode.paletteSize:
      # This is an error according to the PNG spec, but most PNG decoders make it black instead.
      # Done here too, slightly faster due to no error handling needed.
      output[x]   = T(0)
      output[x+1] = T(0)
      output[x+2] = T(0)
    else:
      output[x]   = T(mode.palette[index].r)
      output[x+1] = T(mode.palette[index].g)
      output[x+2] = T(mode.palette[index].b)

proc RGBFromGreyAlpha8[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 3
    let val = input[i * 2]
    output[x] = val
    output[x+1] = val
    output[x+2] = val

proc RGBFromGreyAlpha16[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 3
    let val = input[i * 4]
    output[x] = val
    output[x+1] = val
    output[x+2] = val

proc RGBFromRGBA8[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 3
    let y = i * 4
    output[x]   = input[y]
    output[x+1] = input[y+1]
    output[x+2] = input[y+2]

proc RGBFromRGBA16[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 3
    let y = i * 8
    output[x]   = input[y]
    output[x+1] = input[y+2]
    output[x+2] = input[y+4]

proc RGBAFromGrey8[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 4
    output[x]   = input[i]
    output[x+1] = input[i]
    output[x+2] = input[i]
    if mode.keyDefined and (ord(input[i]) == mode.keyR): output[x+3] = T(0)
    else: output[x+3] = T(255)

proc RGBAFromGrey16[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 4
    let y = i * 2
    output[x]   = input[y]
    output[x+1] = input[y]
    output[x+2] = input[y]
    let keyR = 256 * ord(input[y + 0]) + ord(input[y + 1])
    if mode.keyDefined and (keyR == mode.keyR): output[x+3] = T(0)
    else: output[x+3] = T(255)

proc RGBAFromGrey124[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  var highest = ((1 shl mode.bitDepth) - 1) #highest possible value for this bit depth
  var obp = 0
  for i in 0..<numPixels:
    let val = readBitsFromReversedStream(obp, input, mode.bitDepth)
    let value = T((val * 255) div highest)
    let x = i * 4
    output[x]   = T(value)
    output[x+1] = T(value)
    output[x+2] = T(value)
    if mode.keyDefined and (ord(val) == mode.keyR): output[x+3] = T(0)
    else: output[x+3] = T(255)

proc RGBAFromRGB8[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 4
    let y = i * 3
    output[x]   = input[y]
    output[x+1] = input[y+1]
    output[x+2] = input[y+2]
    if mode.keyDefined and (mode.keyR == ord(input[y])) and
      (mode.keyG == ord(input[y+1])) and (mode.keyB == ord(input[y+2])): output[x+3] = T(0)
    else: output[x+3] = T(255)

proc RGBAFromRGB16[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 4
    let y = i * 6
    output[x]   = input[y]
    output[x+1] = input[y+2]
    output[x+2] = input[y+4]
    let keyR = 256 * ord(input[y]) + ord(input[y+1])
    let keyG = 256 * ord(input[y+2]) + ord(input[y+3])
    let keyB = 256 * ord(input[y+4]) + ord(input[y+5])
    if mode.keyDefined and (mode.keyR == keyR) and
      (mode.keyG == keyG) and (mode.keyB == keyB): output[x+3] = T(0)
    else: output[x+3] = T(255)

proc RGBAFromPalette8[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 4
    let index = ord(input[i])
    if index >= mode.paletteSize:
      # This is an error according to the PNG spec, but most PNG decoders make it black instead.
      # Done here too, slightly faster due to no error handling needed.
      output[x]   = T(0)
      output[x+1] = T(0)
      output[x+2] = T(0)
      output[x+3] = T(0)
    else:
      output[x]   = T(mode.palette[index].r)
      output[x+1] = T(mode.palette[index].g)
      output[x+2] = T(mode.palette[index].b)
      output[x+3] = T(mode.palette[index].a)

proc RGBAFromPalette124[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  var obp = 0
  for i in 0..<numPixels:
    let x = i * 4
    let index = readBitsFromReversedStream(obp, input, mode.bitDepth)
    if index >= mode.paletteSize:
      # This is an error according to the PNG spec, but most PNG decoders make it black instead.
      # Done here too, slightly faster due to no error handling needed.
      output[x]   = T(0)
      output[x+1] = T(0)
      output[x+2] = T(0)
      output[x+3] = T(0)
    else:
      output[x]   = T(mode.palette[index].r)
      output[x+1] = T(mode.palette[index].g)
      output[x+2] = T(mode.palette[index].b)
      output[x+3] = T(mode.palette[index].a)

proc RGBAFromGreyAlpha8[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 4
    let val = input[i * 2]
    output[x] = val
    output[x+1] = val
    output[x+2] = val
    output[x+3] = input[i * 2 + 1]

proc RGBAFromGreyAlpha16[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 4
    let val = input[i * 4]
    output[x] = val
    output[x+1] = val
    output[x+2] = val
    output[x+3] = input[i * 4 + 2]

proc RGBAFromRGBA8[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 4
    let y = i * 4
    output[x]   = input[y]
    output[x+1] = input[y+1]
    output[x+2] = input[y+2]
    output[x+3] = input[y+3]

proc RGBAFromRGBA16[T](output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode) =
  for i in 0..<numPixels:
    let x = i * 4
    let y = i * 8
    output[x]   = input[y]
    output[x+1] = input[y+2]
    output[x+2] = input[y+4]
    output[x+3] = input[y+6]

type
  convertRGBA[T]    = proc(output: var openArray[T], input: openArray[T], numPixels: int, mode: PNGColorMode)
  convertRGBA8[T]   = proc(p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode)
  convertRGBA16[T]  = proc(p: var RGBA16, input: openArray[T], px: int, mode: PNGColorMode)
  pixelRGBA8[T]     = proc(p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8)
  pixelRGBA16[T]    = proc(p: RGBA16, output: var openArray[T], px: int, mode: PNGColorMode)

proc hash*(c: RGBA8): Hash =
  var h: Hash = 0
  h = h !& ord(c.r)
  h = h !& ord(c.g)
  h = h !& ord(c.b)
  h = h !& ord(c.a)
  result = !$(h)

proc RGBA8FromGrey8[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  p.r = char(input[px])
  p.g = char(input[px])
  p.b = char(input[px])
  if mode.keyDefined and (ord(p.r) == mode.keyR): p.a = char(0)
  else: p.a = char(255)

proc RGBA8FromGrey16[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 2
  let keyR = 256 * ord(input[i]) + ord(input[i + 1])
  p.r = char(input[i])
  p.g = char(input[i])
  p.b = char(input[i])
  if mode.keyDefined and (keyR == mode.keyR): p.a = char(0)
  else: p.a = char(255)

proc RGBA8FromGrey124[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  let highest = ((1 shl mode.bitDepth) - 1) #highest possible value for this bit depth
  var obp = px * mode.bitDepth
  let val = readBitsFromReversedStream(obp, input, mode.bitDepth)
  let value = char((val * 255) div highest)
  p.r = value
  p.g = value
  p.b = value
  if mode.keyDefined and (ord(val) == mode.keyR): p.a = char(0)
  else: p.a = char(255)

proc RGBA8FromRGB8[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  let y = px * 3
  p.r = char(input[y])
  p.g = char(input[y+1])
  p.b = char(input[y+2])
  if mode.keyDefined and (mode.keyR == ord(input[y])) and
    (mode.keyG == ord(input[y+1])) and (mode.keyB == ord(input[y+2])): p.a = char(0)
  else: p.a = char(255)

proc RGBA8FromRGB16[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  let y = px * 6
  p.r = char(input[y])
  p.g = char(input[y+2])
  p.b = char(input[y+4])
  let keyR = 256 * ord(input[y]) + ord(input[y+1])
  let keyG = 256 * ord(input[y+2]) + ord(input[y+3])
  let keyB = 256 * ord(input[y+4]) + ord(input[y+5])
  if mode.keyDefined and (mode.keyR == keyR) and
    (mode.keyG == keyG) and (mode.keyB == keyB): p.a = char(0)
  else: p.a = char(255)

proc RGBA8FromPalette8[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  let index = ord(input[px])
  if index >= mode.paletteSize:
    # This is an error according to the PNG spec,
    # but common PNG decoders make it black instead.
    # Done here too, slightly faster due to no error handling needed.
    p.r = char(0)
    p.g = char(0)
    p.b = char(0)
    p.a = char(255)
  else:
    p.r = mode.palette[index].r
    p.g = mode.palette[index].g
    p.b = mode.palette[index].b
    p.a = mode.palette[index].a

proc RGBA8FromPalette124[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  var obp = px * mode.bitDepth
  let index = readBitsFromReversedStream(obp, input, mode.bitDepth)
  if index >= mode.paletteSize:
    # This is an error according to the PNG spec,
    # but common PNG decoders make it black instead.
    # Done here too, slightly faster due to no error handling needed.
    p.r = char(0)
    p.g = char(0)
    p.b = char(0)
    p.a = char(255)
  else:
    p.r = mode.palette[index].r
    p.g = mode.palette[index].g
    p.b = mode.palette[index].b
    p.a = mode.palette[index].a

proc RGBA8FromGreyAlpha8[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 2
  let val = char(input[i])
  p.r = val
  p.g = val
  p.b = val
  p.a = char(input[i+1])

proc RGBA8FromGreyAlpha16[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 4
  let val = char(input[i])
  p.r = val
  p.g = val
  p.b = val
  p.a = char(input[i+2])

proc RGBA8FromRGBA8[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 4
  p.r = char(input[i])
  p.g = char(input[i+1])
  p.b = char(input[i+2])
  p.a = char(input[i+3])

proc RGBA8FromRGBA16[T](p: var RGBA8, input: openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 8
  p.r = chaR(input[i])
  p.g = chaR(input[i+2])
  p.b = chaR(input[i+4])
  p.a = chaR(input[i+6])

proc RGBA16FromGrey[T](p: var RGBA16, input: openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 2
  let val = 256'u16 * uint16(input[i]) + uint16(input[i + 1])
  p.r = val
  p.g = val
  p.b = val
  if mode.keyDefined and (val.int == mode.keyR): p.a = 0
  else: p.a = 65535

proc RGBA16FromRGB[T](p: var RGBA16, input: openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 6
  p.r = 256'u16 * uint16(input[i]) + uint16(input[i+1])
  p.g = 256'u16 * uint16(input[i+2]) + uint16(input[i+3])
  p.b = 256'u16 * uint16(input[i+4]) + uint16(input[i+5])
  if mode.keyDefined and (int(p.r) == mode.keyR) and
    (int(p.g) == mode.keyG) and (int(p.b) == mode.keyB): p.a = 0
  else: p.a = 65535

proc RGBA16FromGreyAlpha[T](p: var RGBA16, input: openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 4
  let val = 256'u16 * uint16(input[i]) + uint16(input[i + 1])
  p.r = val
  p.g = val
  p.b = val
  p.a = 256'u16 * uint16(input[i + 2]) + uint16(input[i + 3])

proc RGBA16FromRGBA[T](p: var RGBA16, input: openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 8
  p.r = 256'u16 * uint16(input[i]) + uint16(input[i+1])
  p.g = 256'u16 * uint16(input[i+2]) + uint16(input[i+3])
  p.b = 256'u16 * uint16(input[i+4]) + uint16(input[i+5])
  p.a = 256'u16 * uint16(input[i+6]) + uint16(input[i+7])

proc RGBA8ToGrey8[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  output[px] = T(p.r)

proc RGBA8ToGrey16[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  let i = px * 2
  output[i] = T(p.r)
  output[i+1] = T(p.r)

proc RGBA8ToGrey124[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  # take the most significant bits of grey
  let grey = (int(p.r) shr (8 - mode.bitDepth)) and ((1 shl mode.bitDepth) - 1)
  addColorBits(output, px, mode.bitDepth, grey)

proc RGBA8ToRGB8[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  let i = px * 3
  output[i]   = T(p.r)
  output[i+1] = T(p.g)
  output[i+2] = T(p.b)

proc RGBA8ToRGB16[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  let i = px * 6
  output[i]   = T(p.r)
  output[i+2] = T(p.g)
  output[i+4] = T(p.b)
  output[i+1] = T(p.r)
  output[i+3] = T(p.g)
  output[i+5] = T(p.b)

proc RGBA8ToPalette8[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  output[px] = T(ct[p])

proc RGBA8ToPalette124[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  addColorBits(output, px, mode.bitDepth, ct[p])

proc RGBA8ToGreyAlpha8[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  let i = px * 2
  output[i]   = T(p.r)
  output[i+1] = T(p.a)

proc RGBA8ToGreyAlpha16[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  let i = px * 4
  output[i]   = T(p.r)
  output[i+1] = T(p.r)
  output[i+2] = T(p.a)
  output[i+3] = T(p.a)

proc RGBA8ToRGBA8[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  let i = px * 4
  output[i]   = T(p.r)
  output[i+1] = T(p.g)
  output[i+2] = T(p.b)
  output[i+3] = T(p.a)

proc RGBA8ToRGBA16[T](p: RGBA8, output: var openArray[T], px: int, mode: PNGColorMode, ct: ColorTree8) =
  let i = px * 8
  output[i]   = T(p.r)
  output[i+2] = T(p.g)
  output[i+4] = T(p.b)
  output[i+6] = T(p.a)
  output[i+1] = T(p.r)
  output[i+3] = T(p.g)
  output[i+5] = T(p.b)
  output[i+7] = T(p.a)

proc RGBA16ToGrey[T](p: RGBA16, output: var openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 2
  output[i]   = T((p.r shr 8) and 255)
  output[i+1] = T(p.r and 255)

proc RGBA16ToRGB[T](p: RGBA16, output: var openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 6
  output[i]   = T((p.r shr 8) and 255)
  output[i+1] = T(p.r and 255)
  output[i+2] = T((p.g shr 8) and 255)
  output[i+3] = T(p.g and 255)
  output[i+4] = T((p.b shr 8) and 255)
  output[i+5] = T(p.b and 255)

proc RGBA16ToGreyAlpha[T](p: RGBA16, output: var openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 4
  output[i]   = T((p.r shr 8) and 255)
  output[i+1] = T(p.r and 255)
  output[i+2] = T((p.a shr 8) and 255)
  output[i+3] = T(p.a and 255)

proc RGBA16ToRGBA[T](p: RGBA16, output: var openArray[T], px: int, mode: PNGColorMode) =
  let i = px * 8
  output[i]   = T((p.r shr 8) and 255)
  output[i+1] = T(p.r and 255)
  output[i+2] = T((p.g shr 8) and 255)
  output[i+3] = T(p.g and 255)
  output[i+4] = T((p.b shr 8) and 255)
  output[i+5] = T(p.b and 255)
  output[i+6] = T((p.a shr 8) and 255)
  output[i+7] = T(p.a and 255)

proc getColorRGBA16[T](mode: PNGColorMode): convertRGBA16[T] =
  if mode.colorType == LCT_GREY: return RGBA16FromGrey[T]
  elif mode.colorType == LCT_RGB: return RGBA16FromRGB[T]
  elif mode.colorType == LCT_GREY_ALPHA: return RGBA16FromGreyAlpha[T]
  elif mode.colorType == LCT_RGBA: return RGBA16FromRGBA[T]
  else: raise PNGFatal("unsupported converter16")

proc getPixelRGBA16[T](mode: PNGColorMode): pixelRGBA16[T] =
  if mode.colorType == LCT_GREY: return RGBA16ToGrey[T]
  elif mode.colorType == LCT_RGB: return RGBA16ToRGB[T]
  elif mode.colorType == LCT_GREY_ALPHA: return RGBA16ToGreyAlpha[T]
  elif mode.colorType == LCT_RGBA: return RGBA16ToRGBA[T]
  else: raise PNGFatal("unsupported pixel16 converter")

proc getColorRGBA8[T](mode: PNGColorMode): convertRGBA8[T] =
  if mode.colorType == LCT_GREY:
    if mode.bitDepth == 8: return RGBA8FromGrey8[T]
    elif mode.bitDepth == 16: return RGBA8FromGrey16[T]
    else: return RGBA8FromGrey124[T]
  elif mode.colorType == LCT_RGB:
    if mode.bitDepth == 8: return RGBA8FromRGB8[T]
    else: return RGBA8FromRGB16[T]
  elif mode.colorType == LCT_PALETTE:
    if mode.bitDepth == 8: return RGBA8FromPalette8[T]
    else: return RGBA8FromPalette124[T]
  elif mode.colorType == LCT_GREY_ALPHA:
    if mode.bitDepth == 8: return RGBA8FromGreyAlpha8[T]
    else: return RGBA8FromGreyAlpha16[T]
  elif mode.colorType == LCT_RGBA:
    if mode.bitDepth == 8: return RGBA8FromRGBA8[T]
    else: return RGBA8FromRGBA16[T]
  else: raise PNGFatal("unsupported converter8")

proc getPixelRGBA8[T](mode: PNGColorMode): pixelRGBA8[T] =
  if mode.colorType == LCT_GREY:
    if mode.bitDepth == 8: return RGBA8ToGrey8[T]
    elif mode.bitDepth == 16: return RGBA8ToGrey16[T]
    else: return RGBA8ToGrey124[T]
  elif mode.colorType == LCT_RGB:
    if mode.bitDepth == 8: return RGBA8ToRGB8[T]
    else: return RGBA8ToRGB16[T]
  elif mode.colorType == LCT_PALETTE:
    if mode.bitDepth == 8: return RGBA8ToPalette8[T]
    else: return RGBA8ToPalette124[T]
  elif mode.colorType == LCT_GREY_ALPHA:
    if mode.bitDepth == 8: return RGBA8ToGreyAlpha8[T]
    else: return RGBA8ToGreyAlpha16[T]
  elif mode.colorType == LCT_RGBA:
    if mode.bitDepth == 8: return RGBA8ToRGBA8[T]
    else: return RGBA8ToRGBA16[T]
  else: raise PNGFatal("unsupported pixel8 converter")

proc getConverterRGB[T](mode: PNGColorMode): convertRGBA[T] =
  if mode.colorType == LCT_GREY:
    if mode.bitDepth == 8: return RGBFromGrey8[T]
    elif mode.bitDepth == 16: return RGBFromGrey16[T]
    else: return RGBFromGrey124[T]
  elif mode.colorType == LCT_RGB:
    if mode.bitDepth == 8: return RGBFromRGB8[T]
    else: return RGBFromRGB16[T]
  elif mode.colorType == LCT_PALETTE:
    if mode.bitDepth == 8: return RGBFromPalette8[T]
    else: return RGBFromPalette124[T]
  elif mode.colorType == LCT_GREY_ALPHA:
    if mode.bitDepth == 8: return RGBFromGreyAlpha8[T]
    else: return RGBFromGreyAlpha16[T]
  elif mode.colorType == LCT_RGBA:
    if mode.bitDepth == 8: return RGBFromRGBA8[T]
    else: return RGBFromRGBA16[T]
  else: raise PNGFatal("unsupported RGB converter")

proc getConverterRGBA[T](mode: PNGColorMode): convertRGBA[T] =
  if mode.colorType == LCT_GREY:
    if mode.bitDepth == 8: return RGBAFromGrey8[T]
    elif mode.bitDepth == 16: return RGBAFromGrey16[T]
    else: return RGBAFromGrey124[T]
  elif mode.colorType == LCT_RGB:
    if mode.bitDepth == 8: return RGBAFromRGB8[T]
    else: return RGBAFromRGB16[T]
  elif mode.colorType == LCT_PALETTE:
    if mode.bitDepth == 8: return RGBAFromPalette8[T]
    else: return RGBAFromPalette124[T]
  elif mode.colorType == LCT_GREY_ALPHA:
    if mode.bitDepth == 8: return RGBAFromGreyAlpha8[T]
    else: return RGBAFromGreyAlpha16[T]
  elif mode.colorType == LCT_RGBA:
    if mode.bitDepth == 8: return RGBAFromRGBA8[T]
    else: return RGBAFromRGBA16[T]
  else: raise PNGFatal("unsupported RGBA converter")

proc convertImpl*[T](output: var openArray[T], input: openArray[T], modeOut, modeIn: PNGColorMode, numPixels: int) =
  var tree: ColorTree8
  if modeOut.colorType == LCT_PALETTE:
    var
      paletteSize = modeOut.paletteSize
      palette:  type(modeOut.palette)
      palSize = 1 shl modeOut.bitDepth

    shallowCopy(palette, modeOut.palette)
    # if the user specified output palette but did not give the values, assume
    # they want the values of the input color type (assuming that one is palette).
    # Note that we never create a new palette ourselves.
    if paletteSize == 0:
      paletteSize = modeIn.paletteSize
      shallowCopy(palette, modeIn.palette)

    if paletteSize < palSize: palSize = paletteSize
    tree = initTable[RGBA8, int](nextPowerOfTwo(paletteSize))
    for i in 0..palSize-1:
      tree[palette[i]] = i

  if(modeIn.bitDepth == 16) and (modeOut.bitDepth == 16):
    let cvt = getColorRGBA16[T](modeIn)
    let pxl = getPixelRGBA16[T](modeOut)
    for px in 0..<numPixels:
      var p = RGBA16(r:0, g:0, b:0, a:0)
      cvt(p, input, px, modeIn)
      pxl(p, output, px, modeOut)
  elif(modeOut.bitDepth == 8) and (modeOut.colorType == LCT_RGBA):
    let cvt = getConverterRGBA[T](modeIn)
    cvt(output, input, numPixels, modeIn)
  elif(modeOut.bitDepth == 8) and (modeOut.colorType == LCT_RGB):
    let cvt = getConverterRGB[T](modeIn)
    cvt(output, input, numPixels, modeIn)
  else:
    let cvt = getColorRGBA8[T](modeIn)
    let pxl = getPixelRGBA8[T](modeOut)
    for px in 0..<numPixels:
      var p = RGBA8(r:char(0), g:char(0), b:char(0), a:char(0))
      cvt(p, input, px, modeIn)
      pxl(p, output, px, modeOut, tree)

proc convert*[T](png: PNG[T], colorType: PNGColorType, bitDepth: int): PNGResult[T] =
  # TODO: check if this works according to the statement in the documentation: "The converter can convert
  # from greyscale input color type, to 8-bit greyscale or greyscale with alpha"
  # if(colorType notin {LCT_RGB, LCT_RGBA}) and (bitDepth != 8):
  #   raise PNGFatal("unsupported color mode conversion")

  let header = PNGHeader(png.getChunk(IHDR))
  let modeIn = png.getColorMode()
  let modeOut = newColorMode(colorType, bitDepth)
  let size = getRawSize(header.width, header.height, modeOut)
  let numPixels = header.width * header.height

  new(result)
  result.width  = header.width
  result.height = header.height
  result.data   = newStorage[T](size)

  if modeOut == modeIn:
    result.data = png.pixels
    return

  convertImpl(result.data.toOpenArray(0, result.data.len-1),
    png.pixels.toOpenArray(0, png.pixels.len-1),
    modeOut, modeIn, numPixels)

proc convert*[T](png: PNG[T], colorType: PNGColorType, bitDepth: int, ctl: APNGFrameControl, data: T): APNGFrame[T] =
  let modeIn = png.getColorMode()
  let modeOut = newColorMode(colorType, bitDepth)
  let size = getRawSize(ctl.width, ctl.height, modeOut)
  let numPixels = ctl.width * ctl.height

  new(result)
  result.ctl  = ctl
  result.data = newStorage[T](size)

  if modeOut == modeIn:
    result.data = data
    return result

  convertImpl(result.data.toOpenArray(0, result.data.len-1),
    data.toOpenArray(0, data.len-1),
    modeOut, modeIn, numPixels)

proc toStorage[T](chunk: APNGFrameData): T =
  let fdatLen = chunk.data.len - chunk.frameDataPos
  let fdatAddr = chunk.data[chunk.frameDataPos].addr
  result = newStorage[T](fdatLen)
  copyMem(result[0].addr, fdatAddr, fdatLen)

type
  APNG[T] = ref object
    png: PNG[T]
    result: PNGResult[T]

proc processingAPNG[T](apng: APNG[T], colorType: PNGColorType, bitDepth: int) =
  let header = PNGHeader(apng.png.getChunk(IHDR))
  var
    actl = APNGAnimationControl(apng.png.getChunk(acTL))
    frameControl = newSeqOfCap[APNGFrameControl](actl.numFrames)
    frameData = newSeqOfCap[T](actl.numFrames)
    numFrames = 0
    lastChunkType = PNGChunkType(0)
    start = 0

  if apng.png.firstFrameIsDefaultImage:
    start = 1
    # IDAT already processed, so we add a dummy here
    when T is string:
      frameData.add ""
    else:
      frameData.add @[]

  for x in apng.png.apngChunks:
    if x.chunkType == fcTL:
      frameControl.add APNGFrameControl(x)
      inc numFrames
      lastChunkType = fcTL
    else:
      let y = APNGFrameData(x)
      if lastChunkType == fdAT:
        frameData[^1].add toStorage[T](y)
      else:
        frameData.add toStorage[T](y)
      lastChunkType = fdAT

  if actl.numFrames == 0 or actl.numFrames != numFrames or actl.numFrames != frameData.len:
    raise PNGFatal("animation numFrames error")

  apng.png.apngPixels = newSeqOfCap[T](numFrames)

  if apng.result != nil:
    apng.result.frames = newSeqOfCap[APNGFrame[T]](numFrames)

  if apng.png.firstFrameIsDefaultImage:
    let ctl = frameControl[0]
    if ctl.width != header.width or ctl.height != header.height:
      raise PNGFatal("animation control error: dimension")
    if ctl.xOffset != 0 or ctl.xOffset != 0:
      raise PNGFatal("animation control error: offset")

    if apng.result != nil:
      var frame = new(APNGFrame[T])
      frame.ctl = ctl
      frame.data = apng.result.data
      apng.result.frames.add frame

  for i in start..<numFrames:
    let ctl = frameControl[i]
    when T is string:
      var nz = nzInflateInit(frameData[i])
    else:
      var nz = nzInflateInit(cast[string](frameData[i]))
    nz.ignoreAdler32 = PNGDecoder(apng.png.settings).ignoreAdler32
    var idat = zlib_decompress(nz)
    apng.png.postProcessScanLines(ctl, idat)

    if apng.result != nil:
      if PNGDecoder(apng.png.settings).colorConvert:
        apng.result.frames.add convert[T](apng.png, colorType, bitDepth, ctl, apng.png.apngPixels[^1])
      else:
        var frame = new(APNGFrame[T])
        frame.ctl = ctl
        frame.data = apng.png.apngPixels[^1]
        apng.result.frames.add frame

proc decodePNG*(T: type, s: Stream, colorType: PNGColorType, bitDepth: int, settings = PNGDecoder(nil)): PNGResult[T] =
  if not bitDepthAllowed(colorType, bitDepth):
    raise PNGFatal("colorType and bitDepth combination not allowed")

  var png = parsePNG[T](s, settings)
  png.postProcessScanLines()

  if PNGDecoder(png.settings).colorConvert:
    result = convert[T](png, colorType, bitDepth)
  else:
    new(result)
    let header = PNGHeader(png.getChunk(IHDR))
    result.width  = header.width
    result.height = header.height
    result.data   = png.pixels

  if png.isAPNG:
    var apng = APNG[T](png: png, result: result)
    apng.processingAPNG(colorType, bitDepth)

proc decodePNG*(T: type, s: Stream, settings = PNGDecoder(nil)): PNG[T] =
  var png = parsePNG[T](s, settings)
  png.postProcessScanLines()

  if png.isAPNG:
    var apng = APNG[T](png: png, result: nil)
    apng.processingAPNG(PNGColorType(0), 0)

  result = png

type
  PNGRes*[T] = Result[PNGResult[T], string]

when not defined(js):
  proc loadPNG*(T: type, fileName: string, colorType: PNGColorType, bitDepth: int, settings: PNGDecoder = nil): PNGRes[T] =
    try:
      var s = newFileStream(fileName, fmRead)
      if s == nil:
        result.err("cannot open input stream")
        return
      result.ok(decodePNG(T, s, colorType, bitDepth, settings))
      s.close()
    except PNGError, IOError, NZError:
      result.err(getCurrentExceptionMsg())

  proc loadPNG32*(T: type, fileName: string, settings = PNGDecoder(nil)): PNGRes[T] =
    loadPNG(T, fileName, LCT_RGBA, 8, settings)

  proc loadPNG24*(T: type, fileName: string, settings = PNGDecoder(nil)): PNGRes[T] =
    loadPNG(T, fileName, LCT_RGB, 8, settings)

proc decodePNG32Impl*[T](input: T, settings = PNGDecoder(nil)): PNGRes[T] =
  try:
    when T is string:
      var s = newStringStream(input)
    else:
      var s = newStringStream(cast[string](input))
    if s == nil:
      result.err("cannot open input stream")
      return
    result.ok(decodePNG(T, s, LCT_RGBA, 8, settings))
  except PNGError, IOError, NZError:
    result.err(getCurrentExceptionMsg())

proc decodePNG24Impl*[T](input: T, settings = PNGDecoder(nil)): PNGRes[T] =
  try:
    when T is string:
      var s = newStringStream(input)
    else:
      var s = newStringStream(cast[string](input))
    if s == nil:
      result.err("cannot open input stream")
      return
    result.ok(decodePNG(T, s, LCT_RGB, 8, settings))
  except PNGError, IOError, NZError:
    result.err(getCurrentExceptionMsg())

# these are legacy API
proc decodePNG*(s: Stream, colorType: PNGColorType, bitDepth: int, settings = PNGDecoder(nil)): PNGResult[string] =
  decodePNG(string, s, colorType, bitDepth, settings)

proc decodePNG*(s: Stream, settings = PNGDecoder(nil)): PNG[string] =
  decodePNG(string, s, settings)

when not defined(js):
  proc loadPNG*(fileName: string, colorType: PNGColorType, bitDepth: int, settings: PNGDecoder = nil): PNGResult[string] =
    let res = loadPNG(string, fileName, colorType, bitDepth, settings)
    if res.isOk: result = res.get()
    else: debugEcho res.error()

  proc loadPNG32*(fileName: string, settings = PNGDecoder(nil)): PNGResult[string] =
    let res = loadPNG32(string, fileName, settings)
    if res.isOk: result = res.get()
    else: debugEcho res.error()

  proc loadPNG24*(fileName: string, settings = PNGDecoder(nil)): PNGResult[string] =
    let res = loadPNG24(string, fileName, settings)
    if res.isOk: result = res.get()
    else: debugEcho res.error()

proc decodePNG32Legacy*(input: string, settings = PNGDecoder(nil)): PNGResult[string] =
  let res = decodePNG32Impl(input, settings)
  if res.isOk: result = res.get()
  else: debugEcho res.error()

proc decodePNG24Legacy*(input: string, settings = PNGDecoder(nil)): PNGResult[string] =
  let res = decodePNG24Impl(input, settings)
  if res.isOk: result = res.get()
  else: debugEcho res.error()

template decodePNG32*[T](input: T, settings = PNGDecoder(nil)): untyped =
  when T is string:
    decodePNG32Legacy(input, settings)
  elif T is openArray:
    decodePNG32Impl(@(input), settings)
  else:
    decodePNG32Impl(input, settings)

template decodePNG24*[T](input: T, settings = PNGDecoder(nil)): untyped =
  when T is string:
    decodePNG24Legacy(input, settings)
  elif T is openArray:
    decodePNG24Impl(@(input), settings)
  else:
    decodePNG24Impl(input, settings)

#Encoder/Decoder demarcation line-----------------------------

type
  PNGFilterStrategy* = enum
    #every filter at zero
    LFS_ZERO,
    #Use filter that gives minimum sum, as described in the official PNG filter heuristic.
    LFS_MINSUM,
    #Use the filter type that gives smallest Shannon entropy for this scanLine. Depending
    #on the image, this is better or worse than minsum.
    LFS_ENTROPY,
    #Brute-force-search PNG filters by compressing each filter for each scanLine.
    #Experimental, very slow, and only rarely gives better compression than MINSUM.
    LFS_BRUTE_FORCE,
    #use predefined_filters buffer: you specify the filter type for each scanLine
    LFS_PREDEFINED

  PNGKeyText = object
    keyword, text: string

  PNGIText = object
    keyword: string
    text: string
    languageTag: string
    translatedKeyword: string

  PNGUnknown = ref object of PNGChunk
  PNGEnd = ref object of PNGChunk

  PNGEncoder* = ref object of PNGSettings
    #automatically choose output PNG color type. Default: true
    autoConvert*: bool
    modeIn*: PNGColorMode
    modeOut*: PNGColorMode

    #If true, follows the official PNG heuristic: if the PNG uses a palette or lower than
    #8 bit depth, set all filters to zero. Otherwise use the filter_strategy. Note that to
    #completely follow the official PNG heuristic, filter_palette_zero must be true and
    #filter_strategy must be LFS_MINSUM
    filterPaletteZero*: bool

    #Which filter strategy to use when not using zeroes due to filter_palette_zero.
    #Set filter_palette_zero to 0 to ensure always using your chosen strategy. Default: LFS_MINSUM
    filterStrategy*: PNGFilterStrategy

    #used if filter_strategy is LFS_PREDEFINED. In that case, this must point to a buffer with
    #the same length as the amount of scanLines in the image, and each value must <= 5.
    #Don't forget that filter_palette_zero must be set to false to ensure this is also used on palette or low bitdepth images.
    predefinedFilters*: seq[PNGFilter]

    #force creating a PLTE chunk if colorType is 2 or 6 (= a suggested palette).
    #If colorType is 3, PLTE is _always_ created.
    forcePalette*: bool

    #add nimPNG identifier and version as a text chunk, for debugging
    addID*: bool
    #encode text chunks as zTXt chunks instead of tEXt chunks, and use compression in iTXt chunks
    textCompression*: bool
    textList*: seq[PNGKeyText]
    itextList*: seq[PNGIText]

    interlaceMethod*: PNGInterlace

    backgroundDefined*: bool
    backgroundR*, backgroundG*, backgroundB*: int

    physDefined*: bool
    physX*, physY*, physUnit*: int

    timeDefined*: bool
    year*: int   #range[0..65535]
    month*: int  #range[1..12]
    day*: int    #range[1..31]
    hour*: int   #range[0..23]
    minute*: int #range[0..59]
    second*: int #range[0..60] #to allow for leap seconds

    unknown*: seq[PNGUnknown]

    # APNG number of plays, 0 = infinite
    numPlays*: int

  PNGColorProfile = ref object
    colored: bool #not greyscale
    key: bool #if true, image is not opaque. Only if true and alpha is false, color key is possible.
    keyR, keyG, keyB: int #these values are always in 16-bit bitdepth in the profile
    alpha: bool #alpha channel or alpha palette required
    numColors: int #amount of colors, up to 257. Not valid if bits == 16.
    palette: seq[RGBA8] #Remembers up to the first 256 RGBA colors, in no particular order
    bits: int #bits per channel (not for palette). 1,2 or 4 for greyscale only. 16 if 16-bit per channel required.

proc makePNGEncoder*(): PNGEncoder =
  var s: PNGEncoder
  s = new(PNGEncoder)
  s.filterPaletteZero = true
  s.filterStrategy = LFS_MINSUM
  s.autoConvert = true
  s.modeIn = newColorMode()
  s.modeOut = newColorMode()
  s.forcePalette = false
  s.predefinedFilters = @[]
  s.addID = false
  s.textCompression = true
  s.interlaceMethod = IM_NONE
  s.backgroundDefined = false
  s.backgroundR = 0
  s.backgroundG = 0
  s.backgroundB = 0
  s.physDefined = false
  s.physX = 0
  s.physY = 0
  s.physUnit = 0
  s.timeDefined = false
  s.textList = @[]
  s.itextList = @[]
  s.unknown = @[]
  s.numPlays = 0
  result = s

proc addText*(state: PNGEncoder, keyword, text: string) =
  state.textList.add PNGKeyText(keyword: keyword, text: text)

proc addIText*(state: PNGEncoder, keyword, langtag, transkey, text: string) =
  var itext: PNGIText
  itext.keyword = keyword
  itext.text = text
  itext.languageTag = langtag
  itext.translatedKeyword = transkey
  state.itextList.add itext

proc make[T](chunkType: PNGChunkType, estimateSize: int): T =
  result = new(T)
  result.chunkType = chunkType
  if estimateSize > 0: result.data = newStringOfCap(estimateSize)
  else: result.data = ""

proc addUnknownChunk*(state: PNGEncoder, chunkType, data: string) =
  assert chunkType.len == 4
  var chunk = make[PNGUnknown](makeChunkType(chunkType), 0)
  chunk.data = data
  state.unknown.add chunk

proc makeColorProfile(): PNGColorProfile =
  new(result)
  result.colored = false
  result.key = false
  result.alpha = false
  result.keyR = 0
  result.keyG = 0
  result.keyB = 0
  result.numcolors = 0
  result.bits = 1
  result.palette = @[]

proc writeByte(s: PNGChunk, val: int) = s.data.add chr(val)
proc writeString(s: PNGChunk, val: string) = s.data.add val

proc writeInt32(s: PNGChunk, val: int) =
  s.writeByte((val shr 24) and 0xff)
  s.writeByte((val shr 16) and 0xff)
  s.writeByte((val shr 8) and 0xff)
  s.writeByte(val and 0xff)

proc writeInt16(s: PNGChunk, val: int) =
  s.writeByte((val shr 8) and 0xff)
  s.writeByte(val and 0xff)

proc writeInt32BE(s: Stream, value: int) =
  var val = cast[int32](value)
  var tmp: int32
  bigEndian32(addr(tmp), addr(val))
  s.write(tmp)

proc writeChunk(chunk: PNGHeader, png: PNG): bool =
  #estimate 13 bytes
  chunk.writeInt32(chunk.width)
  chunk.writeInt32(chunk.height)
  chunk.writeByte(chunk.bitDepth)
  chunk.writeByte(int(chunk.colorType))
  chunk.writeByte(chunk.compressionMethod)
  chunk.writeByte(chunk.filterMethod)
  chunk.writeByte(int(chunk.interlaceMethod))
  result = true

proc writeChunk(chunk: PNGPalette, png: PNG): bool =
  #estimate 3 * palette.len
  for px in chunk.palette:
    chunk.writeByte(int(px.r))
    chunk.writeByte(int(px.g))
    chunk.writeByte(int(px.b))
  result = true

proc writeChunk(chunk: PNGTrans, png: PNG): bool =
  var header = PNGHeader(png.getChunk(IHDR))

  if header.colorType == LCT_PALETTE:
    #estimate plte.palette.len
    var plte = PNGPalette(png.getChunk(PLTE))
    #the tail of palette values that all have 255 as alpha, does not have to be encoded
    var amount = plte.palette.len
    for i in countdown(amount-1, 0):
      if plte.palette[i].a == chr(255): dec amount
      else: break
    for i in 0..amount-1: chunk.writeByte(int(plte.palette[i].a))
  elif header.colorType == LCT_GREY:
    #estimate 2 bytes
    if chunk.keyR != -1: chunk.writeInt16(chunk.keyR)
  elif header.colorType == LCT_RGB:
    #estimate 6 bytes
    if chunk.keyR != -1:
      chunk.writeInt16(chunk.keyR)
      chunk.writeInt16(chunk.keyG)
      chunk.writeInt16(chunk.keyB)
  else:
    raise PNGFatal("tRNS chunk not allowed for other color models")
  result = true

proc writeChunk(chunk: PNGBackground, png: PNG): bool =
  var header = PNGHeader(png.getChunk(IHDR))
  if header.colorType == LCT_PALETTE:
    #estimate 1 bytes
    chunk.writeByte(chunk.bkgdR)
  if header.colorType in {LCT_GREY, LCT_GREY_ALPHA}:
    #estimate 2 bytes
    chunk.writeInt16(chunk.bkgdR)
  elif header.colorType in {LCT_RGB, LCT_RGBA}:
    #estimate 6 bytes
    chunk.writeInt16(chunk.bkgdR)
    chunk.writeInt16(chunk.bkgdG)
    chunk.writeInt16(chunk.bkgdB)
  result = true

proc writeChunk(chunk: PNGTime, png: PNG): bool =
  #estimate 7 bytes
  chunk.writeInt16(chunk.year)
  chunk.writeByte(chunk.month)
  chunk.writeByte(chunk.day)
  chunk.writeByte(chunk.hour)
  chunk.writeByte(chunk.minute)
  chunk.writeByte(chunk.second)
  result = true

proc writeChunk(chunk: PNGPhys, png: PNG): bool =
  #estimate 9 bytes
  chunk.writeInt32(chunk.physX)
  chunk.writeInt32(chunk.physY)
  chunk.writeByte(chunk.unit)
  result = true

proc writeChunk(chunk: PNGText, png: PNG): bool =
  #estimate chunk.keyword.len + chunk.text.len + 1
  chunk.writeString chunk.keyword
  chunk.writeByte 0 #null separator
  chunk.writeString chunk.text
  result = true

proc writeChunk(chunk: PNGGamma, png: PNG): bool =
  #estimate 4 bytes
  chunk.writeInt32(chunk.gamma)
  result = true

proc writeChunk(chunk: PNGChroma, png: PNG): bool =
  #estimate 8 * 4 bytes
  chunk.writeInt32(chunk.whitePointX)
  chunk.writeInt32(chunk.whitePointY)
  chunk.writeInt32(chunk.redX)
  chunk.writeInt32(chunk.redY)
  chunk.writeInt32(chunk.greenX)
  chunk.writeInt32(chunk.greenY)
  chunk.writeInt32(chunk.blueX)
  chunk.writeInt32(chunk.blueY)
  result = true

proc writeChunk(chunk: PNGStandarRGB, png: PNG): bool =
  #estimate 1 byte
  chunk.writeByte(chunk.renderingIntent)
  result = true

proc writeChunk(chunk: PNGSPalette, png: PNG): bool =
  #estimate chunk.paletteName.len + 2
  #if sampleDepth == 8: estimate += chunk.palette.len * 6
  #else: estimate += chunk.palette.len * 10
  chunk.writeString chunk.paletteName
  chunk.writeByte 0 #null separator
  if chunk.sampleDepth notin {8, 16}: raise PNGFatal("palette sample depth error")
  chunk.writeByte chunk.sampleDepth

  if chunk.sampleDepth == 8:
    for p in chunk.palette:
      chunk.writeByte(p.red)
      chunk.writeByte(p.green)
      chunk.writeByte(p.blue)
      chunk.writeByte(p.alpha)
      chunk.writeInt16(p.frequency)
  else: # chunk.sampleDepth == 16:
    for p in chunk.palette:
      chunk.writeInt16(p.red)
      chunk.writeInt16(p.green)
      chunk.writeInt16(p.blue)
      chunk.writeInt16(p.alpha)
      chunk.writeInt16(p.frequency)
  result = true

proc writeChunk(chunk: PNGHist, png: PNG): bool =
  #estimate chunk.histogram.len * 2
  for c in chunk.histogram:
    chunk.writeInt16 c
  result = true

proc writeChunk(chunk: PNGData, png: PNG): bool =
  var nz = nzDeflateInit(chunk.idat)
  chunk.data = zlib_compress(nz)
  result = true

proc writeChunk(chunk: PNGZtxt, png: PNG): bool =
  #estimate chunk.keyword.len + 2
  chunk.writeString chunk.keyword
  chunk.writeByte 0 #null separator
  chunk.writeByte 0 #compression proc(0: deflate)
  var nz = nzDeflateInit(chunk.text)
  chunk.writeString zlib_compress(nz)
  result = true

proc writeChunk(chunk: PNGItxt, png: PNG): bool =
  #estimate chunk.keyword.len + 2
  # + chunk.languageTag.len + chunk.translatedKeyword.len
  let state = PNGEncoder(png.settings)
  var compressed: int
  var text: string
  if state.textCompression:
    var nz = nzDeflateInit(chunk.text)
    var zz = zlib_compress(nz)
    if zz.len >= chunk.text.len:
      compressed = 0
      text = chunk.text
    else:
      compressed = 1
      text = zz
  else:
    compressed = 0
    text = chunk.text

  chunk.writeString chunk.keyword
  chunk.writeByte 0 #null separator
  chunk.writeByte compressed #compression flag(0: uncompressed, 1: compressed)
  chunk.writeByte 0 #compression proc(0: deflate)
  chunk.writeString chunk.languageTag
  chunk.writeByte 0 #null separator
  chunk.writeString chunk.translatedKeyword
  chunk.writeByte 0 #null separator
  chunk.writeString text
  result = true

proc writeChunk(chunk: PNGICCProfile, png: PNG): bool =
  #estimate chunk.profileName.len + 2
  chunk.writeString chunk.profileName
  chunk.writeByte 0 #null separator
  chunk.writeByte 0 #compression proc(0: deflate)
  var nz = nzDeflateInit(chunk.profile)
  chunk.writeString zlib_compress(nz)
  result = true

proc writeChunk(chunk: APNGAnimationControl, png: PNG): bool =
  # estimate 8 bytes
  chunk.writeInt32(chunk.numFrames)
  chunk.writeInt32(chunk.numPlays)
  result = true

proc writeChunk(chunk: APNGFrameControl, png: PNG): bool =
  # estimate 5*4 + 2*2 + 2 = 26 bytes
  chunk.writeInt32(chunk.sequenceNumber)
  chunk.writeInt32(chunk.width)
  chunk.writeInt32(chunk.height)
  chunk.writeInt32(chunk.xOffset)
  chunk.writeInt32(chunk.yOffset)
  chunk.writeInt16(chunk.delayNum)
  chunk.writeInt16(chunk.delayDen)
  chunk.writeByte(ord(chunk.disposeOp))
  chunk.writeByte(ord(chunk.blendOp))
  result = true

proc writeChunk(chunk: APNGFrameData, png: PNG): bool =
  chunk.writeInt32(chunk.sequenceNumber)
  var nz = nzDeflateInit(cast[string](png.apngPixels[chunk.frameDataPos]))
  chunk.writeString zlib_compress(nz)
  result = true

proc writeChunk(chunk: PNGChunk, png: PNG): bool =
  case chunk.chunkType
  of IHDR: result = writeChunk(PNGHeader(chunk), png)
  of PLTE: result = writeChunk(PNGPalette(chunk), png)
  of IDAT: result = writeChunk(PNGData(chunk), png)
  of tRNS: result = writeChunk(PNGTrans(chunk), png)
  of bKGD: result = writeChunk(PNGBackground(chunk), png)
  of tIME: result = writeChunk(PNGTime(chunk), png)
  of pHYs: result = writeChunk(PNGPhys(chunk), png)
  of tEXt: result = writeChunk(PNGTExt(chunk), png)
  of zTXt: result = writeChunk(PNGZtxt(chunk), png)
  of iTXt: result = writeChunk(PNGItxt(chunk), png)
  of gAMA: result = writeChunk(PNGGamma(chunk), png)
  of cHRM: result = writeChunk(PNGChroma(chunk), png)
  of iCCP: result = writeChunk(PNGICCProfile(chunk), png)
  of sRGB: result = writeChunk(PNGStandarRGB(chunk), png)
  of sPLT: result = writeChunk(PNGSPalette(chunk), png)
  of hIST: result = writeChunk(PNGHist(chunk), png)
  of sBIT: result = writeChunk(PNGSbit(chunk), png)
  of acTL: result = writeChunk(APNGAnimationControl(chunk), png)
  of fcTL: result = writeChunk(APNGFrameControl(chunk), png)
  of fdAT: result = writeChunk(APNGFrameData(chunk), png)
  else: result = true

proc isGreyscaleType(mode: PNGColorMode): bool =
  result = mode.colorType in {LCT_GREY, LCT_GREY_ALPHA}

proc isAlphaType(mode: PNGColorMode): bool =
  result = mode.colorType in {LCT_RGBA, LCT_GREY_ALPHA}

proc hasPaletteAlpha(mode: PNGColorMode): bool =
  for p in mode.palette:
    if ord(p.a) < 255: return true
  result = false

proc canHaveAlpha(mode: PNGColorMode): bool =
  result = mode.keyDefined or isAlphaType(mode) or hasPaletteAlpha(mode)

#Returns how many bits needed to represent given value (max 8 bit)*/
proc getValueRequiredBits(value: int): int =
  if(value == 0) or (value == 255): return 1
  #The scaling of 2-bit and 4-bit values uses multiples of 85 and 17
  if(value mod 17) == 0:
    if (value mod 85) == 0: return 2
    else: return 4
  result = 8

proc differ(p: RGBA16): bool =
  # first and second byte differ
  if (p.r and 255) != ((p.r shr 8) and 255): return true
  if (p.g and 255) != ((p.g shr 8) and 255): return true
  if (p.b and 255) != ((p.b shr 8) and 255): return true
  if (p.a and 255) != ((p.a shr 8) and 255): return true
  result = false

proc calculateColorProfile[T](input: openArray[T], w, h: int, mode: PNGColorMode, prof: PNGColorProfile, tree: var Table[RGBA8, int]) =
  let
    numPixels = w * h
    bpp = getBPP(mode)

  var
    coloredDone = isGreyscaleType(mode)
    alphaDone   = not canHaveAlpha(mode)
    bitsDone = bpp == 1
    numColorsDone = false
    sixteen = false
    maxNumColors = 257

  if bpp <= 8:
    case bpp
    of 1: maxNumColors = 2
    of 2: maxNumColors = 4
    of 4: maxNumColors = 16
    else: maxNumColors = 256

  #Check if the 16-bit input is truly 16-bit
  if mode.bitDepth == 16:
    let cvt = getColorRGBA16[T](mode)
    var p = RGBA16(r:0, g:0, b:0, a:0)
    for px in 0..<numPixels:
      cvt(p, input.toOpenArray(0, input.len-1), px, mode)
      if p.differ():
        sixteen = true
        break

  if sixteen:
    let cvt = getColorRGBA16[T](mode)
    var p = RGBA16(r:0, g:0, b:0, a:0)
    prof.bits = 16
    #counting colors no longer useful, palette doesn't support 16-bit
    bitsDone = true
    numColorsDone = true

    for px in 0..<numPixels:
      cvt(p, input.toOpenArray(0, input.len-1), px, mode)
      if not coloredDone and ((p.r != p.g) or (p.r != p.b)):
        prof.colored = true
        coloredDone = true

      if not alphaDone:
        let matchKey = (int(p.r) == prof.keyR and
          int(p.g) == prof.keyG and int(p.b) == prof.keyB)

        if(p.a != 65535) and (p.a != 0 or (prof.key and not matchKey)):
          prof.alpha = true
          alphaDone = true
          if prof.bits < 8: prof.bits = 8 #PNG has no alphachannel modes with less than 8-bit per channel
        elif(p.a == 0) and not prof.alpha and not prof.key:
          prof.key = true
          prof.keyR = int(p.r)
          prof.keyG = int(p.g)
          prof.keyB = int(p.b)
        elif(p.a == 65535) and prof.key and matchKey:
          # Color key cannot be used if an opaque pixel also has that RGB color.
          prof.alpha = true
          alphaDone = true

      if alphaDone and numColorsDone and coloredDone and bitsDone: break
  else: # < 16-bit
    let cvt = getColorRGBA8[T](mode)
    for px in 0..<numPixels:
      var p = RGBA8(r:chr(0), g:chr(0), b:chr(0), a:chr(0))
      cvt(p, input.toOpenArray(0, input.len-1), px, mode)
      if (not bitsDone) and (prof.bits < 8):
        #only r is checked, < 8 bits is only relevant for greyscale
        let bits = getValueRequiredBits(int(p.r))
        if bits > prof.bits: prof.bits = bits
      bitsDone = prof.bits >= bpp

      if (not coloredDone) and ((p.r != p.g) or (p.r != p.b)):
        prof.colored = true
        coloredDone = true
        if prof.bits < 8: prof.bits = 8 #PNG has no colored modes with less than 8-bit per channel

      if not alphaDone:
        let matchKey = ((int(p.r) == prof.keyR) and
          (int(p.g) == prof.keyG) and (int(p.b) == prof.keyB))

        if(p.a != chr(255)) and (p.a != chr(0) or (prof.key and (not matchKey))):
          prof.alpha = true
          alphaDone = true
          if prof.bits < 8: prof.bits = 8 #PNG has no alphachannel modes with less than 8-bit per channel
        elif(p.a == chr(0)) and not prof.alpha and not prof.key:
          prof.key = true
          prof.keyR = int(p.r)
          prof.keyG = int(p.g)
          prof.keyB = int(p.b)
        elif(p.a == chr(255)) and prof.key and matchKey:
          #Color key cannot be used if an opaque pixel also has that RGB color.
          prof.alpha = true
          alphaDone = true
          if prof.bits < 8: prof.bits = 8 #PNG has no alphachannel modes with less than 8-bit per channel

      if not numColorsDone:
        if not tree.hasKey(p):
          tree[p] = prof.numColors
          if prof.numColors < 256: prof.palette.add p
          inc prof.numColors
          numColorsDone = prof.numColors >= maxNumColors
      if alphaDone and numColorsDone and coloredDone and bitsDone: break

    # make the profile's key always 16-bit for consistency - repeat each byte twice
    prof.keyR += prof.keyR shl 8
    prof.keyG += prof.keyG shl 8
    prof.keyB += prof.keyB shl 8

proc getColorProfile(png: PNG, mode: PNGColorMode): PNGColorProfile =
  var
    prof = makeColorProfile()
    tree = initTable[RGBA8, int]()

  calculateColorProfile(png.pixels.toOpenArray(0, png.pixels.len-1), png.width, png.height, mode, prof, tree)

  if png.isAPNG:
    for i in 1..<png.apngChunks.len:
      var ctl = APNGFrameControl(png.apngChunks[i])
      let len = png.apngPixels[i].len
      calculateColorProfile(png.apngPixels[i].toOpenArray(0, len-1), ctl.width, ctl.height, mode, prof, tree)

  result = prof

# Automatically chooses color type that gives smallest amount of bits in the
# output image, e.g. grey if there are only greyscale pixels, palette if there
# are less than 256 colors, ...
# Updates values of mode with a potentially smaller color model. mode_out should
# contain the user chosen color model, but will be overwritten with the new chosen one.
proc autoChooseColor(png: PNG, modeOut, modeIn: PNGColorMode) =
  var prof = png.getColorProfile(modeIn)
  modeOut.keyDefined = false

  let w = png.width
  let h = png.height
  if prof.key and ((w * h) <= 16):
    prof.alpha = true # too few pixels to justify tRNS chunk overhead
    if prof.bits < 8: prof.bits = 8 # PNG has no alphachannel modes with less than 8-bit per channel

  # grey without alpha, with potentially low bits
  let greyOk = not prof.colored and  not prof.alpha
  let n = prof.numColors

  var paletteBits = 0
  if n <= 2: paletteBits = 1
  elif n <= 4: paletteBits = 2
  elif n <= 16: paletteBits = 4
  else: paletteBits = 8
  var paletteOk = (n <= 256) and ((n * 2) < (w * h)) and prof.bits <= 8
  # don't add palette overhead if image has only a few pixels
  if (w * h) < (n * 2): paletteOk = false
  # grey is less overhead
  if greyOk and (prof.bits <= palettebits): paletteOk = false

  if paletteOk:
    modeOut.paletteSize = prof.palette.len
    modeOut.palette   = prof.palette
    modeOut.colorType = LCT_PALETTE
    modeOut.bitDepth  = paletteBits

    if(modeIn.colorType == LCT_PALETTE) and (modeIn.palettesize >= modeOut.palettesize) and
      (modeIn.bitdepth == modeOut.bitdepth):
      # If input should have same palette colors, keep original to preserve its order and prevent conversion
      modeIn.copyTo(modeOut)
  else: # 8-bit or 16-bit per channel
    modeOut.bitDepth = prof.bits
    if prof.alpha:
      if prof.colored: modeOut.colorType = LCT_RGBA
      else: modeOut.colorType = LCT_GREY_ALPHA
    else:
      if prof.colored: modeOut.colorType = LCT_RGB
      else: modeOut.colorType = LCT_GREY

    if prof.key and not prof.alpha:
      # profile always uses 16-bit, mask converts it
      let mask = (1 shl modeOut.bitDepth) - 1
      modeOut.keyR = prof.keyR and mask
      modeOut.keyG = prof.keyG and mask
      modeOut.keyB = prof.keyB and mask
      modeOut.keyDefined = true

proc filter[T](output: var openArray[T], input: openArray[T], w, h: int, modeOut: PNGColorMode, state: PNGEncoder) =
  # For PNG filter proc 0
  # out must be a buffer with as size: h + (w * h * bpp + 7) / 8, because there are
  # the scanlines with 1 extra byte per scanline

  let bpp = getBPP(modeOut)
  var strategy = state.filterStrategy

  # There is a heuristic called the minimum sum of absolute differences heuristic, suggested by the PNG standard:
  # *  If the image type is Palette, or the bit depth is smaller than 8, then do not filter the image (i.e.
  #    use fixed filtering, with the filter None).
  # * (The other case) If the image type is Grayscale or RGB (with or without Alpha), and the bit depth is
  #   not smaller than 8, then use adaptive filtering heuristic as follows: independently for each row, apply
  #   all five filters and select the filter that produces the smallest sum of absolute values per row.
  # This heuristic is used if filter strategy is LFS_MINSUM and filter_palette_zero is true.

  # If filter_palette_zero is true and filter_strategy is not LFS_MINSUM, the above heuristic is followed,
  # but for "the other case", whatever strategy filter_strategy is set to instead of the minimum sum
  # heuristic is used.
  if state.filterPaletteZero and
    (modeOut.colorType == LCT_PALETTE or modeOut.bitDepth < 8): strategy = LFS_ZERO

  if bpp == 0:
    raise PNGFatal("invalid color type")

  case strategy
  of LFS_ZERO: filterZero(output, input, w, h, bpp)
  of LFS_MINSUM: filterMinsum(output, input, w, h, bpp)
  of LFS_ENTROPY: filterEntropy(output, input, w, h, bpp)
  of LFS_BRUTE_FORCE: filterBruteForce(output, input, w, h, bpp)
  of LFS_PREDEFINED: filterPredefined(output, input, w, h, bpp, state.predefinedFilters)

proc preProcessScanLines[T, B](png: PNG[T], input: openArray[B], frameNo, w, h: int, modeOut: PNGColorMode, state: PNGEncoder) =
  # This function converts the pure 2D image with the PNG's colorType, into filtered-padded-interlaced data. Steps:
  #  if no Adam7: 1) add padding bits (= posible extra bits per scanLine if bpp < 8) 2) filter
  #  if adam7: 1) Adam7_interlace 2) 7x add padding bits 3) 7x filter
  let bpp = getBPP(modeOut)

  if state.interlaceMethod == IM_NONE:
    # image size plus an extra byte per scanLine + possible padding bits
    let scanLen = (w * bpp + 7) div 8
    let outSize = h + (h * scanLen)
    var output = newStorage[T](outSize)

    # non multiple of 8 bits per scanLine, padding bits needed per scanLine
    if(bpp < 8) and ((w * bpp) != (scanLen * 8)):
      var padded = newStorage[T](h * scanLen)
      addPaddingBits(padded.toOpenArray(0, padded.len-1), input, scanLen * 8, w * bpp, h)

      filter(output.toOpenArray(0, output.len-1),
        padded.toOpenArray(0, padded.len-1),
        w, h, modeOut, state)
    else:
      # we can immediatly filter into the out buffer, no other steps needed
      filter(output.toOpenArray(0, output.len-1),
        input, w, h, modeOut, state)

    shallowCopy(png.apngPixels[frameNo], output)

  else: #interlaceMethod is 1 (Adam7)
    var pass: PNGPass
    adam7PassValues(pass, w, h, bpp)
    let outSize = pass.filterStart[7]

    var output = newStorage[T](outSize)
    var adam7 = newStorage[T](pass.start[7])

    adam7Interlace(adam7.toOpenArray(0, adam7.len-1),
      input, w, h, bpp)
    for i in 0..6:
      if bpp < 8:
        var padding = newStorage[T](pass.paddedStart[i + 1] - pass.paddedStart[i])

        addPaddingBits(padding.toOpenArray(0, padding.len-1),
          adam7.toOpenArray(pass.start[i], adam7.len-1),
          ((pass.w[i] * bpp + 7) div 8) * 8, pass.w[i] * bpp, pass.h[i])

        filter(output.toOpenArray(pass.filterStart[i], output.len-1),
          padding.toOpenArray(0, padding.len-1),
          pass.w[i], pass.h[i], modeOut, state)
      else:
        filter(output.toOpenArray(pass.filterStart[i], output.len-1),
          adam7.toOpenArray(pass.paddedStart[i], adam7.len-1),
          pass.w[i], pass.h[i], modeOut, state)

    shallowCopy(png.apngPixels[frameNo], output)

#palette must have 4 * palettesize bytes allocated, and given in format RGBARGBARGBARGBA...
#returns 0 if the palette is opaque,
#returns 1 if the palette has a single color with alpha 0 ==> color key
#returns 2 if the palette is semi-translucent.
proc getPaletteTranslucency(modeOut: PNGColorMode): int =
  var key = 0
  #the value of the color with alpha 0, so long as color keying is possible
  var p: RGBA8
  var i = 0
  while i < modeOut.paletteSize:
    let x = modeOut.palette[i]
    if (key == 0) and (x.a == chr(0)):
      p = x
      key = 1
      i = -1 #restart from beginning, to detect earlier opaque colors with key's value
    elif x.a != chr(255): return 2
    #when key, no opaque RGB may have key's RGB*/
    elif(key != 0) and (p.r == x.r) and (p.g == x.g) and (p.b == x.g): return 2
    inc i

  result = key

proc addChunkIHDR(png: PNG, w,h: int, modeOut: PNGColorMode, state: PNGEncoder) =
  var chunk = make[PNGHeader](IHDR, 13)
  chunk.width = w
  chunk.height = h
  chunk.bitDepth = modeOut.bitDepth
  chunk.colorType = modeOut.colorType
  chunk.compressionMethod = 0
  chunk.filterMethod = 0
  chunk.interlaceMethod = state.interlaceMethod
  png.chunks.add chunk

proc addChunkPLTE(png: PNG, modeOut: PNGColorMode) =
  if modeOut.paletteSize == 0: return
  var chunk = make[PNGPalette](PLTE, 3 * modeOut.paletteSize)
  chunk.palette = modeOut.palette
  png.chunks.add chunk

proc addChunktRNS(png: PNG, modeOut: PNGColorMode) =
  var chunk = make[PNGTrans](tRNS, 2)

  if modeOut.colorType == LCT_PALETTE:
    var plte = png.getChunk(PLTE)
    doAssert plte != nil
  elif modeOut.colorType == LCT_GREY:
    if modeOut.keyDefined:
      chunk.keyR = modeOut.keyR
    else:
      chunk.keyR = -1
  elif modeOut.colorType == LCT_RGB:
    if modeOut.keyDefined:
      chunk.keyR = modeOut.keyR
      chunk.keyG = modeOut.keyG
      chunk.keyB = modeOut.keyB
    else:
      chunk.keyR = -1
  png.chunks.add chunk

proc addChunkbKGD(png: PNG, modeOut: PNGColorMode, state: PNGEncoder) =
  var chunk = make[PNGBackground](bKGD, 6)
  if modeOut.colorType == LCT_PALETTE:
    #estimate 1 bytes
    chunk.bkgdR = state.backgroundR
  if modeOut.colorType in {LCT_GREY, LCT_GREY_ALPHA}:
    #estimate 2 bytes
    chunk.bkgdR = state.backgroundR
  elif modeOut.colorType in {LCT_RGB, LCT_RGBA}:
    #estimate 6 bytes
    chunk.bkgdR = state.backgroundR
    chunk.bkgdG = state.backgroundG
    chunk.bkgdB = state.backgroundB
  png.chunks.add chunk

proc addChunkpHYs(png: PNG, state: PNGEncoder) =
  var chunk = make[PNGPhys](pHYs, 9)
  chunk.physX = state.physX
  chunk.physY = state.physY
  chunk.unit  = state.physUnit
  png.chunks.add chunk

proc addChunkIDAT(png: PNG, state: PNGEncoder) =
  var chunk = make[PNGData](IDAT, 0)
  chunk.idat = cast[string](png.pixels)
  png.chunks.add chunk

proc addChunktIME(png: PNG, state: PNGEncoder) =
  var chunk = make[PNGTime](tIME, 0)
  chunk.year   = state.year
  chunk.month  = state.month
  chunk.day    = state.day
  chunk.hour   = state.hour
  chunk.minute = state.minute
  chunk.second = state.second
  png.chunks.add chunk

proc addChunktEXt(png: PNG, txt: PNGKeyText) =
  var chunk = make[PNGText](tEXt, txt.keyword.len + txt.text.len + 1)
  chunk.keyword = txt.keyword
  chunk.text = txt.text
  png.chunks.add chunk

proc addChunkzTXt(png: PNG, txt: PNGKeyText) =
  var chunk = make[PNGZtxt](zTXt, txt.keyword.len + txt.text.len + 1)
  chunk.keyword = txt.keyword
  chunk.text = txt.text
  png.chunks.add chunk

proc addChunkiTXt(png: PNG, txt: PNGIText) =
  var chunk = make[PNGItxt](iTXt, txt.keyword.len + txt.text.len + 1)
  chunk.keyword = txt.keyword
  chunk.translatedKeyword = txt.translatedKeyword
  chunk.languageTag = txt.languageTag
  chunk.text = txt.text
  png.chunks.add chunk

proc addChunkIEND(png: PNG) =
  var chunk = make[PNGEnd](IEND, 0)
  png.chunks.add chunk

proc addChunkacTL(png: PNG, numFrames, numPlays: int) =
  var chunk = make[APNGAnimationControl](acTL, 8)
  chunk.numFrames = numFrames
  chunk.numPlays = numPlays
  png.chunks.add chunk

proc addChunkfcTL[T](png: PNG[T], chunk: APNGFrameControl, sequenceNumber: int) =
  chunk.chunkType = fcTL
  if chunk.data == "":
    chunk.data = newStringOfCap(26)
  chunk.sequenceNumber = sequenceNumber
  png.chunks.add chunk

proc addChunkfdAT(png: PNG, sequenceNumber, frameDataPos: int) =
  var chunk = make[APNGFrameData](fdAT, 0)
  chunk.sequenceNumber = sequenceNumber
  chunk.frameDataPos = frameDataPos
  png.chunks.add chunk

proc frameConvert[T](png: PNG[T], modeIn, modeOut: PNGColorMode, w, h, frameNo: int, state: PNGEncoder) =
  template input: untyped = png.apngPixels[frameNo]

  if modeIn != modeOut:
    let size = (w * h * getBPP(modeOut) + 7) div 8
    let numPixels = w * h

    var converted = newStorage[T](size)
    # although in preProcessScanLines png.pixels is reinitialized, it is ok
    # because initBuffer(png.pixels) share the ownership
    convertImpl(converted.toOpenArray(0, converted.len-1),
      input.toOpenArray(0, input.len-1),
      modeOut, modeIn, numPixels)

    preProcessScanLines(png, converted.toOpenArray(0, converted.len-1), frameNo, w, h, modeOut, state)
  else:
    preProcessScanLines(png, input.toOpenArray(0, input.len-1), frameNo, w, h, modeOut, state)

proc encoderCore[T](png: PNG[T]) =
  let state = PNGEncoder(png.settings)
  var modeIn = newColorMode(state.modeIn)
  var modeOut = newColorMode(state.modeOut)
  var sequenceNumber = 0

  if not bitDepthAllowed(modeIn.colorType, modeIn.bitDepth):
    raise PNGFatal("modeIn colorType and bitDepth combination not allowed")

  if not bitDepthAllowed(modeOut.colorType, modeOut.bitDepth):
    raise PNGFatal("modeOut colorType and bitDepth combination not allowed")

  if(modeOut.colorType == LCT_PALETTE or state.forcePalette) and
    (modeOut.paletteSize == 0 or modeOut.paletteSize > 256):
    raise PNGFatal("invalid palette size, it is only allowed to be 1-256")

  if state.filterStrategy == LFS_PREDEFINED:
    if state.predefinedFilters.len != png.height:
      raise PNGFatal("predefinedFilters length not equals to image height")

  let inputSize = getRawSize(png.width, png.height, modeIn)
  if png.pixels.len < inputSize:
    raise PNGFatal("not enough input to encode")

  if state.autoConvert:
    png.autoChooseColor(modeOut, modeIn)

  if state.interlaceMethod notin {IM_NONE, IM_INTERLACED}:
    raise PNGFatal("unexisting interlace mode")

  if not bitDepthAllowed(modeOut.colorType, modeOut.bitDepth):
    raise PNGFatal("colorType and bitDepth combination not allowed")

  if not png.isAPNG: png.apngPixels = @[newStorage[T](0)]

  shallowCopy(png.apngPixels[0], png.pixels)
  frameConvert[T](png, modeIn, modeOut, png.width, png.height, 0, state)
  shallowCopy(png.pixels, png.apngPixels[0])

  png.addChunkIHDR(png.width, png.height, modeOut, state)
  #unknown chunks between IHDR and PLTE
  if state.unknown.len > 0:
    png.chunks.add state.unknown[0]

  if modeOut.colorType == LCT_PALETTE: png.addChunkPLTE(modeOut)
  if state.forcePalette and modeOut.colorType in {LCT_RGB, LCT_RGBA}: png.addChunkPLTE(modeOut)

  if(modeOut.colorType == LCT_PALETTE) and (getPaletteTranslucency(modeOut) != 0):
    png.addChunktRNS(modeOut)

  if modeOut.colorType in {LCT_GREY, LCT_RGB} and modeOut.keyDefined:
    png.addChunktRNS(modeOut)

  #bKGD (must come between PLTE and the IDAt chunks
  if state.backgroundDefined: png.addChunkbKGD(modeOut, state)

  #pHYs (must come before the IDAT chunks)
  if state.physDefined: png.addChunkpHYs(state)

  #unknown chunks between PLTE and IDAT
  if state.unknown.len > 1:
    png.chunks.add state.unknown[1]

  if png.isAPNG:
    if png.apngPixels.len != png.apngChunks.len:
      raise PNGFatal("APNG encoder frame error")
    if png.apngPixels.len == 0:
      raise PNGFatal("APNG encoder no frame")
    png.addChunkacTL(png.apngPixels.len, state.numPlays)
    if png.firstFrameIsDefaultImage:
      png.addChunkfcTL(APNGFrameControl(png.apngChunks[0]), sequenceNumber)
      inc sequenceNumber

  #IDAT (multiple IDAT chunks must be consecutive)
  png.addChunkIDAT(state)

  if png.isAPNG:
    let len = png.apngChunks.len
    for i in 1..<len:
      var ctl = APNGFrameControl(png.apngChunks[i])
      png.addChunkfcTL(ctl, sequenceNumber)
      inc sequenceNumber

      frameConvert[T](png, modeIn, modeOut, ctl.width, ctl.height, i, state)
      png.addChunkfdAT(sequenceNumber, i)
      inc sequenceNumber

  if state.timeDefined: png.addChunktIME(state)

  for txt in state.textList:
    if state.textCompression: png.addChunkzTXt(txt)
    else: png.addChunktEXt(txt)

  if state.addID:
    var txt = PNGKeyText(keyword: "nimPNG", text: NIM_PNG_VERSION)
    png.addChunktEXt(txt)

  for txt in state.itextList:
    png.addChunkiTXt(txt)

  #unknown chunks between IDAT and IEND
  if state.unknown.len > 2:
    png.chunks.add state.unknown[2]

  png.addChunkIEND()

proc encodePNG*[T](input: T, w, h: int, settings = PNGEncoder(nil)): PNG[T] =
  var png: PNG[T]
  new(png)
  png.chunks = @[]

  if settings == nil: png.settings = makePNGEncoder()
  else: png.settings = settings

  png.width = w
  png.height = h
  shallowCopy(png.pixels, input)
  encoderCore[T](png)
  result = png

proc encodePNG*[T](input: T, colorType: PNGColorType, bitDepth, w, h: int, settings = PNGEncoder(nil)): PNG[T] =
  if not bitDepthAllowed(colorType, bitDepth):
    raise PNGFatal("colorType and bitDepth combination not allowed")

  var state: PNGEncoder
  if settings == nil: state = makePNGEncoder()
  else: state = settings

  state.modeIn.colorType = colorType
  state.modeIn.bitDepth = bitDepth
  result = encodePNG(input, w, h, state)

template encodePNG32*[T](input: T, w, h: int): auto =
  when T is openArray:
    encodePNG(@(input), LCT_RGBA, 8, w, h)
  else:
    encodePNG(input, LCT_RGBA, 8, w, h)

template encodePNG24*[T](input: T, w, h: int): auto =
  when T is openArray:
    encodePNG(@(input), LCT_RGB, 8, w, h)
  else:
    encodePNG(input, LCT_RGB, 8, w, h)

proc writeChunks*[T](png: PNG[T], s: Stream) =
  s.write PNGSignature

  for chunk in png.chunks:
    if not chunk.validateChunk(png): raise PNGFatal("combine chunk validation error " & $chunk.chunkType)
    if not chunk.writeChunk(png): raise PNGFatal("combine chunk write error " & $chunk.chunkType)
    chunk.length = chunk.data.len
    chunk.crc = crc32(crc32(0, $chunk.chunkType), chunk.data)

    s.writeInt32BE chunk.length
    s.writeInt32BE int(chunk.chunkType)
    s.write chunk.data
    s.writeInt32BE cast[int](chunk.crc)

type
  PNGStatus* = Result[void, string]
  PNGBytes*[T] = Result[T, string]

when not defined(js):
  proc savePNGImpl*[T](fileName: string, input: T, colorType: PNGColorType, bitDepth, w, h: int): PNGStatus =
    try:
      var png = encodePNG(input, colorType, bitDepth, w, h)
      var s = newFileStream(fileName, fmWrite)
      png.writeChunks s
      s.close()
      result.ok()
    except PNGError, IOError, NZError:
      result.err(getCurrentExceptionMsg())

  proc savePNG32Impl*[T](fileName: string, input: T, w, h: int): PNGStatus =
    savePNGImpl(fileName, input, LCT_RGBA, 8, w, h)

  proc savePNG24Impl*[T](fileName: string, input: T, w, h: int): PNGStatus =
    savePNGImpl(fileName, input, LCT_RGB, 8, w, h)

proc prepareAPNG*(T: type, colorType: PNGColorType, bitDepth, numPlays: int, settings = PNGEncoder(nil)): PNG[T] =
  var state: PNGEncoder
  if settings == nil: state = makePNGEncoder()
  else: state = settings

  state.numPlays = numPlays
  state.modeIn.colorType = colorType
  state.modeIn.bitDepth = bitDepth

  var png: PNG[T]
  new(png)
  png.chunks = @[]
  png.settings = state
  png.isAPNG = true
  png.apngChunks = @[]
  png.apngPixels = @[]
  png.pixels = ""
  png.firstFrameIsDefaultImage = false
  png.width = 0
  png.height = 0

  result = png

proc prepareAPNG24*(T: type, numPlays = 0): PNG[T] =
  prepareAPNG(T, LCT_RGB, 8, numPlays)

proc prepareAPNG32*(T: type, numPlays = 0): PNG[T] =
  prepareAPNG(T, LCT_RGBA, 8, numPlays)

proc addDefaultImage*[T](png: PNG[T], input: T, width, height: int, ctl = APNGFrameControl(nil)): bool =
  result = true
  png.firstFrameIsDefaultImage = ctl != nil
  if ctl != nil:
    png.apngChunks.add ctl
    png.apngPixels.add "" # add dummy
    result = result and (ctl.xOffset == 0)
    result = result and (ctl.yOffset == 0)
    result = result and (ctl.width == width)
    result = result and (ctl.height == height)
  else:
    png.apngChunks.add nil
    png.apngPixels.add ""

  shallowCopy(png.pixels, input)
  png.width = width
  png.height = height

proc addFrame*[T](png: PNG[T], frame: T, ctl: APNGFrameControl): bool =
  result = true

  # addDefaultImage must be called first
  if png.apngPixels.len == 0 or png.apngChunks.len == 0: return false
  if ctl.isNil: return false
  result = result and (ctl.xOffset >= 0)
  result = result and (ctl.yOffset >= 0)
  result = result and (ctl.width > 0)
  result = result and (ctl.height > 0)
  result = result and (ctl.xOffset + ctl.width <= png.width)
  result = result and (ctl.yOffset + ctl.height <= png.height)

  if result:
    png.apngPixels.add frame
    png.apngChunks.add ctl

proc encodeAPNGImpl*[T](png: PNG[T]): PNGBytes[T] =
  try:
    encoderCore[T](png)
    var s = newStringStream()
    png.writeChunks s
    when T is string:
      result.ok(s.data)
    else:
      result.ok(cast[seq[byte]](s.data))
  except PNGError, IOError, NZError:
    result.err(getCurrentExceptionMsg())

when not defined(js):
  proc saveAPNGImpl*[T](png: PNG[T], fileName: string): PNGStatus =
    try:
      encoderCore[T](png)
      var s = newFileStream(fileName, fmWrite)
      png.writeChunks s
      s.close()
      result.ok()
    except PNGError, IOError, NZError:
      result.err(getCurrentExceptionMsg())

when not defined(js):
  proc savePNGLegacy*(fileName, input: string, colorType: PNGColorType, bitDepth, w, h: int): bool =
    let res = savePNGImpl(fileName, input, colorType, bitDepth, w, h)
    if res.isOk: result = true
    else:
      result = false
      debugEcho res.error()

  proc savePNG32Legacy*(fileName, input: string, w, h: int): bool =
    let res = savePNG32Impl(fileName, input, w, h)
    if res.isOk: result = true
    else:
      result = false
      debugEcho res.error()

  proc savePNG24Legacy*(fileName, input: string, w, h: int): bool =
    let res = savePNG24Impl(fileName, input, w, h)
    if res.isOk: result = true
    else:
      result = false
      debugEcho res.error()

  template savePNG*[T](fileName: string, input: T, colorType: PNGColorType, bitDepth, w, h: int): untyped =
    when T is string:
      savePNGLegacy(fileName, input, colorType, bitDepth, w , h)
    elif T is openArray:
      savePNGImpl(fileName, @(input), colorType, bitDepth, w , h)
    else:
      savePNGImpl(fileName, input, colorType, bitDepth, w , h)

  template savePNG32*[T](fileName: string, input: T, w, h: int): untyped =
    when T is string:
      savePNG32Legacy(fileName, input, w, h)
    elif T is openArray:
      savePNG32Impl(fileName, @(input), w, h)
    else:
      savePNG32Impl(fileName, input, w, h)

  template savePNG24*[T](fileName: string, input: T, w, h: int): untyped =
    when T is string:
      savePNG24Legacy(fileName, input, w, h)
    elif T is openArray:
      savePNG24Impl(fileName, @(input), w, h)
    else:
      savePNG24Impl(fileName, input, w, h)

proc prepareAPNG*(colorType: PNGColorType, bitDepth, numPlays: int, settings = PNGEncoder(nil)): PNG[string] =
  prepareAPNG(string, colorType, bitDepth, numPlays, settings)

proc prepareAPNG24*(numPlays = 0): PNG[string] =
  prepareAPNG24(string, numPlays)

proc prepareAPNG32*(numPlays = 0): PNG[string] =
  prepareAPNG32(string, numPlays)

proc encodeAPNGLegacy*[T](png: PNG[T]): string =
  let res = encodeAPNGImpl(png)
  if res.isOk:
    result = res.get()
  else:
    debugEcho res.error()

template encodeAPNG*[T](png: PNG[T]): untyped =
  when T is string:
    encodeAPNGLegacy(png)
  else:
    encodeAPNGImpl(png)

when not defined(js):
  proc saveAPNGLegacy*[T](png: PNG[T], fileName: string): bool =
    let res = saveAPNGImpl(png, fileName)
    if res.isOk: result = true
    else:
      result = false
      debugEcho res.error()

  template saveAPNG*[T](png: PNG[T], fileName: string): untyped =
    when T is string:
      savePNGLegacy(png, fileName)
    else:
      savePNGImpl(png, fileName)

proc getFilterTypesInterlaced(png: PNG): seq[seq[PNGFilter]] =
  var header = PNGHeader(png.getChunk(IHDR))
  var idat = PNGData(png.getChunk(IDAT))

  if header.interlaceMethod == IM_NONE:
    result = newSeq[seq[PNGFilter]](1)
    result[0] = @[]

    #A line is 1 filter byte + all pixels
    let lineBytes = 1 + idatRawSize(header.width, 1, header)
    var i = 0
    while i < idat.idat.len:
      result[0].add PNGFilter(idat.idat[i].int)
      inc(i, lineBytes)
  else:
    result = newSeq[seq[PNGFilter]](7)
    for j in 0..6:
      result[j] = @[]
      var w2 = (header.width - ADAM7_IX[j] + ADAM7_DX[j] - 1) div ADAM7_DX[j]
      var h2 = (header.height - ADAM7_IY[j] + ADAM7_DY[j] - 1) div ADAM7_DY[j]
      if(ADAM7_IX[j] >= header.width) or (ADAM7_IY[j] >= header.height):
        w2 = 0
        h2 = 0

      let lineBytes = 1 + idatRawSize(w2, 1, header)
      var pos = 0
      for i in 0..h2-1:
        result[j].add PNGFilter(idat.idat[pos].int)
        inc(pos, linebytes)

proc getFilterTypes*(png: PNG): seq[PNGFilter] =
  var passes = getFilterTypesInterlaced(png)

  if passes.len == 1:
    result = passes[0]
  else:
    var header = PNGHeader(png.getChunk(IHDR))
    #Interlaced. Simplify it: put pass 6 and 7 alternating in the one vector so
    #that one filter per scanline of the uninterlaced image is given, with that
    #filter corresponding the closest to what it would be for non-interlaced image.
    result = @[]
    for i in 0..header.height-1:
      if (i mod 2) == 0: result.add passes[5][i div 2]
      else: result.add passes[6][i div 2]
