## Legacy API

```Nim
encodePNG(input: string, colorType: PNGColorType, bitDepth, w, h: int, settings = PNGEncoder(nil)): PNG
encodePNG32(input: string, w, h: int): PNG
encodePNG24(input: string, w, h: int): PNG

when not defined(js):
  savePNG(fileName, input: string, colorType: PNGColorType, bitDepth, w, h: int): bool
  savePNG32(fileName, input: string, w, h: int): bool
  savePNG24(fileName, input: string, w, h: int): bool

prepareAPNG(colorType: PNGColorType, bitDepth, numPlays: int, settings = PNGEncoder(nil)): PNG
prepareAPNG24(numPlays = 0): PNG
prepareAPNG32(numPlays = 0): PNG
addDefaultImage(png: PNG, input: string, width, height: int, ctl = APNGFrameControl(nil)): bool
addFrame(png: PNG, frame: string, ctl: APNGFrameControl): bool
encodeAPNG(png: PNG): string

when not defined(js):
  saveAPNG(png: PNG, fileName: string): bool

decodePNG(s: Stream, colorType: PNGColorType, bitDepth: int, settings = PNGDecoder(nil)): PNGResult
decodePNG(s: Stream, settings = PNGDecoder(nil)): PNG

when not defined(js):
  loadPNG(fileName: string, colorType: PNGColorType, bitDepth: int, settings: PNGDecoder = nil): PNGResult
  loadPNG32(fileName: string, settings = PNGDecoder(nil)): PNGResult
  loadPNG24(fileName: string, settings = PNGDecoder(nil)): PNGResult

decodePNG32(input: string, settings = PNGDecoder(nil)): PNGResult
decodePNG24(input: string, settings = PNGDecoder(nil)): PNGResult
```


## New API


```Nim
# generic version accept T = `string`, `seq[TT]`, or openArray[TT]
# TT can be `byte`, `char`, or `uint8`
encodePNG(input: T, w, h: int, settings = PNGEncoder(nil)): PNG[T]
encodePNG(input: T, colorType: PNGColorType, bitDepth, w, h: int, settings = PNGEncoder(nil)): PNG[T]
encodePNG32(input: T, w, h: int): PNG[T]
encodePNG24(input: T, w, h: int): PNG[T]
writeChunks(png: PNG[T], s: Stream)

type
  PNGStatus* = Result[void, string]
  PNGBytes*[T] = Result[T, string]

prepareAPNG(T: type, colorType: PNGColorType, bitDepth, numPlays: int, settings = PNGEncoder(nil)): PNG[T]
prepareAPNG24(T: type, numPlays = 0): PNG[T]
prepareAPNG32(T: type, numPlays = 0): PNG[T]
addDefaultImage(png: PNG[T], input: T, width, height: int, ctl = APNGFrameControl(nil)): bool
addFrame(png: PNG[T], frame: T, ctl: APNGFrameControl): bool

when not defined(js):
  savePNG(fileName: string, input: T, colorType: PNGColorType, bitDepth, w, h: int): PNGStatus
  savePNG32(fileName: string, input: T, w, h: int): PNGStatus
  savePNG24(fileName: string, input: T, w, h: int): PNGStatus

encodeAPNG(png: PNG[T]): PNGBytes[T]

when not defined(js):
  saveAPNG(png: PNG[T], fileName: string): PNGStatus

decodePNG(T: type, s: Stream, colorType: PNGColorType, bitDepth: int, settings = PNGDecoder(nil)): PNGResult[T]
decodePNG(T: type, s: Stream, settings = PNGDecoder(nil)): PNG[T]

type
  PNGRes*[T] = Result[PNGResult[T], string]

when not defined(js):
  loadPNG(T: type, fileName: string, colorType: PNGColorType, bitDepth: int, settings: PNGDecoder = nil): PNGRes[T]
  loadPNG32(T: type, fileName: string, settings = PNGDecoder(nil)): PNGRes[T]
  loadPNG24(T: type, fileName: string, settings = PNGDecoder(nil)): PNGRes[T]

decodePNG32(input: T, settings = PNGDecoder(nil)): PNGRes[T]
decodePNG24(input: T, settings = PNGDecoder(nil)): PNGRes[T]
```

## How to use PNGRes?

```Nim
  type
    PNGPix = seq[uint8]

  var pix: PNGResult[PNGPix]
  let res = loadPNG32(PNGPix, fileName)
  if res.isOk: pix = res.get()  # get PNGResult[PNGPix]
  else: debugEcho res.error()   # get error string

  # now you can access PNGResult as usual:
  debugEcho "width: ", pix.width
  debugEcho "height: ", pix.height

  # draw(pix.data)
  # or drawFrames(pix.frames) if it is a APNG
```
