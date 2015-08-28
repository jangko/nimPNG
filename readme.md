#nimPNG
Portable Network Graphics Encoder and Decoder written in Nim
store lossless image with godd compression

all PNG standard color mode are supported:

  -  LCT_GREY = 0,       # greyscale: 1,2,4,8,16 bit
  -  LCT_RGB = 2,        # RGB: 8,16 bit
  -  LCT_PALETTE = 3,    # palette: 1,2,4,8 bit
  -  LCT_GREY_ALPHA = 4, # greyscale with alpha: 8,16 bit
  -  LCT_RGBA = 6        # RGB with alpha: 8,16 bit

both interlaced and non-interlaced mode supported

recognize all PNG standard chunks:
IHDR, IEND, PLTE, IDAT, tRNS, bKGD, pHYs, tIME, iTXt, zTXt
tEXt, gAMA, cHRM, sRGB, iCCP, sBIT, sPLT, hIST

unknown chunks will be handled properly

the following chunks are supported (generated/interpreted) by both encoder and decoder:

-    IHDR: header information
-    PLTE: color palette
-    IDAT: pixel data
-    IEND: the final chunk
-    tRNS: transparency for palettized images
-    tEXt: textual information
-    zTXt: compressed textual information
-    iTXt: international textual information
-    bKGD: suggested background color
-    pHYs: physical dimensions
-    tIME: modification time

the following chunks are parsed correctly, but not used by decoder:
cHRM, gAMA, iCCP, sRGB, sBIT, hIST, sPLT

Supported color conversions:

- anything to 8-bit RGB, 8-bit RGBA, 16-bit RGB, 16-bit RGBA
- any grey or grey+alpha, to grey or grey+alpha
- anything to a palette, as long as the palette has the requested colors in it
- removing alpha channel
- higher to smaller bitdepth, and vice versa