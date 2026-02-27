// ============================================================
// GZIP Compression/Decompression (RFC 1952)
// ============================================================

// ============================================================
// gzh - Write GZIP header
// ============================================================

///|
/// Write GZIP header to output buffer based on options.
/// Returns the number of bytes written.
fn gzh(out : FixedArray[Byte], opts : @types.GzipOptions) -> Int {
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
/// Parse GZIP header starting at the given offset and return the byte
/// offset where the DEFLATE compressed data begins.
fn gzs_at(data : FixedArray[Byte], offset : Int) -> Int raise @types.FlateError {
  let sl = data.length()
  if offset + 10 > sl {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  // Validate magic number
  if data[offset] != b'\x1F' || data[offset + 1] != b'\x8B' {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
  // Validate CM = 8
  if data[offset + 2] != b'\x08' {
    raise @types.FlateError::FlateError(
      @types.FlateErrorCode::UnknownCompressionMethod,
    )
  }
  let flg = data[offset + 3].to_int()
  let mut pos = offset + 10
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
/// Verify the GZIP footer (CRC32 and ISIZE) at the given position.
/// Returns nothing on success, raises on mismatch.
fn gzl_at(
  data : FixedArray[Byte],
  footer_start : Int,
  decompressed : FixedArray[Byte],
) -> Unit raise @types.FlateError {
  if footer_start + 8 > data.length() {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  // Read CRC32 from footer (4 bytes LE)
  let expected_crc = data[footer_start].to_int().reinterpret_as_uint() |
    (data[footer_start + 1].to_int().reinterpret_as_uint() << 8) |
    (data[footer_start + 2].to_int().reinterpret_as_uint() << 16) |
    (data[footer_start + 3].to_int().reinterpret_as_uint() << 24)
  // Read ISIZE from footer (4 bytes LE)
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
/// Supports concatenated multi-member GZIP streams per RFC 1952 section 2.2.
///
/// Parameters:
///   data - GZIP compressed data (may contain multiple members)
///
/// Returns decompressed data (all members concatenated).
pub fn gunzip_sync(
  data : FixedArray[Byte],
  opts? : @types.InflateOptions = @types.InflateOptions::default(),
) -> FixedArray[Byte] raise @types.FlateError {
  let sl = data.length()
  let parts : Array[FixedArray[Byte]] = []
  let mut total_len = 0
  let mut offset = 0
  while offset < sl {
    // Check for GZIP magic number at current offset
    if offset + 10 > sl {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
    // Parse header to find DEFLATE data start
    let deflate_start = gzs_at(data, offset)
    // Extract DEFLATE data from current offset to end of input
    let remaining_len = sl - deflate_start
    let deflate_data = FixedArray::make(remaining_len, b'\x00')
    for i = 0; i < remaining_len; i = i + 1 {
      deflate_data[i] = data[deflate_start + i]
    }
    // Decompress and get consumed byte count
    let size_hint = match opts.size {
      Some(s) => s
      None => 0
    }
    let (decompressed, bytes_consumed) = @deflate.inflt_pos(
      deflate_data, size_hint,
    )
    // Footer position: right after the consumed DEFLATE data
    let footer_pos = deflate_start + bytes_consumed
    if footer_pos + 8 > sl {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
    // Verify CRC32 and ISIZE for this member
    gzl_at(data, footer_pos, decompressed)
    // Accumulate result
    parts.push(decompressed)
    total_len = total_len + decompressed.length()
    // Move to next member (footer is 8 bytes)
    offset = footer_pos + 8
  }
  // Concatenate all parts
  if parts.length() == 1 {
    parts[0]
  } else {
    let result = FixedArray::make(total_len, b'\x00')
    let mut pos = 0
    for part in parts {
      for i = 0; i < part.length(); i = i + 1 {
        result[pos + i] = part[i]
      }
      pos = pos + part.length()
    }
    result
  }
}
