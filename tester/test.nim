import nimPNG, streams, minibmp, os, strutils

proc write(bmp: BMP): string =
  var s = newStringStream()
  minibmp.write(s, bmp)
  result = s.data

proc toBMP(png: PNGResult, fileName: string) =
  if png.frames.len != 0:
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

proc generateAPNG() =
  const numFrames = 7
  var frames: array[numFrames, PNGResult]

  for i in 0..<numFrames:
    frames[i] = loadPNG24(".." & DirSep & "apng" & DirSep & "raw" & DirSep & "frame" & $i & ".png")

  var png = prepareAPNG24()

  var ctl = new(APNGFrameControl)
  ctl.width = frames[0].width
  ctl.height = frames[0].height
  ctl.xOffset = 0
  ctl.yOffset = 0
  # half second delay = delayNum/delayDen
  ctl.delayNum = 1
  ctl.delayDen = 2
  ctl.disposeOp = APNG_DISPOSE_OP_NONE
  ctl.blendOp = APNG_BLEND_OP_SOURCE

  if not png.addDefaultImage(frames[0].data, frames[0].width, frames[0].height, ctl):
    echo "failed to add default image"
    quit(1)

  for i in 1..<numFrames:
    var ctl = new(APNGFrameControl)
    ctl.width = frames[i].width
    ctl.height = frames[i].height
    ctl.xOffset = 0
    ctl.yOffset = 0
    ctl.delayNum = 1
    ctl.delayDen = 2
    ctl.disposeOp = APNG_DISPOSE_OP_NONE
    ctl.blendOp = APNG_BLEND_OP_SOURCE

    if not png.addFrame(frames[i].data, ctl):
      echo "failed to add frames"
      quit(1)

  if not png.saveAPNG("rainbow.png"):
    echo "failed to save rainbow.png"
    quit(1)

proc main() =
  let data = loadPNG32("sample.png")
  assert(not data.isNil)
  convert(".." & DirSep & "apng")
  generateAPNG()

main()
