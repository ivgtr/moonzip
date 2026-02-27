///|
/// Compress data using GZIP format.
/// Alias for gzip_sync, compatible with fflate's compressSync.
pub fn compress_sync(
  data : FixedArray[Byte],
  opts? : @types.GzipOptions = @types.GzipOptions::default(),
) -> FixedArray[Byte] raise @types.FlateError {
  @gzip.gzip_sync(data, opts~)
}

///|
/// Auto-detect format and decompress data.
/// Tries GZIP (0x1F 0x8B), then Zlib (valid CMF/FLG), then raw DEFLATE.
pub fn decompress_sync(
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
