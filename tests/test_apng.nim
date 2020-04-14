import ../nimPNG, streams, ./minibmp, os, strutils

proc write(bmp: BMP): string =
  var s = newStringStream()
  s.writeBMP(bmp)
  result = s.data

proc toBMP(png: PNGResult, fileName: string) =
  if png.frames != @[]:
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
          bmp.data[px]     = chr(uint8(255) + uint8((((x.data[px4 + 2].uint - 255'u) * alpha) shr 8) and 0xFF))
          bmp.data[px + 1] = chr(uint8(255) + uint8((((x.data[px4 + 1].uint - 255'u) * alpha) shr 8) and 0xFF))
          bmp.data[px + 2] = chr(uint8(255) + uint8((((x.data[px4 + 0].uint - 255'u) * alpha) shr 8) and 0xFF))

      let bmpName = fileName & "_" & $frame & ".bmp"

      let data1 = bmp.write()
      let data2 = readFile(bmpName)
      assert data1 == data2
      echo "frame $1 of $2 vs. $3" % [$(frame + 1), $png.frames.len, bmpName]

      inc frame

proc convert(dir: string) =
  for fileName in walkDirRec(dir, {pcFile}):
    let path = splitFile(fileName)
    if path.ext.len() == 0: continue

    let ext = toLowerAscii(path.ext)
    if ext != ".png": continue

    let bmpName = path.dir / "frames" / path.name
    echo fileName

    let png = loadPNG32(fileName)
    if png == nil: continue
    png.toBMP(bmpName)

proc generateAPNG() =
  const numFrames = 7
  var frames: array[numFrames, PNGResult]

  for i in 0..<numFrames:
    frames[i] = loadPNG24("tests" / "apng" / "raw" / "frame" & $i & ".png")

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

  let rainbowPNG = png.encodeAPNG()
  let rainbowFile = readFile("tests" / "misc" / "rainbow.png")
  if rainbowPNG != rainbowFile:
    echo "failed to encode rainbow.png"
    quit(1)

proc main() =
  let data = loadPNG32("tests" / "misc" / "sample.png")
  assert(not data.isNil)
  convert("tests" / "apng")
  generateAPNG()

main()
