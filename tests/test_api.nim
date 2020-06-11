import ../nimPNG, unittest, os

proc main() =
  const subject = "tests" / "misc" / "sample.png"

  const subject24 = "tests" / "misc" / "sample24.png"
  const subject32 = "tests" / "misc" / "sample32.png"

  let data = cast[string](readFile(subject))
  suite "test API":
    test "decodePNG/encodePNG/savePNG string":
      let png1 = decodePNG24(data)
      let png2 = decodePNG32(data)

      let im1 = encodePNG24(png1.data, png1.width, png1.height)
      let im2 = encodePNG32(png2.data, png2.width, png2.height)

      check savePNG24(subject24, png1.data, png1.width, png1.height) == true
      check savePNG32(subject32, png2.data, png2.width, png2.height) == true

    test "decodePNG/encodePNG/savePNG seq[uint8]":
      let res1 = decodePNG24(cast[seq[uint8]](data))
      let res2 = decodePNG32(cast[seq[uint8]](data))
      check res1.isOk() == true
      check res2.isOk() == true

      let png1 = res1.get()
      let png2 = res2.get()

      let im1 = encodePNG24(png1.data, png1.width, png1.height)
      let im2 = encodePNG32(png2.data, png2.width, png2.height)

      check savePNG24(subject24, png1.data, png1.width, png1.height).isOk() == true
      check savePNG32(subject32, png2.data, png2.width, png2.height).isOk() == true

    test "decodePNG openArray[uint8]":
      let png1 = decodePNG24(data.toOpenArrayByte(0, data.len-1))
      let png2 = decodePNG32(data.toOpenArrayByte(0, data.len-1))

    test "loadPNG string":
      let png1 = loadPNG32(string, subject)
      let png2 = loadPNG24(string, subject)

    test "loadPNG string":
      let png1 = loadPNG32(seq[uint8], subject)
      let png2 = loadPNG24(seq[uint8], subject)

main()
