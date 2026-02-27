///|
/// Compress data using GZIP format.
/// Alias for gzip_sync, compatible with fflate's compressSync.
pub fn compress_sync(
  data : FixedArray[Byte],
  opts? : @types.GzipOptions = @types.GzipOptions::default(),
) -> FixedArray[Byte] {
  @gzip.gzip_sync(data, opts~)
}

///|
/// Auto-detect format and decompress data.
/// Tries GZIP (0x1F 0x8B), then Zlib (valid CMF/FLG), then raw DEFLATE.
pub fn decompress_sync(
  data : FixedArray[Byte],
  opts? : @types.InflateOptions = @types.InflateOptions::default(),
) -> FixedArray[Byte] raise @types.FlateError {
  if data.length() >= 2 {
    // Check for GZIP magic number
    if data[0] == b'\x1F' && data[1] == b'\x8B' {
      return @gzip.gunzip_sync(data, opts~)
    }
    // Check for valid Zlib header
    let cmf = data[0].to_int()
    let flg = data[1].to_int()
    let cm = cmf & 0x0F
    let cinfo = (cmf >> 4) & 0x0F
    if cm == 8 && cinfo <= 7 && (cmf * 256 + flg) % 31 == 0 {
      return @zlib.unzlib_sync(data, opts~)
    }
  }
  // Fall back to raw DEFLATE
  @deflate.inflate_sync(data, opts~)
}

///|
/// Compress data using raw DEFLATE.
pub fn deflate_sync(
  data : FixedArray[Byte],
  opts? : @types.DeflateOptions,
) -> FixedArray[Byte] {
  @deflate.deflate_sync(data, opts?)
}

///|
/// Decompress raw DEFLATE data.
pub fn inflate_sync(
  data : FixedArray[Byte],
  opts? : @types.InflateOptions,
) -> FixedArray[Byte] raise @types.FlateError {
  @deflate.inflate_sync(data, opts?)
}

///|
/// Compress data using GZIP format.
pub fn gzip_sync(
  data : FixedArray[Byte],
  opts? : @types.GzipOptions,
) -> FixedArray[Byte] {
  @gzip.gzip_sync(data, opts?)
}

///|
/// Decompress GZIP data.
pub fn gunzip_sync(
  data : FixedArray[Byte],
  opts? : @types.InflateOptions,
) -> FixedArray[Byte] raise @types.FlateError {
  @gzip.gunzip_sync(data, opts?)
}

///|
/// Compress data using Zlib format.
pub fn zlib_sync(
  data : FixedArray[Byte],
  opts? : @types.ZlibOptions,
) -> FixedArray[Byte] {
  @zlib.zlib_sync(data, opts?)
}

///|
/// Decompress Zlib data.
pub fn unzlib_sync(
  data : FixedArray[Byte],
  opts? : @types.InflateOptions,
) -> FixedArray[Byte] raise @types.FlateError {
  @zlib.unzlib_sync(data, opts?)
}

///|
/// Create a ZIP archive from files.
pub fn zip_sync(
  files : Array[(String, FixedArray[Byte])],
  opts? : @types.ZipOptions,
  entry_opts? : Array[@types.ZipEntryOptions?],
) -> FixedArray[Byte] {
  @zip.zip_sync(files, opts?, entry_opts?)
}

///|
/// Extract files from a ZIP archive.
pub fn unzip_sync(
  data : FixedArray[Byte],
  filter? : (@types.UnzipFileInfo) -> Bool,
) -> Array[(String, FixedArray[Byte])] raise @types.FlateError {
  @zip.unzip_sync(data, filter?)
}

///|
/// List files in a ZIP archive without extracting.
pub fn unzip_list(
  data : FixedArray[Byte],
) -> Array[@types.UnzipFileInfo] raise @types.FlateError {
  @zip.unzip_list(data)
}

///|
/// Compute CRC-32 checksum.
pub fn crc32(data : FixedArray[Byte]) -> UInt {
  @checksum.crc32(data)
}

///|
/// Compute Adler-32 checksum.
pub fn adler32(data : FixedArray[Byte]) -> UInt {
  @checksum.adler32(data)
}

///|
/// Convert a string to a byte array.
/// When latin1 is true, each character is truncated to its low 8 bits (Latin-1).
/// When latin1 is false (default), full UTF-8 encoding is used.
pub fn str_to_u8(s : String, latin1? : Bool = false) -> FixedArray[Byte] {
  @utf8.str_to_u8(s, latin1~)
}

///|
/// Convert a byte array back to a string.
/// When latin1 is true, each byte is treated as a Latin-1 character.
/// When latin1 is false (default), the data is decoded as UTF-8 with validation.
pub fn str_from_u8(
  data : FixedArray[Byte],
  latin1? : Bool = false,
) -> String raise @types.FlateError {
  @utf8.str_from_u8(data, latin1~)
}
