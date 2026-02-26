// ============================================================
// Streaming API for compression/decompression
// ============================================================
// Provides struct-based streaming classes that accept input
// in chunks via push() and produce output via result().
// Internally buffers all chunks and processes on final push.

// ============================================================
// Helper: Concatenate chunks into a single FixedArray[Byte]
// ============================================================

///|
fn concat_chunks(chunks : Array[FixedArray[Byte]]) -> FixedArray[Byte] {
  let mut total = 0
  for i = 0; i < chunks.length(); i = i + 1 {
    total = total + chunks[i].length()
  }
  let result = FixedArray::make(total, b'\x00')
  let mut pos = 0
  for i = 0; i < chunks.length(); i = i + 1 {
    let chunk = chunks[i]
    for j = 0; j < chunk.length(); j = j + 1 {
      result[pos] = chunk[j]
      pos = pos + 1
    }
  }
  result
}

// ============================================================
// DeflateStream - DEFLATE compression stream
// ============================================================

///|
pub struct DeflateStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
  level : Int
  mem : Int
}

///|
pub fn DeflateStream::new(level? : Int = 6, mem? : Int = 4) -> DeflateStream {
  { buf: [], output: [], finished: false, level, mem }
}

///|
pub fn DeflateStream::push(
  self : DeflateStream,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.buf.push(chunk)
  if final_ {
    self.finished = true
    let input = concat_chunks(self.buf)
    let opts = @types.DeflateOptions::{
      level: self.level,
      mem: self.mem,
      dictionary: None,
    }
    let compressed = @deflate.deflate_sync(input, opts~)
    self.output.push(compressed)
  }
}

///|
pub fn DeflateStream::result(
  self : DeflateStream,
) -> FixedArray[Byte] raise @types.FlateError {
  if not(self.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  concat_chunks(self.output)
}

// ============================================================
// InflateStream - DEFLATE decompression stream
// ============================================================

///|
pub struct InflateStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
}

///|
pub fn InflateStream::new() -> InflateStream {
  { buf: [], output: [], finished: false }
}

///|
pub fn InflateStream::push(
  self : InflateStream,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.buf.push(chunk)
  if final_ {
    self.finished = true
    let input = concat_chunks(self.buf)
    let decompressed = @deflate.inflate_sync(input)
    self.output.push(decompressed)
  }
}

///|
pub fn InflateStream::result(
  self : InflateStream,
) -> FixedArray[Byte] raise @types.FlateError {
  if not(self.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  concat_chunks(self.output)
}

// ============================================================
// GzipStream - GZIP compression stream
// ============================================================

///|
pub struct GzipStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
  level : Int
  mem : Int
}

///|
pub fn GzipStream::new(level? : Int = 6, mem? : Int = 4) -> GzipStream {
  { buf: [], output: [], finished: false, level, mem }
}

///|
pub fn GzipStream::push(
  self : GzipStream,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.buf.push(chunk)
  if final_ {
    self.finished = true
    let input = concat_chunks(self.buf)
    let opts = @types.GzipOptions::{
      ..@types.GzipOptions::default(),
      level: self.level,
      mem: self.mem,
    }
    let compressed = @gzip.gzip_sync(input, opts~)
    self.output.push(compressed)
  }
}

///|
pub fn GzipStream::result(
  self : GzipStream,
) -> FixedArray[Byte] raise @types.FlateError {
  if not(self.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  concat_chunks(self.output)
}

// ============================================================
// GunzipStream - GZIP decompression stream
// ============================================================

///|
pub struct GunzipStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
}

///|
pub fn GunzipStream::new() -> GunzipStream {
  { buf: [], output: [], finished: false }
}

///|
pub fn GunzipStream::push(
  self : GunzipStream,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.buf.push(chunk)
  if final_ {
    self.finished = true
    let input = concat_chunks(self.buf)
    let decompressed = @gzip.gunzip_sync(input)
    self.output.push(decompressed)
  }
}

///|
pub fn GunzipStream::result(
  self : GunzipStream,
) -> FixedArray[Byte] raise @types.FlateError {
  if not(self.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  concat_chunks(self.output)
}

// ============================================================
// ZlibStream - Zlib compression stream
// ============================================================

///|
pub struct ZlibStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
  level : Int
  mem : Int
}

///|
pub fn ZlibStream::new(level? : Int = 6, mem? : Int = 4) -> ZlibStream {
  { buf: [], output: [], finished: false, level, mem }
}

///|
pub fn ZlibStream::push(
  self : ZlibStream,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.buf.push(chunk)
  if final_ {
    self.finished = true
    let input = concat_chunks(self.buf)
    let opts = @types.ZlibOptions::{
      ..@types.ZlibOptions::default(),
      level: self.level,
      mem: self.mem,
    }
    let compressed = @zlib.zlib_sync(input, opts~)
    self.output.push(compressed)
  }
}

///|
pub fn ZlibStream::result(
  self : ZlibStream,
) -> FixedArray[Byte] raise @types.FlateError {
  if not(self.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  concat_chunks(self.output)
}

// ============================================================
// UnzlibStream - Zlib decompression stream
// ============================================================

///|
pub struct UnzlibStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
}

///|
pub fn UnzlibStream::new() -> UnzlibStream {
  { buf: [], output: [], finished: false }
}

///|
pub fn UnzlibStream::push(
  self : UnzlibStream,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.buf.push(chunk)
  if final_ {
    self.finished = true
    let input = concat_chunks(self.buf)
    let decompressed = @zlib.unzlib_sync(input)
    self.output.push(decompressed)
  }
}

///|
pub fn UnzlibStream::result(
  self : UnzlibStream,
) -> FixedArray[Byte] raise @types.FlateError {
  if not(self.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  concat_chunks(self.output)
}

// ============================================================
// DecompressStream - Auto-detect decompression stream
// ============================================================

///|
pub struct DecompressStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
}

///|
pub fn DecompressStream::new() -> DecompressStream {
  { buf: [], output: [], finished: false }
}

///|
pub fn DecompressStream::push(
  self : DecompressStream,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.buf.push(chunk)
  if final_ {
    self.finished = true
    let input = concat_chunks(self.buf)
    let decompressed = decompress_auto(input)
    self.output.push(decompressed)
  }
}

///|
pub fn DecompressStream::result(
  self : DecompressStream,
) -> FixedArray[Byte] raise @types.FlateError {
  if not(self.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  concat_chunks(self.output)
}

///|
fn decompress_auto(
  data : FixedArray[Byte],
) -> FixedArray[Byte] raise @types.FlateError {
  if data.length() >= 2 {
    // Check for GZIP magic number
    if data[0] == b'\x1F' && data[1] == b'\x8B' {
      return @gzip.gunzip_sync(data)
    }
    // Check for valid Zlib header
    let cmf = data[0].to_int()
    let flg = data[1].to_int()
    let cm = cmf & 0x0F
    let cinfo = (cmf >> 4) & 0x0F
    if cm == 8 && cinfo <= 7 && (cmf * 256 + flg) % 31 == 0 {
      return @zlib.unzlib_sync(data)
    }
  }
  // Fall back to raw DEFLATE
  @deflate.inflate_sync(data)
}
