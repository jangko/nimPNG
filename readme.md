# nimPNG (PNG + APNG)
Portable Network Graphics Encoder and Decoder written in Nim store lossless image with good compression.

Notable releases:
- 0.2.0 support Animated PNG!
- 0.2.6 compile with --gc:arc.
- 0.3.0 [new set of API](apidoc.md) using seq[uint8] and new method to handle error.
- 0.3.1 fix new API bug and add openArray API

[![Build Status (Travis)](https://img.shields.io/travis/jangko/nimPNG/master.svg?label=Linux%20/%20macOS "Linux/macOS build status (Travis)")](https://travis-ci.org/jangko/nimPNG)
[![Build status](https://ci.appveyor.com/api/projects/status/7ap5r5a41t7ea04p?svg=true)](https://ci.appveyor.com/project/jangko/nimpng)
![nimble](https://img.shields.io/badge/available%20on-nimble-yellow.svg?style=flat-square)
![license](https://img.shields.io/github/license/citycide/cascade.svg?style=flat-square)

all PNG standard color mode are supported:

- LCT_GREY = 0,       # greyscale: 1,2,4,8,16 bit
- LCT_RGB = 2,        # RGB: 8,16 bit
- LCT_PALETTE = 3,    # palette: 1,2,4,8 bit
- LCT_GREY_ALPHA = 4, # greyscale with alpha: 8,16 bit
- LCT_RGBA = 6        # RGB with alpha: 8,16 bit

both interlaced and non-interlaced mode supported

recognize all PNG standard chunks:
IHDR, IEND, PLTE, IDAT, tRNS, bKGD, pHYs, tIME, iTXt, zTXt
tEXt, gAMA, cHRM, sRGB, iCCP, sBIT, sPLT, hIST

unknown chunks will be handled properly

the following chunks are supported (generated/interpreted) by both encoder and decoder:

- IHDR: header information
- PLTE: color palette
- IDAT: pixel data
- IEND: the final chunk
- tRNS: transparency for palettized images
- tEXt: textual information
- zTXt: compressed textual information
- iTXt: international textual information
- bKGD: suggested background color
- pHYs: physical dimensions
- tIME: modification time

the following chunks are parsed correctly, but not used by decoder:
cHRM, gAMA, iCCP, sRGB, sBIT, hIST, sPLT

Supported color conversions:

- anything to 8-bit RGB, 8-bit RGBA, 16-bit RGB, 16-bit RGBA
- any grey or grey+alpha, to grey or grey+alpha
- anything to a palette, as long as the palette has the requested colors in it
- removing alpha channel
- higher to smaller bitdepth, and vice versa

### Planned Feature(s):
- streaming for progressive loading

## Basic Usage
```Nim
import nimPNG

let png = loadPNG32("image.png")
#is equivalent to:
#let png = loadPNG("image.png", LCT_RGBA, 8)
#will produce rgba pixels:
#png.width -> width of the image
#png.height -> height of the image
#png.data -> pixels data in RGBA format
```

if you already have the whole file in memory:

```Nim
let png = decodePNG32(raw_bytes)
#will do the same as above
```

other variants:

* loadPNG24 -> will produce pixels in RGB format 8 bpp
* decodePNG24 -> load png from memory instead of file

to create PNG:

* savePNG32("output.png", rgba_pixels, width, height) or savePNG24
* encodePNG32(rgba_pixels, width, height) or encodePNG24

special notes:

* Use **loadPNG** or **savePNG** if you need specific input/output format by supplying supported **colorType** and **bitDepth** information.
* Use **encodePNG** or **decodePNG** to do *in-memory* encoding/decoding by supplying desired **colorType** and **bitDepth** information

pixels are stored as raw bytes using Nim's string as container:

|           Byte Order           |      Format      |
|:------------------------------:|:----------------:|
| r1,g1,b1,a1,...,rn,gn,bn,an    | RGBA 8 bit       |
| r1,g1,b1,r2,g2,b2,...,rn,gn,bn | RGB 8 bit        |
| grey1,grey2,grey3, ..., greyn  | GREY 8 bit       |
| grey1,a1,grey2,a2,...,greyn,an | GREY ALPHA 8 bit |


## Animated PNG (APNG)

Since version 0.2.0, nimPNG provides support for [Animated PNG](https://en.wikipedia.org/wiki/APNG).

Both decoder and encoder recognize/generate APNG chunks correctly: acTL, fcTL, fdAT.

Decoded frames is provided as is, the dimension and coordinate offset might be different with default frame.
No alpha blending or other blending method performed.
It is up to the application to do proper in-memory rendering before displaying the animation.
Don't ask how to do it, any decent graphics rendering library have their own set of API to do alpha blending and
offset rendering. In the future nimPNG might be shipped with simple frame rendering utility for common cases.
Right now nimPNG is just a PNG encoder/decoder.

### Decoding

```Nim
#let png = loadPNG32("image.png")
# or
#let png = loadPNG("image.png", LCT_RGBA, 8)
# or
#let png = decodePNG32(raw_bytes)
```

The usual loadPNG and decodePNG can decode both unanimated and animated PNG.
`png.width`, `png.height`, `png.data` works as usual. If the decoded PNG is an APNG, `png.data` will contains default frame.
Animation frames can be accessible via `png.frames`. If it is not an APNG, `png.frames` will be nil.

### Encoding

```Nim
var png = prepareAPNG24(numPlays)
```

* First step is to call `prepareAPNG`, `prepareAPNG24`, or `prepareAPNG32`. You also can specify how many times the animation
will be played

```Nim
  png.addDefaultImage(framePixels, w, h, ctl)
```

* Second step is also mandatory, you should call `addDefaultImage`. `ctl` is optional, if you provide a `ctl`(Frame Control),
the default image will be part of the animation. If `ctl` is nil, default image will not be part of animation.

```Nim
  png.addFrame(frames[i].data, ctl)
```

* Third step is calling `addFrame` one or more times. Here `ctl` is mandatory.

```Nim
  png.saveAPNG("rainbow.png")
  # or
  var str = png.encodeAPNG()
```

* Final step is to call `saveAPNG` if you want save it to file or call `encodeAPNG` if you want to get the result in a string container

You can read the details of frame control from [spec](https://wiki.mozilla.org/APNG_Specification).
You can also see an example in tester/test.nim -> generateAPNG

## Installation via nimble
> nimble install nimPNG

