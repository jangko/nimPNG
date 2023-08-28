import ../nimPNG, unittest, os

proc main() =
  const subject = "tests" / "misc" / "sample.png"
  const subject24 = "tests" / "misc" / "sample24.png"
  const subject32 = "tests" / "misc" / "sample32.png"

  const tmpOut = "tests" / "tmp"
  createDir(tmpOut)

  let data = cast[string](readFile(subject))
  suite "test API":
    test "decodePNG/encodePNG/savePNG string":
      let png1 = decodePNG24(data)
      let png2 = decodePNG32(data)

      discard encodePNG24(png1.data, png1.width, png1.height)
      discard encodePNG32(png2.data, png2.width, png2.height)

      check savePNG24(subject24, png1.data, png1.width, png1.height) == true
      check savePNG32(subject32, png2.data, png2.width, png2.height) == true

    test "decodePNG/encodePNG/savePNG seq[uint8]":
      let res1 = decodePNG24(cast[seq[uint8]](data))
      let res2 = decodePNG32(cast[seq[uint8]](data))
      check res1.isOk() == true
      check res2.isOk() == true

      let png1 = res1.get()
      let png2 = res2.get()

      discard encodePNG24(png1.data, png1.width, png1.height)
      discard encodePNG32(png2.data, png2.width, png2.height)

      check savePNG24(subject24, png1.data, png1.width, png1.height).isOk() == true
      check savePNG32(subject32, png2.data, png2.width, png2.height).isOk() == true

    test "decodePNG openArray[uint8]":
      let res1 = decodePNG24(data.toOpenArrayByte(0, data.len-1))
      let res2 = decodePNG32(data.toOpenArrayByte(0, data.len-1))

      check res1.isOk() == true
      check res2.isOk() == true

      let png1 = res1.get()
      let png2 = res2.get()

      discard encodePNG24(png1.data.toOpenArray(0, png1.data.len-1), png1.width, png1.height)
      discard encodePNG32(png2.data.toOpenArray(0, png2.data.len-1), png2.width, png2.height)

    test "loadPNG string":
      discard loadPNG32(string, subject)
      discard loadPNG24(string, subject)

    test "loadPNG string":
      discard loadPNG32(seq[uint8], subject)
      discard loadPNG24(seq[uint8], subject)

    test "savePNG with array":
      var data: array[100*100*4, uint8]
      check savePng(tmpOut / "image.png", data, LCT_RGBA, 8, 100, 100).isOk

main()
