import streams, os, strutils, nimPNG, minibmp

proc loadPNG(fileName: string): BMP =
  var settings = makePNGDecoder()
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
  minibmp.write(s, bmp)
  result = s.data

proc convert(dir: string) =
  for fileName in walkDirRec(dir, {pcFile}):
    let path = splitFile(fileName)
    if path.ext.len() == 0: continue

    let ext = toLowerAscii(path.ext)
    if ext != ".png": continue
    if path.name[0] == 'x': continue

    let bmpName = path.dir & DirSep & path.name & ExtSep & "bmp"

    echo fileName, " vs. ", bmpName
    var bmp = loadPNG(fileName)
    if bmp != nil:
      let data1 = bmp.write()
      let data2 = readFile(bmpName)
      assert data1 == data2

convert(".." & DirSep & "suite")
