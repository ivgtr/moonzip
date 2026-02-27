// ============================================================
// Streaming API for compression/decompression
// ============================================================
// Provides struct-based streaming classes that accept input
// in chunks via push() and produce output via result().
// Supports ondata callback for incremental output notification
// and flush() for forcing pending output.

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
  ondata : ((FixedArray[Byte], Bool) -> Unit)?
}

///|
pub fn DeflateStream::new(
  level? : Int = 6,
  mem? : Int = 4,
  ondata? : ((FixedArray[Byte], Bool) -> Unit)? = None,
) -> DeflateStream {
  { buf: [], output: [], finished: false, level, mem, ondata }
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
    match self.ondata {
      Some(cb) => cb(compressed, true)
      None => ()
    }
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

///|
pub fn DeflateStream::flush(
  self : DeflateStream,
) -> Unit raise @types.FlateError {
  if self.finished {
    return
  }
  if self.buf.length() == 0 {
    return
  }
  let input = concat_chunks(self.buf)
  self.buf.clear()
  if input.length() == 0 {
    return
  }
  let opts = @types.DeflateOptions::{
    level: self.level,
    mem: self.mem,
    dictionary: None,
  }
  let compressed = @deflate.deflate_sync(input, opts~)
  self.output.push(compressed)
  match self.ondata {
    Some(cb) => cb(compressed, false)
    None => ()
  }
}

// ============================================================
// InflateStream - DEFLATE decompression stream
// ============================================================

///|
pub struct InflateStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
  ondata : ((FixedArray[Byte], Bool) -> Unit)?
}

///|
pub fn InflateStream::new(
  ondata? : ((FixedArray[Byte], Bool) -> Unit)? = None,
) -> InflateStream {
  { buf: [], output: [], finished: false, ondata }
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
    match self.ondata {
      Some(cb) => cb(decompressed, true)
      None => ()
    }
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

///|
pub fn InflateStream::flush(
  self : InflateStream,
) -> Unit raise @types.FlateError {
  if self.finished {
    return
  }
  if self.buf.length() == 0 {
    return
  }
  let input = concat_chunks(self.buf)
  self.buf.clear()
  if input.length() == 0 {
    return
  }
  let decompressed = @deflate.inflate_sync(input)
  self.output.push(decompressed)
  match self.ondata {
    Some(cb) => cb(decompressed, false)
    None => ()
  }
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
  ondata : ((FixedArray[Byte], Bool) -> Unit)?
}

///|
pub fn GzipStream::new(
  level? : Int = 6,
  mem? : Int = 4,
  ondata? : ((FixedArray[Byte], Bool) -> Unit)? = None,
) -> GzipStream {
  { buf: [], output: [], finished: false, level, mem, ondata }
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
    match self.ondata {
      Some(cb) => cb(compressed, true)
      None => ()
    }
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

///|
pub fn GzipStream::flush(self : GzipStream) -> Unit raise @types.FlateError {
  if self.finished {
    return
  }
  if self.buf.length() == 0 {
    return
  }
  let input = concat_chunks(self.buf)
  self.buf.clear()
  if input.length() == 0 {
    return
  }
  let opts = @types.GzipOptions::{
    ..@types.GzipOptions::default(),
    level: self.level,
    mem: self.mem,
  }
  let compressed = @gzip.gzip_sync(input, opts~)
  self.output.push(compressed)
  match self.ondata {
    Some(cb) => cb(compressed, false)
    None => ()
  }
}

// ============================================================
// GunzipStream - GZIP decompression stream
// ============================================================

///|
pub struct GunzipStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
  ondata : ((FixedArray[Byte], Bool) -> Unit)?
  onmember : ((FixedArray[Byte]) -> Unit)?
}

///|
pub fn GunzipStream::new(
  ondata? : ((FixedArray[Byte], Bool) -> Unit)? = None,
  onmember? : ((FixedArray[Byte]) -> Unit)? = None,
) -> GunzipStream {
  { buf: [], output: [], finished: false, ondata, onmember }
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
    let all_decompressed = gunzip_multi_member(input, self.onmember)
    self.output.push(all_decompressed)
    match self.ondata {
      Some(cb) => cb(all_decompressed, true)
      None => ()
    }
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

///|
pub fn GunzipStream::flush(self : GunzipStream) -> Unit raise @types.FlateError {
  if self.finished {
    return
  }
  if self.buf.length() == 0 {
    return
  }
  let input = concat_chunks(self.buf)
  self.buf.clear()
  if input.length() == 0 {
    return
  }
  let decompressed = gunzip_multi_member(input, self.onmember)
  self.output.push(decompressed)
  match self.ondata {
    Some(cb) => cb(decompressed, false)
    None => ()
  }
}

///|
fn gunzip_multi_member(
  data : FixedArray[Byte],
  onmember : ((FixedArray[Byte]) -> Unit)?,
) -> FixedArray[Byte] raise @types.FlateError {
  let parts : Array[FixedArray[Byte]] = []
  let mut offset = 0
  while offset < data.length() {
    if offset + 10 > data.length() {
      break
    }
    if data[offset] != b'\x1F' || data[offset + 1] != b'\x8B' {
      break
    }
    // Find the exact boundary of this member first
    let member_slice = slice_bytes(data, offset, data.length() - offset)
    let header_size = gzip_header_size(member_slice)
    let member_end = find_gzip_member_end(data, offset, header_size)
    // Extract only this member's data
    let member_len = member_end - offset
    let member_data = slice_bytes(data, offset, member_len)
    let decompressed = @gzip.gunzip_sync(member_data)
    parts.push(decompressed)
    match onmember {
      Some(cb) => cb(decompressed)
      None => ()
    }
    offset = member_end
  }
  if parts.length() == 0 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  concat_chunks(parts)
}

///|
fn gzip_header_size(data : FixedArray[Byte]) -> Int raise @types.FlateError {
  let sl = data.length()
  if sl < 10 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  let flg = data[3].to_int()
  let mut pos = 10
  // FEXTRA (bit 2)
  if (flg & 0x04) != 0 {
    if pos + 2 > sl {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
    let xlen = data[pos].to_int() | (data[pos + 1].to_int() << 8)
    pos = pos + 2 + xlen
  }
  // FNAME (bit 3) - null-terminated
  if (flg & 0x08) != 0 {
    while pos < sl && data[pos] != b'\x00' {
      pos = pos + 1
    }
    pos = pos + 1
  }
  // FCOMMENT (bit 4) - null-terminated
  if (flg & 0x10) != 0 {
    while pos < sl && data[pos] != b'\x00' {
      pos = pos + 1
    }
    pos = pos + 1
  }
  // FHCRC (bit 1) - 2 bytes
  if (flg & 0x02) != 0 {
    pos = pos + 2
  }
  pos
}

///|
fn find_gzip_member_end(
  data : FixedArray[Byte],
  member_start : Int,
  header_size : Int,
) -> Int raise @types.FlateError {
  // Parse deflate blocks starting at member_start + header_size
  let deflate_start = member_start + header_size
  let mut pos = deflate_start * 8 // bit position
  let sl = data.length()
  let mut final_block = false
  while not(final_block) {
    if pos + 3 > sl * 8 {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
    let bfinal = @bits.bits(data, pos, 1)
    pos = pos + 1
    let btype = @bits.bits(data, pos, 2)
    pos = pos + 2
    if bfinal != 0 {
      final_block = true
    }
    if btype == 0 {
      // Stored block
      pos = @bits.shft(pos)
      let byte_pos = pos >> 3
      if byte_pos + 4 > sl {
        raise @types.FlateError::FlateError(
          @types.FlateErrorCode::UnexpectedEOF,
        )
      }
      let len = @bits.b2(data, byte_pos)
      pos = (byte_pos + 4 + len) * 8
    } else if btype == 1 || btype == 2 {
      // Huffman coded block - need to decode to find end
      let flrm = @huffman.flrm
      let fdrm = @huffman.fdrm
      let mut lmap : FixedArray[Int] = flrm
      let mut dmap : FixedArray[Int] = fdrm
      let mut lbits = 9
      let mut dbits = 5
      if btype == 2 {
        // Parse dynamic Huffman tables
        let hlit = @bits.bits(data, pos, 5) + 257
        pos = pos + 5
        let hdist = @bits.bits(data, pos, 5) + 1
        pos = pos + 5
        let hclen = @bits.bits(data, pos, 4) + 4
        pos = pos + 4
        let clt : FixedArray[Int] = FixedArray::make(19, 0)
        for i = 0; i < hclen; i = i + 1 {
          clt[@huffman.clim[i]] = @bits.bits(data, pos, 3)
          pos = pos + 3
        }
        let clb = @huffman.max_bits(clt)
        if clb == 0 {
          raise @types.FlateError::FlateError(
            @types.FlateErrorCode::InvalidLengthLiteral,
          )
        }
        let clm = @huffman.h_map(clt, clb, @huffman.Reverse)
        let tl = hlit + hdist
        let ldt : FixedArray[Int] = FixedArray::make(tl, 0)
        let mut i = 0
        while i < tl {
          let r = clm[@bits.bits(data, pos, clb)]
          let s = r >> 4
          let b = r & 15
          pos = pos + b
          if s < 16 {
            ldt[i] = s
            i = i + 1
          } else if s == 16 {
            let rep = 3 + @bits.bits(data, pos, 2)
            pos = pos + 2
            let prev_val = if i > 0 { ldt[i - 1] } else { 0 }
            for _j = 0; _j < rep; _j = _j + 1 {
              ldt[i] = prev_val
              i = i + 1
            }
          } else if s == 17 {
            let rep = 3 + @bits.bits(data, pos, 3)
            pos = pos + 3
            for _j = 0; _j < rep; _j = _j + 1 {
              ldt[i] = 0
              i = i + 1
            }
          } else {
            let rep = 11 + @bits.bits(data, pos, 7)
            pos = pos + 7
            for _j = 0; _j < rep; _j = _j + 1 {
              ldt[i] = 0
              i = i + 1
            }
          }
        }
        let lt : FixedArray[Int] = FixedArray::make(hlit, 0)
        for j = 0; j < hlit; j = j + 1 {
          lt[j] = ldt[j]
        }
        let dt : FixedArray[Int] = FixedArray::make(hdist, 0)
        for j = 0; j < hdist; j = j + 1 {
          dt[j] = ldt[hlit + j]
        }
        lbits = @huffman.max_bits(lt)
        dbits = @huffman.max_bits(dt)
        if lbits == 0 {
          raise @types.FlateError::FlateError(
            @types.FlateErrorCode::InvalidLengthLiteral,
          )
        }
        lmap = @huffman.h_map(lt, lbits, @huffman.Reverse)
        if dbits > 0 {
          dmap = @huffman.h_map(dt, dbits, @huffman.Reverse)
        }
      }
      // Decode symbols until EOB
      let mut done = false
      while not(done) {
        let r = lmap[@bits.bits(data, pos, lbits)]
        let sym = r >> 4
        let blen = r & 15
        if blen == 0 {
          raise @types.FlateError::FlateError(
            @types.FlateErrorCode::InvalidLengthLiteral,
          )
        }
        pos = pos + blen
        if sym == 256 {
          done = true
        } else if sym > 256 {
          let lc = sym - 257
          let add_bits = @huffman.fleb[lc]
          if add_bits > 0 {
            pos = pos + add_bits
          }
          if dbits == 0 {
            raise @types.FlateError::FlateError(
              @types.FlateErrorCode::InvalidDistance,
            )
          }
          let dr = dmap[@bits.bits(data, pos, dbits)]
          let dsym = dr >> 4
          let dblen = dr & 15
          if dblen == 0 {
            raise @types.FlateError::FlateError(
              @types.FlateErrorCode::InvalidDistance,
            )
          }
          pos = pos + dblen
          let dadd_bits = @huffman.fdeb[dsym]
          if dadd_bits > 0 {
            pos = pos + dadd_bits
          }
        }
      }
    } else {
      raise @types.FlateError::FlateError(
        @types.FlateErrorCode::InvalidBlockType,
      )
    }
  }
  // pos is now the bit position after the last block
  let byte_pos = (pos + 7) >> 3
  // 8 bytes footer (CRC32 + ISIZE)
  byte_pos + 8
}

///|
fn slice_bytes(
  data : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> FixedArray[Byte] {
  let result = FixedArray::make(length, b'\x00')
  for i = 0; i < length; i = i + 1 {
    result[i] = data[offset + i]
  }
  result
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
  ondata : ((FixedArray[Byte], Bool) -> Unit)?
}

///|
pub fn ZlibStream::new(
  level? : Int = 6,
  mem? : Int = 4,
  ondata? : ((FixedArray[Byte], Bool) -> Unit)? = None,
) -> ZlibStream {
  { buf: [], output: [], finished: false, level, mem, ondata }
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
    match self.ondata {
      Some(cb) => cb(compressed, true)
      None => ()
    }
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

///|
pub fn ZlibStream::flush(self : ZlibStream) -> Unit raise @types.FlateError {
  if self.finished {
    return
  }
  if self.buf.length() == 0 {
    return
  }
  let input = concat_chunks(self.buf)
  self.buf.clear()
  if input.length() == 0 {
    return
  }
  let opts = @types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: self.level,
    mem: self.mem,
  }
  let compressed = @zlib.zlib_sync(input, opts~)
  self.output.push(compressed)
  match self.ondata {
    Some(cb) => cb(compressed, false)
    None => ()
  }
}

// ============================================================
// UnzlibStream - Zlib decompression stream
// ============================================================

///|
pub struct UnzlibStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
  ondata : ((FixedArray[Byte], Bool) -> Unit)?
}

///|
pub fn UnzlibStream::new(
  ondata? : ((FixedArray[Byte], Bool) -> Unit)? = None,
) -> UnzlibStream {
  { buf: [], output: [], finished: false, ondata }
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
    match self.ondata {
      Some(cb) => cb(decompressed, true)
      None => ()
    }
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

///|
pub fn UnzlibStream::flush(self : UnzlibStream) -> Unit raise @types.FlateError {
  if self.finished {
    return
  }
  if self.buf.length() == 0 {
    return
  }
  let input = concat_chunks(self.buf)
  self.buf.clear()
  if input.length() == 0 {
    return
  }
  let decompressed = @zlib.unzlib_sync(input)
  self.output.push(decompressed)
  match self.ondata {
    Some(cb) => cb(decompressed, false)
    None => ()
  }
}

// ============================================================
// DecompressStream - Auto-detect decompression stream
// ============================================================

///|
pub struct DecompressStream {
  buf : Array[FixedArray[Byte]]
  output : Array[FixedArray[Byte]]
  mut finished : Bool
  ondata : ((FixedArray[Byte], Bool) -> Unit)?
}

///|
pub fn DecompressStream::new(
  ondata? : ((FixedArray[Byte], Bool) -> Unit)? = None,
) -> DecompressStream {
  { buf: [], output: [], finished: false, ondata }
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
    match self.ondata {
      Some(cb) => cb(decompressed, true)
      None => ()
    }
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
pub fn DecompressStream::flush(
  self : DecompressStream,
) -> Unit raise @types.FlateError {
  if self.finished {
    return
  }
  if self.buf.length() == 0 {
    return
  }
  let input = concat_chunks(self.buf)
  self.buf.clear()
  if input.length() == 0 {
    return
  }
  let decompressed = decompress_auto(input)
  self.output.push(decompressed)
  match self.ondata {
    Some(cb) => cb(decompressed, false)
    None => ()
  }
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
// ZipPassThrough - ZIP entry with no compression (store)
// ============================================================

///|
pub struct ZipPassThrough {
  filename : String
  buf : Array[FixedArray[Byte]]
  mut crc_state : UInt
  mut size : Int
  mut finished : Bool
  mtime : Int
  ondata : ((FixedArray[Byte], Bool) -> Unit)?
}

///|
pub fn ZipPassThrough::new(
  filename : String,
  mtime? : Int = 0,
  ondata? : ((FixedArray[Byte], Bool) -> Unit)? = None,
) -> ZipPassThrough {
  {
    filename,
    buf: [],
    crc_state: 0xFFFFFFFFU,
    size: 0,
    finished: false,
    mtime,
    ondata,
  }
}

///|
pub fn ZipPassThrough::push(
  self : ZipPassThrough,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.buf.push(chunk)
  self.crc_state = @checksum.crc32_update(self.crc_state, chunk)
  self.size = self.size + chunk.length()
  if final_ {
    self.finished = true
    let data = concat_chunks(self.buf)
    match self.ondata {
      Some(cb) => cb(data, true)
      None => ()
    }
  }
}

///|
pub fn ZipPassThrough::result(
  self : ZipPassThrough,
) -> FixedArray[Byte] raise @types.FlateError {
  if not(self.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  concat_chunks(self.buf)
}

///|
pub fn ZipPassThrough::crc(self : ZipPassThrough) -> UInt {
  self.crc_state ^ 0xFFFFFFFFU
}

///|
pub fn ZipPassThrough::size(self : ZipPassThrough) -> Int {
  self.size
}

// ============================================================
// ZipDeflate - ZIP entry with DEFLATE compression
// ============================================================

///|
pub struct ZipDeflate {
  filename : String
  buf : Array[FixedArray[Byte]]
  mut crc_state : UInt
  mut original_size : Int
  mut finished : Bool
  level : Int
  mem : Int
  mtime : Int
  ondata : ((FixedArray[Byte], Bool) -> Unit)?
}

///|
pub fn ZipDeflate::new(
  filename : String,
  level? : Int = 6,
  mem? : Int = 4,
  mtime? : Int = 0,
  ondata? : ((FixedArray[Byte], Bool) -> Unit)? = None,
) -> ZipDeflate {
  {
    filename,
    buf: [],
    crc_state: 0xFFFFFFFFU,
    original_size: 0,
    finished: false,
    level,
    mem,
    mtime,
    ondata,
  }
}

///|
pub fn ZipDeflate::push(
  self : ZipDeflate,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.buf.push(chunk)
  self.crc_state = @checksum.crc32_update(self.crc_state, chunk)
  self.original_size = self.original_size + chunk.length()
  if final_ {
    self.finished = true
    let data = concat_chunks(self.buf)
    let opts = @types.DeflateOptions::{
      level: self.level,
      mem: self.mem,
      dictionary: None,
    }
    let compressed = @deflate.deflate_sync(data, opts~)
    match self.ondata {
      Some(cb) => cb(compressed, true)
      None => ()
    }
  }
}

///|
pub fn ZipDeflate::compressed_result(
  self : ZipDeflate,
) -> FixedArray[Byte] raise @types.FlateError {
  if not(self.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  let data = concat_chunks(self.buf)
  let opts = @types.DeflateOptions::{
    level: self.level,
    mem: self.mem,
    dictionary: None,
  }
  @deflate.deflate_sync(data, opts~)
}

///|
pub fn ZipDeflate::crc(self : ZipDeflate) -> UInt {
  self.crc_state ^ 0xFFFFFFFFU
}

///|
pub fn ZipDeflate::original_size(self : ZipDeflate) -> Int {
  self.original_size
}

// ============================================================
// Zip - Streaming ZIP archive creation
// ============================================================

///|
pub struct Zip {
  entries : Array[ZipEntry]
  mut finished : Bool
  comment : String
  ondata : ((FixedArray[Byte], Bool) -> Unit)?
}

///|
struct ZipEntry {
  filename : String
  data : FixedArray[Byte]
  compressed_data : FixedArray[Byte]
  crc : UInt
  compression : Int
  original_size : Int
  mtime : Int
}

///|
pub fn Zip::new(
  comment? : String = "",
  ondata? : ((FixedArray[Byte], Bool) -> Unit)? = None,
) -> Zip {
  { entries: [], finished: false, comment, ondata }
}

///|
pub fn Zip::add_passthrough(
  self : Zip,
  pt : ZipPassThrough,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  if not(pt.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinishing)
  }
  let data = pt.result()
  self.entries.push({
    filename: pt.filename,
    data,
    compressed_data: data,
    crc: pt.crc(),
    compression: 0,
    original_size: pt.size,
    mtime: pt.mtime,
  })
}

///|
pub fn Zip::add_deflate(
  self : Zip,
  zd : ZipDeflate,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  if not(zd.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinishing)
  }
  let compressed = zd.compressed_result()
  self.entries.push({
    filename: zd.filename,
    data: concat_chunks(zd.buf),
    compressed_data: compressed,
    crc: zd.crc(),
    compression: 8,
    original_size: zd.original_size,
    mtime: zd.mtime,
  })
}

///|
pub fn Zip::finish(self : Zip) -> FixedArray[Byte] raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.finished = true
  let files : Array[(String, FixedArray[Byte])] = []
  for i = 0; i < self.entries.length(); i = i + 1 {
    let entry = self.entries[i]
    files.push((entry.filename, entry.data))
  }
  let opts = @types.ZipOptions::{
    level: 6,
    mtime: None,
    comment: if self.comment == "" {
      None
    } else {
      Some(self.comment)
    },
  }
  // Build using individual entry info for proper CRC/compression
  let result = build_zip(self.entries, self.comment)
  match self.ondata {
    Some(cb) => cb(result, true)
    None => ()
  }
  let _ = opts
  result
}

///|
fn has_non_ascii(s : String) -> Bool {
  for c in s {
    if c.to_int() > 127 {
      return true
    }
  }
  false
}

///|
fn string_to_utf8(s : String) -> FixedArray[Byte] {
  let mut byte_count = 0
  for c in s {
    let cp = c.to_int()
    if cp <= 0x7F {
      byte_count = byte_count + 1
    } else if cp <= 0x7FF {
      byte_count = byte_count + 2
    } else if cp <= 0xFFFF {
      byte_count = byte_count + 3
    } else {
      byte_count = byte_count + 4
    }
  }
  let buf = FixedArray::make(byte_count, b'\x00')
  let mut pos = 0
  for c in s {
    let cp = c.to_int()
    if cp <= 0x7F {
      buf[pos] = cp.to_byte()
      pos = pos + 1
    } else if cp <= 0x7FF {
      buf[pos] = (0xC0 | (cp >> 6)).to_byte()
      buf[pos + 1] = (0x80 | (cp & 0x3F)).to_byte()
      pos = pos + 2
    } else if cp <= 0xFFFF {
      buf[pos] = (0xE0 | (cp >> 12)).to_byte()
      buf[pos + 1] = (0x80 | ((cp >> 6) & 0x3F)).to_byte()
      buf[pos + 2] = (0x80 | (cp & 0x3F)).to_byte()
      pos = pos + 3
    } else {
      buf[pos] = (0xF0 | (cp >> 18)).to_byte()
      buf[pos + 1] = (0x80 | ((cp >> 12) & 0x3F)).to_byte()
      buf[pos + 2] = (0x80 | ((cp >> 6) & 0x3F)).to_byte()
      buf[pos + 3] = (0x80 | (cp & 0x3F)).to_byte()
      pos = pos + 4
    }
  }
  buf
}

///|
fn td(unix_ts : Int) -> (Int, Int) {
  let ts = if unix_ts < 315532800 { 315532800 } else { unix_ts }
  let seconds_per_day = 86400
  let total_days = ts / seconds_per_day
  let day_seconds = ts - total_days * seconds_per_day
  let hour = day_seconds / 3600
  let minute = (day_seconds - hour * 3600) / 60
  let second = day_seconds - hour * 3600 - minute * 60
  let month_days : FixedArray[Int] = [
    31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
  ]
  let mut year = 1970
  let mut remaining = total_days
  while true {
    let days_in_year = if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 {
      366
    } else {
      365
    }
    if remaining < days_in_year {
      break
    }
    remaining = remaining - days_in_year
    year = year + 1
  }
  let mut month = 1
  while month <= 12 {
    let mut dim = month_days[month - 1]
    if month == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) {
      dim = dim + 1
    }
    if remaining < dim {
      break
    }
    remaining = remaining - dim
    month = month + 1
  }
  let day = remaining + 1
  let dos_date = ((year - 1980) << 9) | (month << 5) | day
  let dos_time = (hour << 11) | (minute << 5) | (second / 2)
  (dos_date, dos_time)
}

///|
fn build_zip(entries : Array[ZipEntry], comment : String) -> FixedArray[Byte] {
  let num_files = entries.length()
  let comment_bytes = string_to_utf8(comment)
  // Pre-process filenames
  let filename_bytes_arr : Array[FixedArray[Byte]] = []
  let flags_arr : Array[Int] = []
  let dos_dates : Array[Int] = []
  let dos_times : Array[Int] = []
  for i = 0; i < num_files; i = i + 1 {
    let entry = entries[i]
    filename_bytes_arr.push(string_to_utf8(entry.filename))
    flags_arr.push(if has_non_ascii(entry.filename) { 0x800 } else { 0 })
    let (dd, dt) = td(entry.mtime)
    dos_dates.push(dd)
    dos_times.push(dt)
  }
  // Calculate total output size
  let mut total_size = 0
  for i = 0; i < num_files; i = i + 1 {
    total_size = total_size +
      30 +
      filename_bytes_arr[i].length() +
      entries[i].compressed_data.length()
  }
  let cd_offset = total_size
  for i = 0; i < num_files; i = i + 1 {
    total_size = total_size + 46 + filename_bytes_arr[i].length()
  }
  let cd_size = total_size - cd_offset
  total_size = total_size + 22 + comment_bytes.length()
  let out = FixedArray::make(total_size, b'\x00')
  // Write local file headers and file data
  let mut pos = 0
  let local_offsets : Array[Int] = []
  for i = 0; i < num_files; i = i + 1 {
    let entry = entries[i]
    local_offsets.push(pos)
    let crc_int = entry.crc.reinterpret_as_int()
    // Local file header
    @bits.wbytes4(out, pos, 0x04034B50)
    @bits.wbytes2(out, pos + 4, 20)
    @bits.wbytes2(out, pos + 6, flags_arr[i])
    @bits.wbytes2(out, pos + 8, entry.compression)
    @bits.wbytes2(out, pos + 10, dos_times[i])
    @bits.wbytes2(out, pos + 12, dos_dates[i])
    @bits.wbytes4(out, pos + 14, crc_int)
    @bits.wbytes4(out, pos + 18, entry.compressed_data.length())
    @bits.wbytes4(out, pos + 22, entry.original_size)
    @bits.wbytes2(out, pos + 26, filename_bytes_arr[i].length())
    @bits.wbytes2(out, pos + 28, 0)
    let fn_bytes = filename_bytes_arr[i]
    for j = 0; j < fn_bytes.length(); j = j + 1 {
      out[pos + 30 + j] = fn_bytes[j]
    }
    pos = pos + 30 + fn_bytes.length()
    // Copy compressed data
    let cd = entry.compressed_data
    for j = 0; j < cd.length(); j = j + 1 {
      out[pos + j] = cd[j]
    }
    pos = pos + cd.length()
  }
  // Write central directory
  for i = 0; i < num_files; i = i + 1 {
    let entry = entries[i]
    let crc_int = entry.crc.reinterpret_as_int()
    @bits.wbytes4(out, pos, 0x02014B50)
    @bits.wbytes2(out, pos + 4, 20)
    @bits.wbytes2(out, pos + 6, 20)
    @bits.wbytes2(out, pos + 8, flags_arr[i])
    @bits.wbytes2(out, pos + 10, entry.compression)
    @bits.wbytes2(out, pos + 12, dos_times[i])
    @bits.wbytes2(out, pos + 14, dos_dates[i])
    @bits.wbytes4(out, pos + 16, crc_int)
    @bits.wbytes4(out, pos + 20, entry.compressed_data.length())
    @bits.wbytes4(out, pos + 24, entry.original_size)
    @bits.wbytes2(out, pos + 28, filename_bytes_arr[i].length())
    @bits.wbytes2(out, pos + 30, 0)
    @bits.wbytes2(out, pos + 32, 0)
    @bits.wbytes2(out, pos + 34, 0)
    @bits.wbytes2(out, pos + 36, 0)
    @bits.wbytes4(out, pos + 38, 0)
    @bits.wbytes4(out, pos + 42, local_offsets[i])
    let fn_bytes = filename_bytes_arr[i]
    for j = 0; j < fn_bytes.length(); j = j + 1 {
      out[pos + 46 + j] = fn_bytes[j]
    }
    pos = pos + 46 + fn_bytes.length()
  }
  // Write EOCD
  @bits.wbytes4(out, pos, 0x06054B50)
  @bits.wbytes2(out, pos + 4, 0)
  @bits.wbytes2(out, pos + 6, 0)
  @bits.wbytes2(out, pos + 8, num_files)
  @bits.wbytes2(out, pos + 10, num_files)
  @bits.wbytes4(out, pos + 12, cd_size)
  @bits.wbytes4(out, pos + 16, cd_offset)
  @bits.wbytes2(out, pos + 20, comment_bytes.length())
  for i = 0; i < comment_bytes.length(); i = i + 1 {
    out[pos + 22 + i] = comment_bytes[i]
  }
  out
}

// ============================================================
// Unzip - Streaming ZIP archive extraction
// ============================================================

///|
pub struct Unzip {
  buf : Array[FixedArray[Byte]]
  mut finished : Bool
  onfile : ((String, FixedArray[Byte]) -> Unit)?
}

///|
pub fn Unzip::new(
  onfile? : ((String, FixedArray[Byte]) -> Unit)? = None,
) -> Unzip {
  { buf: [], finished: false, onfile }
}

///|
pub fn Unzip::push(
  self : Unzip,
  chunk : FixedArray[Byte],
  final_ : Bool,
) -> Unit raise @types.FlateError {
  if self.finished {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  self.buf.push(chunk)
  if final_ {
    self.finished = true
    let data = concat_chunks(self.buf)
    let files = @zip.unzip_sync(data)
    match self.onfile {
      Some(cb) =>
        for i = 0; i < files.length(); i = i + 1 {
          let (name, file_data) = files[i]
          cb(name, file_data)
        }
      None => ()
    }
  }
}

///|
pub fn Unzip::result(
  self : Unzip,
) -> Array[(String, FixedArray[Byte])] raise @types.FlateError {
  if not(self.finished) {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::StreamFinished)
  }
  let data = concat_chunks(self.buf)
  @zip.unzip_sync(data)
}
