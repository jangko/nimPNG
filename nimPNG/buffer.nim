import sequtils

type
  Buffer*[T] = object ## Uses T as internal data buffer
    data*: T
    offset*: int
  SeqBuffer*[T] = Buffer[seq[T]] ## Uses seq[T] as internal data buffer

template `[]`*[T](b: Buffer[T], i: int): auto = b.data[b.offset + i]
template `[]=`*[S, T](b: var Buffer[S], i: int, v: T) = b.data[b.offset + i] = v

proc init*[T](b: var Buffer[T], d: sink T) =
  b.data = d
  b.offset = 0

proc initBuffer*[T](d: sink T): Buffer[T] =
  result.data = d

template isNil*[T](b: Buffer[T]): bool =
  when T is (string or seq):
    b.data.len == 0
  else:
    b.data.isNil

template copyElements*[T](dst: var Buffer[T], src: Buffer[T], count: int) =
  when defined(js):
    for i in 0 ..< count: dst[i] = src[i]
  else:
    copyMem(addr dst[dst.offset], unsafeAddr src[src.offset], count * sizeof(dst[0]))

template zeroMem*[T](dst: var Buffer[T]) =
  when defined(js):
    applyIt(dst.data, type(dst[0])(0))
  else:
    zeroMem(addr dst.data[dst.offset], sizeof(dst[0]) * (dst.data.len - dst.offset))
