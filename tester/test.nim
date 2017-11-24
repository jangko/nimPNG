import nimPNG, streams, minibmp, os, strutils

proc write(bmp: BMP): string =
  var s = newStringStream()
  s.write(bmp)
  result = s.data

proc toBMP(png: PNGResult, fileName: string) =
  if png.frames != nil:
    var frame = 0
    for x in png.frames:
      var bmp = newBMP(x.ctl.width, x.ctl.height)
      let size = bmp.width * bmp.height
      for i in 0..size-1:
        let px = i * 3
        let px4 = i * 4
        if x.data[px4 + 3] == chr(0):
          bmp.data[px]     = chr(0xFF)
          bmp.data[px + 1] = chr(0xFF)
          bmp.data[px + 2] = chr(0xFF)
        else:
          let alpha = uint(x.data[px4 + 3])
          bmp.data[px]     = chr(uint8(255) + uint8(((x.data[px4 + 2].uint - 255'u) * alpha) shr 8))
          bmp.data[px + 1] = chr(uint8(255) + uint8(((x.data[px4 + 1].uint - 255'u) * alpha) shr 8))
          bmp.data[px + 2] = chr(uint8(255) + uint8(((x.data[px4 + 0].uint - 255'u) * alpha) shr 8))

      let bmpName = fileName & "_" & $frame & ".bmp"
      #var s = newFileStream(bmpName, fmWrite)
      #s.write(bmp)
      #s.close()

      let data1 = bmp.write()
      let data2 = readFile(bmpName)
      assert data1 == data2
      echo "frame $1 of $2" % [$(frame + 1), $png.frames.len]

      inc frame

proc convert(dir: string) =
  for fileName in walkDirRec(dir, {pcFile}):
    let path = splitFile(fileName)
    if path.ext.len() == 0: continue

    let ext = toLowerAscii(path.ext)
    if ext != ".png": continue

    let bmpName = path.dir & DirSep & "frames" & DirSep & path.name
    echo fileName

    let png = loadPNG32(fileName)
    if png == nil: continue
    png.toBMP(bmpName)

proc main() =
  let data = loadPNG32("sample.png")
  assert(not data.isNil)
  convert(".." & DirSep & "apng")

main()
