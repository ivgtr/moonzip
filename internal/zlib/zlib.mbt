///|
/// Generate Zlib header bytes with FDICT support.
/// When a dictionary is provided, sets FDICT=1 and appends DICTID (Adler-32 of dictionary).
fn zlh_dict(level : Int, dictionary : FixedArray[Byte]?) -> FixedArray[Byte] {
  let cmf = 0x78
  let flevel = if level <= 1 {
    0
  } else if level <= 5 {
    1
  } else if level == 6 {
    2
  } else {
    3
  }
  let fdict_bit = match dictionary {
    Some(_) => 1
    None => 0
  }
  let flg_base = (flevel << 6) | (fdict_bit << 5)
  let fcheck = 31 - (cmf * 256 + flg_base) % 31
  let flg = flg_base | fcheck
  match dictionary {
    Some(d) => {
      let dict_adler = @checksum.adler32(d)
      let hdr = FixedArray::make(6, b'\x00')
      hdr[0] = cmf.to_byte()
      hdr[1] = flg.to_byte()
      hdr[2] = ((dict_adler >> 24) & 0xFFU).to_byte()
      hdr[3] = ((dict_adler >> 16) & 0xFFU).to_byte()
      hdr[4] = ((dict_adler >> 8) & 0xFFU).to_byte()
      hdr[5] = (dict_adler & 0xFFU).to_byte()
      hdr
    }
    None => [cmf.to_byte(), flg.to_byte()]
  }
}

///|
/// Compress data with Zlib wrapper (RFC 1950).
/// Writes Zlib header, DEFLATE compressed data, and Adler-32 footer (big-endian).
/// When a dictionary is provided, FDICT flag is set and DICTID is written.
pub fn zlib_sync(
  data : FixedArray[Byte],
  opts? : @types.ZlibOptions = @types.ZlibOptions::default(),
) -> FixedArray[Byte] raise @types.FlateError {
  let level = opts.level
  let header = zlh_dict(level, opts.dictionary)
  let deflate_opts : @types.DeflateOptions = {
    level: opts.level,
    mem: opts.mem,
    dictionary: opts.dictionary,
  }
  let compressed = @deflate.deflate_sync(data, opts=deflate_opts)
  let adler = @checksum.adler32(data)
  let hdr_len = header.length()
  let out_len = hdr_len + compressed.length() + 4
  let out = FixedArray::make(out_len, b'\x00')
  for i = 0; i < hdr_len; i = i + 1 {
    out[i] = header[i]
  }
  for i = 0; i < compressed.length(); i = i + 1 {
    out[hdr_len + i] = compressed[i]
  }
  let footer_offset = hdr_len + compressed.length()
  out[footer_offset] = ((adler >> 24) & 0xFFU).to_byte()
  out[footer_offset + 1] = ((adler >> 16) & 0xFFU).to_byte()
  out[footer_offset + 2] = ((adler >> 8) & 0xFFU).to_byte()
  out[footer_offset + 3] = (adler & 0xFFU).to_byte()
  out
}

///|
/// Validate Zlib header and return (data_offset, fdict_flag).
fn zls_ext(data : FixedArray[Byte]) -> (Int, Bool) raise @types.FlateError {
  if data.length() < 2 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  let cmf = data[0].to_int()
  let flg = data[1].to_int()
  let cm = cmf & 0x0F
  if cm != 8 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
  let cinfo = (cmf >> 4) & 0x0F
  if cinfo > 7 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
  if (cmf * 256 + flg) % 31 != 0 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
  }
  let fdict = (flg >> 5) & 1
  let mut offset = 2
  if fdict != 0 {
    if data.length() < 6 {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
    offset = 6
  }
  (offset, fdict != 0)
}

///|
/// Decompress Zlib-wrapped data (RFC 1950).
/// Validates header, decompresses DEFLATE payload, and verifies Adler-32 footer.
/// When dictionary is provided and FDICT is set, verifies DICTID matches
/// and passes dictionary to inflate for back-reference resolution.
pub fn unzlib_sync(
  data : FixedArray[Byte],
  opts? : @types.InflateOptions = @types.InflateOptions::default(),
) -> FixedArray[Byte] raise @types.FlateError {
  let dictionary = opts.dictionary
  let (offset, has_fdict) = zls_ext(data)
  // Validate dictionary requirement
  if has_fdict {
    match dictionary {
      None =>
        raise @types.FlateError::FlateError(
          @types.FlateErrorCode::InvalidHeader,
        )
      Some(dict) => {
        // Verify DICTID matches
        let stored_dictid = (data[2].to_uint() << 24) |
          (data[3].to_uint() << 16) |
          (data[4].to_uint() << 8) |
          data[5].to_uint()
        let expected_dictid = @checksum.adler32(dict)
        if stored_dictid != expected_dictid {
          raise @types.FlateError::FlateError(
            @types.FlateErrorCode::InvalidHeader,
          )
        }
      }
    }
  }
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
  let decompressed = @deflate.inflate_sync(payload, opts~)
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
