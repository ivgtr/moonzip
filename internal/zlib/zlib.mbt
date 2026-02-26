///|
/// Generate Zlib header bytes for a given compression level.
/// Returns [CMF, FLG] where CMF uses CM=8 (deflate), CINFO=7 (32KB window),
/// and FLG encodes FLEVEL with correct FCHECK so (CMF*256+FLG) % 31 == 0.
pub fn zlh(level : Int) -> FixedArray[Byte] {
  let cmf = 0x78 // CM=8 (deflate), CINFO=7 (32KB window)
  let flevel = if level <= 1 {
    0
  } else if level <= 5 {
    1
  } else if level == 6 {
    2
  } else {
    3
  }
  let flg_base = flevel << 6
  let fcheck = 31 - (cmf * 256 + flg_base) % 31
  let flg = flg_base | fcheck
  [cmf.to_byte(), flg.to_byte()]
}

///|
/// Validate Zlib header and return data offset (number of bytes to skip).
/// Raises FlateError on invalid header.
pub fn zls(data : FixedArray[Byte]) -> Int raise @types.FlateError {
  if data.length() < 2 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  let cmf = data[0].to_int()
  let flg = data[1].to_int()
  // CM must be 8 (deflate)
  let cm = cmf & 0x0F
  if cm != 8 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
  // CINFO must be <= 7
  let cinfo = (cmf >> 4) & 0x0F
  if cinfo > 7 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
  // FCHECK: (CMF*256 + FLG) % 31 must equal 0
  if (cmf * 256 + flg) % 31 != 0 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
  // FDICT flag (bit 5 of FLG)
  let fdict = (flg >> 5) & 1
  let mut offset = 2
  if fdict != 0 {
    // 4 bytes DICTID follows
    if data.length() < 6 {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
    offset = 6
  }
  offset
}

///|
/// Compress data with Zlib wrapper (RFC 1950).
/// Writes Zlib header, DEFLATE compressed data, and Adler-32 footer (big-endian).
pub fn zlib_sync(
  data : FixedArray[Byte],
  opts? : @types.ZlibOptions = @types.ZlibOptions::default(),
) -> FixedArray[Byte] raise @types.FlateError {
  let level = opts.level
  let header = zlh(level)
  let deflate_opts = @types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: opts.level,
    mem: opts.mem,
  }
  let compressed = @deflate.deflate_sync(data, opts=deflate_opts)
  let adler = @checksum.adler32(data)
  // Output: 2 bytes header + compressed data + 4 bytes Adler-32 (big-endian)
  let out_len = 2 + compressed.length() + 4
  let out = FixedArray::make(out_len, b'\x00')
  out[0] = header[0]
  out[1] = header[1]
  for i = 0; i < compressed.length(); i = i + 1 {
    out[2 + i] = compressed[i]
  }
  // Adler-32 footer in big-endian
  let footer_offset = 2 + compressed.length()
  out[footer_offset] = ((adler >> 24) & 0xFFU).to_byte()
  out[footer_offset + 1] = ((adler >> 16) & 0xFFU).to_byte()
  out[footer_offset + 2] = ((adler >> 8) & 0xFFU).to_byte()
  out[footer_offset + 3] = (adler & 0xFFU).to_byte()
  out
}

///|
/// Decompress Zlib-wrapped data (RFC 1950).
/// Validates header, decompresses DEFLATE payload, and verifies Adler-32 footer.
pub fn unzlib_sync(
  data : FixedArray[Byte],
) -> FixedArray[Byte] raise @types.FlateError {
  let offset = zls(data)
  // Need at least offset + 4 bytes for footer
  if data.length() < offset + 4 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  // Extract DEFLATE payload (between header and 4-byte footer)
  let payload_len = data.length() - offset - 4
  let payload = FixedArray::make(payload_len, b'\x00')
  for i = 0; i < payload_len; i = i + 1 {
    payload[i] = data[offset + i]
  }
  let decompressed = @deflate.inflt(payload, 0)
  // Read and verify Adler-32 footer (big-endian)
  let footer_offset = data.length() - 4
  let stored_adler = (data[footer_offset].to_uint() << 24) |
    (data[footer_offset + 1].to_uint() << 16) |
    (data[footer_offset + 2].to_uint() << 8) |
    data[footer_offset + 3].to_uint()
  let computed_adler = @checksum.adler32(decompressed)
  if stored_adler != computed_adler {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
  decompressed
}
