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

// ============================================================
// EncodeUTF8 - String to UTF-8 byte stream
// ============================================================

///|
pub struct EncodeUTF8 {
  ondata : (FixedArray[Byte], Bool) -> Unit
  mut finished : Bool
}

///|
pub fn EncodeUTF8::new(
  ondata~ : (FixedArray[Byte], Bool) -> Unit,
) -> EncodeUTF8 {
  { ondata, finished: false }
}

///|
pub fn EncodeUTF8::push(
  self : EncodeUTF8,
  chunk : String,
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  if final_ {
    self.finished = true
  }
  // Calculate byte length
  let mut byte_len = 0
  for c in chunk {
    let cp = c.to_int()
    if cp <= 0x7F {
      byte_len += 1
    } else if cp <= 0x7FF {
      byte_len += 2
    } else if cp <= 0xFFFF {
      byte_len += 3
    } else {
      byte_len += 4
    }
  }
  let result = FixedArray::make(byte_len, b'\x00')
  let mut idx = 0
  for c in chunk {
    let cp = c.to_int()
    if cp <= 0x7F {
      result[idx] = cp.to_byte()
      idx += 1
    } else if cp <= 0x7FF {
      result[idx] = (0xC0 | (cp >> 6)).to_byte()
      result[idx + 1] = (0x80 | (cp & 0x3F)).to_byte()
      idx += 2
    } else if cp <= 0xFFFF {
      result[idx] = (0xE0 | (cp >> 12)).to_byte()
      result[idx + 1] = (0x80 | ((cp >> 6) & 0x3F)).to_byte()
      result[idx + 2] = (0x80 | (cp & 0x3F)).to_byte()
      idx += 3
    } else {
      result[idx] = (0xF0 | (cp >> 18)).to_byte()
      result[idx + 1] = (0x80 | ((cp >> 12) & 0x3F)).to_byte()
      result[idx + 2] = (0x80 | ((cp >> 6) & 0x3F)).to_byte()
      result[idx + 3] = (0x80 | (cp & 0x3F)).to_byte()
      idx += 4
    }
  }
  (self.ondata)(result, final_)
}

// ============================================================
// DecodeUTF8 - UTF-8 byte stream to String
// ============================================================

///|
pub struct DecodeUTF8 {
  ondata : (String, Bool) -> Unit
  mut finished : Bool
  pending : Array[Byte]
}

///|
pub fn DecodeUTF8::new(ondata~ : (String, Bool) -> Unit) -> DecodeUTF8 {
  { ondata, finished: false, pending: [] }
}

///|
fn utf8_seq_len(b : Int) -> Int {
  if b <= 0x7F {
    1
  } else if (b & 0xE0) == 0xC0 {
    2
  } else if (b & 0xF0) == 0xE0 {
    3
  } else if (b & 0xF8) == 0xF0 {
    4
  } else {
    -1
  }
}

///|
fn is_utf8_continuation(b : Int) -> Bool {
  (b & 0xC0) == 0x80
}

///|
pub fn DecodeUTF8::push(
  self : DecodeUTF8,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  if final_ {
    self.finished = true
  }
  // Prepend any pending bytes from previous push
  let data_len = self.pending.length() + chunk.length()
  let data = FixedArray::make(data_len, b'\x00')
  for i = 0; i < self.pending.length(); i = i + 1 {
    data[i] = self.pending[i]
  }
  let pending_len = self.pending.length()
  for i = 0; i < chunk.length(); i = i + 1 {
    data[pending_len + i] = chunk[i]
  }
  self.pending.clear()
  let buf = StringBuilder::new()
  let len = data.length()
  let mut i = 0
  while i < len {
    let b0 = data[i].to_int()
    let seq_len = utf8_seq_len(b0)
    if seq_len == -1 {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
    }
    // Check if we have enough bytes for the full sequence
    if i + seq_len > len {
      // Incomplete sequence at end of chunk
      if final_ {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      // Buffer remaining bytes for next push
      for j = i; j < len; j = j + 1 {
        self.pending.push(data[j])
      }
      break
    }
    // Decode the sequence
    if seq_len == 1 {
      buf.write_char(Int::unsafe_to_char(b0))
      i += 1
    } else if seq_len == 2 {
      let b1 = data[i + 1].to_int()
      if not(is_utf8_continuation(b1)) {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      if cp < 0x80 {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      buf.write_char(Int::unsafe_to_char(cp))
      i += 2
    } else if seq_len == 3 {
      let b1 = data[i + 1].to_int()
      let b2 = data[i + 2].to_int()
      if not(is_utf8_continuation(b1)) || not(is_utf8_continuation(b2)) {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      if cp < 0x800 {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      buf.write_char(Int::unsafe_to_char(cp))
      i += 3
    } else {
      let b1 = data[i + 1].to_int()
      let b2 = data[i + 2].to_int()
      let b3 = data[i + 3].to_int()
      if not(is_utf8_continuation(b1)) ||
        not(is_utf8_continuation(b2)) ||
        not(is_utf8_continuation(b3)) {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      let cp = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      buf.write_char(Int::unsafe_to_char(cp))
      i += 4
    }
  }
  (self.ondata)(buf.to_string(), final_)
}
