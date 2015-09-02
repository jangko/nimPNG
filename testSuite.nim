import streams, os, strutils, nimPNG

type
  BMP = ref object
    width, height: int
    data: string

proc writeWORD(s: Stream, val: int) =
  let word = int16(val)
  s.write(word)

proc writeDWORD(s: Stream, val: int) =
  s.write(val)

proc newBMP(w, h: int): BMP =
  new(result)
  result.width = w
  result.height = h
  result.data = newString(w * h * 3)

proc write(s: Stream, bmp: BMP) =
  let stride    = 4 * ((bmp.width * 24 + 31) div 32)
  let imageData = stride * bmp.height
  let offset    = 54
  var fileSize  = imageData + offset
  s.writeWORD(19778)
  s.writeDWORD(fileSize)
  s.writeWORD(0)
  s.writeWORD(0)
  s.writeDWORD(offset)
  s.writeDWORD(40)
  s.writeDWORD(bmp.width)
  s.writeDWORD(bmp.height)
  s.writeWORD(1)
  s.writeWORD(24)
  s.writeDWORD(0)
  s.writeDWORD(imageData)
  s.writeDWORD(3780)
  s.writeDWORD(3780)
  s.writeDWORD(0)
  s.writeDWORD(0)

  let bytesPerRow = bmp.width * 3
  let paddingLen  = stride - bytesPerRow
  let padding     = if paddingLen > 0: newString(paddingLen) else: nil

  for i in 0..bmp.height-1:
    s.writeData(addr(bmp.data[i * bytesPerRow]), bytesPerRow)
    if paddingLen > 0: s.write(padding)

proc loadPNG(fileName: string): BMP =
  var settings = makeDefaultPNGDecoderSettings()
  settings.readTextChunks = true
  var png = loadPNG24(fileName, settings)
  if png == nil: return nil
  let size = png.width * png.height
  result = newBMP(png.width, png.height)
  for i in 0..size-1:
    let px = i * 3
    result.data[px]     = png.data[px]
    result.data[px + 1] = png.data[px + 1]
    result.data[px + 2] = png.data[px + 2]

proc write(bmp: BMP): string =
  var s = newStringStream()
  s.write(bmp)
  result = s.data

proc convert(dir: string) =
  for fileName in walkDirRec(dir, {pcFile}):
    let path = splitFile(fileName)
    if path.ext.len() == 0: continue

    let ext = toLower(path.ext)
    if ext != ".png": continue
    if path.name[0] == 'x': continue
    
    let bmpName = path.dir & DirSep & path.name & ExtSep & "bmp"
    
    echo fileName, " vs. ", bmpName
    var bmp = loadPNG(fileName)
    if bmp != nil:
      let data1 = bmp.write()
      let data2 = readFile(bmpName)
      assert data1 == data2

convert("suite")
