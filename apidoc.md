## Legacy API

```Nim
proc encodePNG*(input: string, colorType: PNGColorType, bitDepth, w, h: int, settings = PNGEncoder(nil)): PNG
proc encodePNG32*(input: string, w, h: int): PNG
proc encodePNG24*(input: string, w, h: int): PNG

when not defined(js):
  proc savePNG*(fileName, input: string, colorType: PNGColorType, bitDepth, w, h: int): bool
  proc savePNG32*(fileName, input: string, w, h: int): bool
  proc savePNG24*(fileName, input: string, w, h: int): bool

proc prepareAPNG*(colorType: PNGColorType, bitDepth, numPlays: int, settings = PNGEncoder(nil)): PNG
proc prepareAPNG24*(numPlays = 0): PNG
proc prepareAPNG32*(numPlays = 0): PNG
proc addDefaultImage*(png: PNG, input: string, width, height: int, ctl = APNGFrameControl(nil)): bool
proc addFrame*(png: PNG, frame: string, ctl: APNGFrameControl): bool
proc encodeAPNG*(png: PNG): string

when not defined(js):
  proc saveAPNG*(png: PNG, fileName: string): bool

proc decodePNG*(s: Stream, colorType: PNGColorType, bitDepth: int, settings = PNGDecoder(nil)): PNGResult
proc decodePNG*(s: Stream, settings = PNGDecoder(nil)): PNG

when not defined(js):
  proc loadPNG*(fileName: string, colorType: PNGColorType, bitDepth: int, settings: PNGDecoder = nil): PNGResult
  proc loadPNG32*(fileName: string, settings = PNGDecoder(nil)): PNGResult
  proc loadPNG24*(fileName: string, settings = PNGDecoder(nil)): PNGResult

proc decodePNG32*(input: string, settings = PNGDecoder(nil)): PNGResult
proc decodePNG24*(input: string, settings = PNGDecoder(nil)): PNGResult
```


## New API


```Nim
proc decodePNG*(T: type, s: Stream, colorType: PNGColorType, bitDepth: int, settings = PNGDecoder(nil)): PNGResult[T]
proc decodePNG*(T: type, s: Stream, settings = PNGDecoder(nil)): PNG

type
  PNGRes*[T] = Result[PNGResult[T], string]

when not defined(js):
  proc loadPNG*(T: type, fileName: string, colorType: PNGColorType, bitDepth: int, settings: PNGDecoder = nil): PNGRes[T]
  proc loadPNG32*(T: type, fileName: string, settings = PNGDecoder(nil)): PNGRes[T]
  proc loadPNG24*(T: type, fileName: string, settings = PNGDecoder(nil)): PNGRes[T]

proc decodePNG32*(T: type, input: T, settings = PNGDecoder(nil)): PNGRes[T]
proc decodePNG24*(T: type, input: T, settings = PNGDecoder(nil)): PNGRes[T]
```

## How to use PNGRes?

```Nim
  let res = loadPNG32(seq[uint8], fileName, settings)
  if res.isOk: result = res.get()  # get PNGResult[seq[uint8]]
  else: debugEcho res.error()      # get error string
```
