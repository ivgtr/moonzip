// ============================================================
// GZIP Compression/Decompression (RFC 1952)
// ============================================================

// ============================================================
// gzh - Write GZIP header
// ============================================================

///|
/// Write GZIP header to output buffer based on options.
/// Returns the number of bytes written.
pub fn gzh(out : FixedArray[Byte], opts : @types.GzipOptions) -> Int {
  // ID1, ID2
  out[0] = b'\x1F'
  out[1] = b'\x8B'
  // CM = 8 (deflate)
  out[2] = b'\x08'
  // Build FLG byte
  let mut flg = 0
  let has_extra = match opts.extra {
    Some(_) => true
    None => false
  }
  let has_fname = match opts.filename {
    Some(_) => true
    None => false
  }
  let has_comment = match opts.comment {
    Some(_) => true
    None => false
  }
  if has_extra {
    flg = flg | 0x04
  }
  if has_fname {
    flg = flg | 0x08
  }
  if has_comment {
    flg = flg | 0x10
  }
  out[3] = flg.to_byte()
  // MTIME (4 bytes LE)
  let mtime = match opts.mtime {
    Some(m) => m
    None => 0
  }
  out[4] = (mtime & 0xFF).to_byte()
  out[5] = ((mtime >> 8) & 0xFF).to_byte()
  out[6] = ((mtime >> 16) & 0xFF).to_byte()
  out[7] = ((mtime >> 24) & 0xFF).to_byte()
  // XFL: 2 = best compression (level >= 7), 4 = fastest (level <= 2), 0 = normal
  let level = opts.level
  let xfl = if level <= 2 { 4 } else if level >= 7 { 2 } else { 0 }
  out[8] = xfl.to_byte()
  // OS = 255 (unknown)
  out[9] = b'\xFF'
  let mut pos = 10
  // FEXTRA
  match opts.extra {
    Some(extra) => {
      let elen = extra.length()
      out[pos] = (elen & 0xFF).to_byte()
      out[pos + 1] = ((elen >> 8) & 0xFF).to_byte()
      pos = pos + 2
      for i = 0; i < elen; i = i + 1 {
        out[pos + i] = extra[i]
      }
      pos = pos + elen
    }
    None => ()
  }
  // FNAME (null-terminated)
  match opts.filename {
    Some(fname) => {
      for c in fname {
        out[pos] = c.to_int().to_byte()
        pos = pos + 1
      }
      out[pos] = b'\x00'
      pos = pos + 1
    }
    None => ()
  }
  // FCOMMENT (null-terminated)
  match opts.comment {
    Some(comment) => {
      for c in comment {
        out[pos] = c.to_int().to_byte()
        pos = pos + 1
      }
      out[pos] = b'\x00'
      pos = pos + 1
    }
    None => ()
  }
  pos
}

// ============================================================
// gzs - Parse GZIP header, return start offset of DEFLATE data
// ============================================================

///|
/// Parse GZIP header and return the byte offset where the DEFLATE
/// compressed data begins.
pub fn gzs(data : FixedArray[Byte]) -> Int raise @types.FlateError {
  let sl = data.length()
  if sl < 10 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  // Validate magic number
  if data[0] != b'\x1F' || data[1] != b'\x8B' {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
  // Validate CM = 8
  if data[2] != b'\x08' {
    raise @types.FlateError::FlateError(
      @types.FlateErrorCode::UnknownCompressionMethod,
    )
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
    if pos > sl {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
  }
  // FNAME (bit 3) - null-terminated
  if (flg & 0x08) != 0 {
    while pos < sl && data[pos] != b'\x00' {
      pos = pos + 1
    }
    if pos >= sl {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
    pos = pos + 1 // skip null terminator
  }
  // FCOMMENT (bit 4) - null-terminated
  if (flg & 0x10) != 0 {
    while pos < sl && data[pos] != b'\x00' {
      pos = pos + 1
    }
    if pos >= sl {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
    pos = pos + 1 // skip null terminator
  }
  // FHCRC (bit 1) - 2 bytes
  if (flg & 0x02) != 0 {
    pos = pos + 2
    if pos > sl {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
  }
  pos
}

// ============================================================
// gzl - Get GZIP footer info and verify
// ============================================================

///|
/// Verify the GZIP footer (CRC32 and ISIZE) against the decompressed data.
/// The footer is the last 8 bytes of the GZIP data.
pub fn gzl(
  data : FixedArray[Byte],
  decompressed : FixedArray[Byte],
) -> Unit raise @types.FlateError {
  let sl = data.length()
  if sl < 8 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  // Read CRC32 from footer (last 8 bytes, first 4 are CRC32 LE)
  let footer_start = sl - 8
  let expected_crc = data[footer_start].to_int().reinterpret_as_uint() |
    (data[footer_start + 1].to_int().reinterpret_as_uint() << 8) |
    (data[footer_start + 2].to_int().reinterpret_as_uint() << 16) |
    (data[footer_start + 3].to_int().reinterpret_as_uint() << 24)
  // Read ISIZE from footer (last 4 bytes, LE)
  let expected_isize = data[footer_start + 4].to_int() |
    (data[footer_start + 5].to_int() << 8) |
    (data[footer_start + 6].to_int() << 16) |
    (data[footer_start + 7].to_int() << 24)
  // Compute actual CRC32
  let actual_crc = @checksum.crc32(decompressed)
  if actual_crc != expected_crc {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
  // Verify ISIZE (original size mod 2^32)
  let actual_isize = decompressed.length()
  if actual_isize != expected_isize {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
}

// ============================================================
// gzip_sync - Compress data with GZIP wrapper
// ============================================================

///|
/// Compress data using GZIP format (RFC 1952).
///
/// Parameters:
///   data - Uncompressed data
///   opts - GZIP options (level, mtime, filename, etc.)
///
/// Returns complete GZIP data (header + DEFLATE + footer).
pub fn gzip_sync(
  data : FixedArray[Byte],
  opts? : @types.GzipOptions = @types.GzipOptions::default(),
) -> FixedArray[Byte] raise @types.FlateError {
  // Calculate header size
  let mut header_size = 10
  match opts.extra {
    Some(extra) => header_size = header_size + 2 + extra.length()
    None => ()
  }
  match opts.filename {
    Some(fname) => {
      let mut flen = 0
      for _c in fname {
        flen = flen + 1
      }
      header_size = header_size + flen + 1
    }
    None => ()
  }
  match opts.comment {
    Some(comment) => {
      let mut clen = 0
      for _c in comment {
        clen = clen + 1
      }
      header_size = header_size + clen + 1
    }
    None => ()
  }
  // Compress with DEFLATE
  let deflate_opts = @types.DeflateOptions::{
    level: opts.level,
    mem: opts.mem,
    dictionary: None,
  }
  let compressed = @deflate.deflate_sync(data, opts=deflate_opts)
  // Build output: header + compressed + footer (8 bytes)
  let total_size = header_size + compressed.length() + 8
  let out = FixedArray::make(total_size, b'\x00')
  // Write header
  let header_end = gzh(out, opts)
  // Copy compressed data
  for i = 0; i < compressed.length(); i = i + 1 {
    out[header_end + i] = compressed[i]
  }
  // Write footer
  let footer_start = header_end + compressed.length()
  // CRC32 (4 bytes LE)
  let crc = @checksum.crc32(data)
  out[footer_start] = (crc & 0xFFU).to_byte()
  out[footer_start + 1] = ((crc >> 8) & 0xFFU).to_byte()
  out[footer_start + 2] = ((crc >> 16) & 0xFFU).to_byte()
  out[footer_start + 3] = ((crc >> 24) & 0xFFU).to_byte()
  // ISIZE (4 bytes LE) - original size mod 2^32
  let isize = data.length()
  out[footer_start + 4] = (isize & 0xFF).to_byte()
  out[footer_start + 5] = ((isize >> 8) & 0xFF).to_byte()
  out[footer_start + 6] = ((isize >> 16) & 0xFF).to_byte()
  out[footer_start + 7] = ((isize >> 24) & 0xFF).to_byte()
  out
}

// ============================================================
// gunzip_sync - Decompress GZIP data
// ============================================================

///|
/// Decompress GZIP formatted data (RFC 1952).
///
/// Parameters:
///   data - GZIP compressed data
///
/// Returns decompressed data.
pub fn gunzip_sync(
  data : FixedArray[Byte],
) -> FixedArray[Byte] raise @types.FlateError {
  // Parse header to find DEFLATE data start
  let deflate_start = gzs(data)
  // The DEFLATE data ends 8 bytes before the end (footer)
  let deflate_end = data.length() - 8
  if deflate_end < deflate_start {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  // Extract DEFLATE data
  let deflate_len = deflate_end - deflate_start
  let deflate_data = FixedArray::make(deflate_len, b'\x00')
  for i = 0; i < deflate_len; i = i + 1 {
    deflate_data[i] = data[deflate_start + i]
  }
  // Decompress
  let decompressed = @deflate.inflate_sync(deflate_data)
  // Verify footer
  gzl(data, decompressed)
  decompressed
}
