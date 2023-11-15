import ../nimPNG/nimz, unittest, os

template check_roundtrip(source) =
  test source:
    block:
      let input = readFile("tests" / "zcorpus" / source)
      let nzcomp = nzCompressInit(input)
      let output = zlib_compress(nzcomp)
      let nzdecomp = nzDecompressInit(output)
      let uncomp = zlib_decompress(nzdecomp)
      check uncomp.len == input.len
      if uncomp != input:
        check false

proc main() =
  suite "nimz":
    check_roundtrip("alice29.txt")
    check_roundtrip("house.jpg")
    check_roundtrip("html")
    check_roundtrip("fireworks.jpeg")
    check_roundtrip("paper-100k.pdf")
    check_roundtrip("html_x_4")
    check_roundtrip("asyoulik.txt")
    check_roundtrip("lcet10.txt")
    check_roundtrip("plrabn12.txt")
    check_roundtrip("geo.protodata")
    check_roundtrip("kppkn.gtb")
    check_roundtrip("Mark.Twain-Tom.Sawyer.txt")

main()
