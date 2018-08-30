import streams

type
  BMP* = ref object
    width*, height*: int
    data*: string

proc writeWORD(s: Stream, val: int) =
  let word = val.int16
  s.write(word)

proc writeDWORD(s: Stream, val: int) =
  let dword = val.int32
  s.write(dword)

proc newBMP*(w, h: int): BMP =
  new(result)
  result.width = w
  result.height = h
  result.data = newString(w * h * 3)

proc write*(s: Stream, bmp: BMP) =
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
  let padding     = if paddingLen > 0: newString(paddingLen) else: ""

  for i in 0..bmp.height-1:
    s.writeData(addr(bmp.data[i * bytesPerRow]), bytesPerRow)
    if paddingLen > 0: s.write(padding)
