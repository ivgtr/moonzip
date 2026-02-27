// ============================================================
// ZIP Archive Compression/Decompression (PKZIP format)
// ============================================================

// ============================================================
// MS-DOS Date/Time Conversion
// ============================================================

// Days in each month (non-leap year)

///|
let month_days : FixedArray[Int] = [
  31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
]

///|
/// Convert Unix timestamp (seconds since 1970-01-01) to MS-DOS date and time.
/// Returns (DOS date, DOS time).
/// DOS date: bits [15:9]=year-1980, [8:5]=month(1-12), [4:0]=day(1-31)
/// DOS time: bits [15:11]=hour(0-23), [10:5]=minute(0-59), [4:0]=second/2(0-29)
pub fn td(unix_ts : Int) -> (Int, Int) {
  // Handle timestamps before DOS epoch (1980-01-01)
  let ts = if unix_ts < 315532800 { 315532800 } else { unix_ts }
  // Calculate seconds within the day
  let mut remaining = ts
  let seconds_per_day = 86400
  let total_days = remaining / seconds_per_day
  let day_seconds = remaining - total_days * seconds_per_day
  let hour = day_seconds / 3600
  let minute = (day_seconds - hour * 3600) / 60
  let second = day_seconds - hour * 3600 - minute * 60
  // Calculate year, month, day from total days since 1970-01-01
  let mut year = 1970
  remaining = total_days
  while true {
    let days_in_year = if is_leap(year) { 366 } else { 365 }
    if remaining < days_in_year {
      break
    }
    remaining = remaining - days_in_year
    year = year + 1
  }
  let mut month = 1
  while month <= 12 {
    let mut dim = month_days[month - 1]
    if month == 2 && is_leap(year) {
      dim = dim + 1
    }
    if remaining < dim {
      break
    }
    remaining = remaining - dim
    month = month + 1
  }
  let day = remaining + 1
  // Encode DOS date and time
  let dos_date = ((year - 1980) << 9) | (month << 5) | day
  let dos_time = (hour << 11) | (minute << 5) | (second / 2)
  (dos_date, dos_time)
}

///|
fn is_leap(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// Convert MS-DOS date and time to Unix timestamp (seconds since 1970-01-01).
pub fn dt(date : Int, time : Int) -> Int {
  let year = ((date >> 9) & 0x7F) + 1980
  let month = (date >> 5) & 0x0F
  let day = date & 0x1F
  let hour = (time >> 11) & 0x1F
  let minute = (time >> 5) & 0x3F
  let second = (time & 0x1F) * 2
  // Count days from 1970-01-01 to the target date
  let mut total_days = 0
  for y = 1970; y < year; y = y + 1 {
    let dy = if is_leap(y) { 366 } else { 365 }
    total_days = total_days + dy
  }
  for m = 1; m < month; m = m + 1 {
    total_days = total_days + month_days[m - 1]
    if m == 2 && is_leap(year) {
      total_days = total_days + 1
    }
  }
  total_days = total_days + (day - 1)
  total_days * 86400 + hour * 3600 + minute * 60 + second
}

// ============================================================
// Check if a string contains non-ASCII characters
// ============================================================

///|
fn has_non_ascii(s : String) -> Bool {
  for c in s {
    if c.to_int() > 127 {
      return true
    }
  }
  false
}

// ============================================================
// UTF-8 string encoding
// ============================================================

///|
fn string_to_utf8(s : String) -> FixedArray[Byte] {
  // First pass: count bytes needed
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
fn utf8_to_string(
  data : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> String {
  let mut result = ""
  let mut i = offset
  let end = offset + length
  while i < end {
    let b = data[i].to_int() & 0xFF
    if b <= 0x7F {
      result = result + b.unsafe_to_char().to_string()
      i = i + 1
    } else if (b & 0xE0) == 0xC0 {
      let cp = ((b & 0x1F) << 6) | (data[i + 1].to_int() & 0x3F)
      result = result + cp.unsafe_to_char().to_string()
      i = i + 2
    } else if (b & 0xF0) == 0xE0 {
      let cp = ((b & 0x0F) << 12) |
        ((data[i + 1].to_int() & 0x3F) << 6) |
        (data[i + 2].to_int() & 0x3F)
      result = result + cp.unsafe_to_char().to_string()
      i = i + 3
    } else {
      let cp = ((b & 0x07) << 18) |
        ((data[i + 1].to_int() & 0x3F) << 12) |
        ((data[i + 2].to_int() & 0x3F) << 6) |
        (data[i + 3].to_int() & 0x3F)
      result = result + cp.unsafe_to_char().to_string()
      i = i + 4
    }
  }
  result
}

// ============================================================
// wzh - Write Local File Header
// ============================================================

///|
/// Write a Local File Header to the output buffer.
/// Returns the number of bytes written.
pub fn wzh(
  out : FixedArray[Byte],
  out_offset : Int,
  filename : FixedArray[Byte],
  compression : Int,
  crc : Int,
  compressed_size : Int,
  uncompressed_size : Int,
  dos_time : Int,
  dos_date : Int,
  flags : Int,
) -> Int {
  let o = out_offset
  // Signature: 0x04034B50
  @bits.wbytes4(out, o, 0x04034B50)
  // Version needed: 20
  @bits.wbytes2(out, o + 4, 20)
  // Flags
  @bits.wbytes2(out, o + 6, flags)
  // Compression method
  @bits.wbytes2(out, o + 8, compression)
  // ModTime
  @bits.wbytes2(out, o + 10, dos_time)
  // ModDate
  @bits.wbytes2(out, o + 12, dos_date)
  // CRC32
  @bits.wbytes4(out, o + 14, crc)
  // Compressed size
  @bits.wbytes4(out, o + 18, compressed_size)
  // Uncompressed size
  @bits.wbytes4(out, o + 22, uncompressed_size)
  // Filename length
  @bits.wbytes2(out, o + 26, filename.length())
  // Extra field length
  @bits.wbytes2(out, o + 28, 0)
  // Filename
  for i = 0; i < filename.length(); i = i + 1 {
    out[o + 30 + i] = filename[i]
  }
  30 + filename.length()
}

// ============================================================
// Write Central Directory Entry
// ============================================================

///|
fn write_cd_entry(
  out : FixedArray[Byte],
  out_offset : Int,
  filename : FixedArray[Byte],
  compression : Int,
  crc : Int,
  compressed_size : Int,
  uncompressed_size : Int,
  dos_time : Int,
  dos_date : Int,
  flags : Int,
  local_header_offset : Int,
) -> Int {
  let o = out_offset
  // Signature: 0x02014B50
  @bits.wbytes4(out, o, 0x02014B50)
  // Version made by: 20
  @bits.wbytes2(out, o + 4, 20)
  // Version needed: 20
  @bits.wbytes2(out, o + 6, 20)
  // Flags
  @bits.wbytes2(out, o + 8, flags)
  // Compression method
  @bits.wbytes2(out, o + 10, compression)
  // ModTime
  @bits.wbytes2(out, o + 12, dos_time)
  // ModDate
  @bits.wbytes2(out, o + 14, dos_date)
  // CRC32
  @bits.wbytes4(out, o + 16, crc)
  // Compressed size
  @bits.wbytes4(out, o + 20, compressed_size)
  // Uncompressed size
  @bits.wbytes4(out, o + 24, uncompressed_size)
  // Filename length
  @bits.wbytes2(out, o + 28, filename.length())
  // Extra field length
  @bits.wbytes2(out, o + 30, 0)
  // Comment length
  @bits.wbytes2(out, o + 32, 0)
  // Disk number start
  @bits.wbytes2(out, o + 34, 0)
  // Internal file attributes
  @bits.wbytes2(out, o + 36, 0)
  // External file attributes
  @bits.wbytes4(out, o + 38, 0)
  // Local header offset
  @bits.wbytes4(out, o + 42, local_header_offset)
  // Filename
  for i = 0; i < filename.length(); i = i + 1 {
    out[o + 46 + i] = filename[i]
  }
  46 + filename.length()
}

// ============================================================
// wzf - Write End of Central Directory
// ============================================================

///|
/// Write End of Central Directory record.
/// Returns the number of bytes written.
pub fn wzf(
  out : FixedArray[Byte],
  out_offset : Int,
  entry_count : Int,
  cd_size : Int,
  cd_offset : Int,
  comment : FixedArray[Byte],
) -> Int {
  let o = out_offset
  // Signature: 0x06054B50
  @bits.wbytes4(out, o, 0x06054B50)
  // Disk number: 0
  @bits.wbytes2(out, o + 4, 0)
  // CD start disk: 0
  @bits.wbytes2(out, o + 6, 0)
  // Entries on this disk
  @bits.wbytes2(out, o + 8, entry_count)
  // Total entries
  @bits.wbytes2(out, o + 10, entry_count)
  // CD size
  @bits.wbytes4(out, o + 12, cd_size)
  // CD offset
  @bits.wbytes4(out, o + 16, cd_offset)
  // Comment length
  @bits.wbytes2(out, o + 20, comment.length())
  // Comment
  for i = 0; i < comment.length(); i = i + 1 {
    out[o + 22 + i] = comment[i]
  }
  22 + comment.length()
}

// ============================================================
// zh - Parse Central Directory Entry
// ============================================================

///|
/// Parse a Central Directory entry at the given offset.
/// Returns (filename, compression, crc, compressed_size, uncompressed_size,
///          local_header_offset, entry_total_size).
pub fn zh(
  data : FixedArray[Byte],
  offset : Int,
) -> (String, Int, Int, Int, Int, Int, Int) raise @types.FlateError {
  let sl = data.length()
  if offset + 46 > sl {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  // Verify signature
  let sig = @bits.b4(data, offset)
  if sig != 0x02014B50 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidZipData)
  }
  let flags = @bits.b2(data, offset + 8)
  let compression = @bits.b2(data, offset + 10)
  let crc = @bits.b4(data, offset + 16)
  let compressed_size = @bits.b4(data, offset + 20)
  let uncompressed_size = @bits.b4(data, offset + 24)
  let filename_len = @bits.b2(data, offset + 28)
  let extra_len = @bits.b2(data, offset + 30)
  let comment_len = @bits.b2(data, offset + 32)
  let local_header_offset = @bits.b4(data, offset + 42)
  if offset + 46 + filename_len + extra_len + comment_len > sl {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  // Decode filename
  let filename = if (flags & 0x800) != 0 {
    // UTF-8 flag set
    utf8_to_string(data, offset + 46, filename_len)
  } else {
    // ASCII
    utf8_to_string(data, offset + 46, filename_len)
  }
  let entry_total_size = 46 + filename_len + extra_len + comment_len
  (
    filename, compression, crc, compressed_size, uncompressed_size, local_header_offset,
    entry_total_size,
  )
}

// ============================================================
// slzh - Parse Local File Header
// ============================================================

///|
/// Parse a Local File Header at the given offset.
/// Returns the offset where file data starts.
pub fn slzh(
  data : FixedArray[Byte],
  offset : Int,
) -> Int raise @types.FlateError {
  let sl = data.length()
  if offset + 30 > sl {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  // Verify signature
  let sig = @bits.b4(data, offset)
  if sig != 0x04034B50 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidZipData)
  }
  let filename_len = @bits.b2(data, offset + 26)
  let extra_len = @bits.b2(data, offset + 28)
  let data_start = offset + 30 + filename_len + extra_len
  if data_start > sl {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
  }
  data_start
}

// ============================================================
// zip_sync - Create ZIP Archive
// ============================================================

///|
/// Create a ZIP archive from an array of (filename, data) pairs.
///
/// Parameters:
///   files - Array of (filename, file_data) tuples
///   opts  - ZIP options (level, mtime, comment)
///
/// Returns complete ZIP archive data.
pub fn zip_sync(
  files : Array[(String, FixedArray[Byte])],
  opts? : @types.ZipOptions = @types.ZipOptions::default(),
) -> FixedArray[Byte] raise @types.FlateError {
  let level = opts.level
  let mtime = match opts.mtime {
    Some(m) => m
    None => 0
  }
  let comment_bytes = match opts.comment {
    Some(c) => string_to_utf8(c)
    None => FixedArray::make(0, b'\x00')
  }
  let (dos_date, dos_time) = td(mtime)
  // Pre-process: compute CRC, compress, encode filenames
  let num_files = files.length()
  let filename_bytes_arr : Array[FixedArray[Byte]] = []
  let compressed_arr : Array[FixedArray[Byte]] = []
  let crc_arr : Array[UInt] = []
  let method_arr : Array[Int] = []
  let orig_size_arr : Array[Int] = []
  let flags_arr : Array[Int] = []
  for i = 0; i < num_files; i = i + 1 {
    let (name, file_data) = files[i]
    let fn_bytes = string_to_utf8(name)
    filename_bytes_arr.push(fn_bytes)
    let crc = @checksum.crc32(file_data)
    crc_arr.push(crc)
    orig_size_arr.push(file_data.length())
    // Flags: bit 11 for UTF-8 if non-ASCII
    let flags = if has_non_ascii(name) { 0x800 } else { 0 }
    flags_arr.push(flags)
    if level == 0 || file_data.length() == 0 {
      // Store
      method_arr.push(0)
      compressed_arr.push(file_data)
    } else {
      // Deflate
      method_arr.push(8)
      let deflate_opts = @types.DeflateOptions::{
        level,
        mem: 4,
        dictionary: None,
      }
      let compressed = @deflate.deflate_sync(file_data, opts=deflate_opts)
      compressed_arr.push(compressed)
    }
  }
  // Calculate total output size
  let mut total_size = 0
  // Local file headers + file data
  for i = 0; i < num_files; i = i + 1 {
    total_size = total_size +
      30 +
      filename_bytes_arr[i].length() +
      compressed_arr[i].length()
  }
  // Central directory entries
  let cd_offset = total_size
  for i = 0; i < num_files; i = i + 1 {
    total_size = total_size + 46 + filename_bytes_arr[i].length()
  }
  let cd_size = total_size - cd_offset
  // EOCD
  total_size = total_size + 22 + comment_bytes.length()
  let out = FixedArray::make(total_size, b'\x00')
  // Write local file headers and file data
  let mut pos = 0
  let local_offsets : Array[Int] = []
  for i = 0; i < num_files; i = i + 1 {
    local_offsets.push(pos)
    let crc_int = crc_arr[i].reinterpret_as_int()
    let header_size = wzh(
      out,
      pos,
      filename_bytes_arr[i],
      method_arr[i],
      crc_int,
      compressed_arr[i].length(),
      orig_size_arr[i],
      dos_time,
      dos_date,
      flags_arr[i],
    )
    pos = pos + header_size
    // Copy compressed data
    let cd = compressed_arr[i]
    for j = 0; j < cd.length(); j = j + 1 {
      out[pos + j] = cd[j]
    }
    pos = pos + cd.length()
  }
  // Write central directory entries
  for i = 0; i < num_files; i = i + 1 {
    let crc_int = crc_arr[i].reinterpret_as_int()
    let entry_size = write_cd_entry(
      out,
      pos,
      filename_bytes_arr[i],
      method_arr[i],
      crc_int,
      compressed_arr[i].length(),
      orig_size_arr[i],
      dos_time,
      dos_date,
      flags_arr[i],
      local_offsets[i],
    )
    pos = pos + entry_size
  }
  // Write EOCD
  let eocd_size = wzf(out, pos, num_files, cd_size, cd_offset, comment_bytes)
  pos = pos + eocd_size
  // Trim if needed (should match total_size)
  if pos == out.length() {
    out
  } else {
    let result = FixedArray::make(pos, b'\x00')
    for i = 0; i < pos; i = i + 1 {
      result[i] = out[i]
    }
    result
  }
}

// ============================================================
// unzip_list - List ZIP Archive Contents (no decompression)
// ============================================================

///|
/// List all files in a ZIP archive without decompressing.
///
/// Parameters:
///   data - ZIP archive data
///
/// Returns array of UnzipFileInfo with name, sizes, and compression method.
pub fn unzip_list(
  data : FixedArray[Byte],
) -> Array[@types.UnzipFileInfo] raise @types.FlateError {
  let sl = data.length()
  if sl < 22 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidZipData)
  }
  // Find EOCD by scanning backwards for signature 0x06054B50
  let mut eocd_offset = -1
  let search_start = if sl - 22 - 65535 > 0 { sl - 22 - 65535 } else { 0 }
  for i = sl - 22; i >= search_start; i = i - 1 {
    if @bits.b4(data, i) == 0x06054B50 {
      eocd_offset = i
      break
    }
  }
  if eocd_offset < 0 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidZipData)
  }
  // Parse EOCD
  let entry_count = @bits.b2(data, eocd_offset + 10)
  let cd_offset = @bits.b4(data, eocd_offset + 16)
  // Parse central directory entries
  let result : Array[@types.UnzipFileInfo] = []
  let mut cd_pos = cd_offset
  for _i = 0; _i < entry_count; _i = _i + 1 {
    let (
      filename,
      compression,
      _crc,
      compressed_size,
      uncompressed_size,
      _local_header_offset,
      entry_total_size,
    ) = zh(data, cd_pos)
    cd_pos = cd_pos + entry_total_size
    result.push(
      @types.UnzipFileInfo::{
        name: filename,
        size: compressed_size,
        original_size: uncompressed_size,
        compression,
      },
    )
  }
  result
}

// ============================================================
// unzip_sync - Extract ZIP Archive
// ============================================================

///|
/// Extract all files from a ZIP archive.
///
/// Parameters:
///   data - ZIP archive data
///
/// Returns array of (filename, file_data) tuples.
pub fn unzip_sync(
  data : FixedArray[Byte],
) -> Array[(String, FixedArray[Byte])] raise @types.FlateError {
  let sl = data.length()
  if sl < 22 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidZipData)
  }
  // Find EOCD by scanning backwards for signature 0x06054B50
  let mut eocd_offset = -1
  // EOCD is at least 22 bytes from end, at most 22 + 65535 (max comment)
  let search_start = if sl - 22 - 65535 > 0 { sl - 22 - 65535 } else { 0 }
  for i = sl - 22; i >= search_start; i = i - 1 {
    if @bits.b4(data, i) == 0x06054B50 {
      eocd_offset = i
      break
    }
  }
  if eocd_offset < 0 {
    raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidZipData)
  }
  // Parse EOCD
  let entry_count = @bits.b2(data, eocd_offset + 10)
  let cd_size = @bits.b4(data, eocd_offset + 12)
  let cd_offset = @bits.b4(data, eocd_offset + 16)
  let _ = cd_size
  // Parse central directory entries
  let result : Array[(String, FixedArray[Byte])] = []
  let mut cd_pos = cd_offset
  for _i = 0; _i < entry_count; _i = _i + 1 {
    let (
      filename,
      compression,
      expected_crc,
      compressed_size,
      uncompressed_size,
      local_header_offset,
      entry_total_size,
    ) = zh(data, cd_pos)
    cd_pos = cd_pos + entry_total_size
    // Parse local file header to find data start
    let data_start = slzh(data, local_header_offset)
    if data_start + compressed_size > sl {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
    // Extract compressed data
    let file_data = if compression == 0 {
      // Store: copy directly
      let out = FixedArray::make(compressed_size, b'\x00')
      for j = 0; j < compressed_size; j = j + 1 {
        out[j] = data[data_start + j]
      }
      out
    } else if compression == 8 {
      // Deflate: decompress
      let compressed = FixedArray::make(compressed_size, b'\x00')
      for j = 0; j < compressed_size; j = j + 1 {
        compressed[j] = data[data_start + j]
      }
      @deflate.inflate_sync(compressed, opts=@types.InflateOptions::{
        size: Some(uncompressed_size),
        dictionary: None,
      })
    } else {
      raise @types.FlateError::FlateError(
        @types.FlateErrorCode::UnknownCompressionMethod,
      )
    }
    // Verify CRC32
    let actual_crc = @checksum.crc32(file_data)
    let expected_uint = expected_crc.reinterpret_as_uint()
    if actual_crc != expected_uint {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidZipData)
    }
    result.push((filename, file_data))
  }
  result
}
