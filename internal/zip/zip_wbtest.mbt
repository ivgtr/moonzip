///|
fn string_to_bytes(s : String) -> FixedArray[Byte] {
  let len = s.length()
  let arr = FixedArray::make(len, b'\x00')
  let mut idx = 0
  for c in s {
    arr[idx] = c.to_int().to_byte()
    idx += 1
  }
  arr
}

///|
fn fill_bytes(value : Byte, count : Int) -> FixedArray[Byte] {
  FixedArray::make(count, value)
}

///|
fn bytes_equal(a : FixedArray[Byte], b : FixedArray[Byte]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

// === Round-trip tests ===

///|
test "zip: single file round-trip" {
  let data = string_to_bytes("Hello, ZIP!")
  let files : Array[(String, FixedArray[Byte])] = [("hello.txt", data)]
  let archive = zip_sync(files)
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  let (name, content) = result[0]
  assert_eq(name, "hello.txt")
  assert_true(bytes_equal(data, content))
}

///|
test "zip: multiple files round-trip" {
  let data1 = string_to_bytes("File one content")
  let data2 = string_to_bytes("File two content here")
  let data3 = fill_bytes(b'\xAB', 256)
  let files : Array[(String, FixedArray[Byte])] = [
    ("file1.txt", data1),
    ("dir/file2.txt", data2),
    ("binary.bin", data3),
  ]
  let archive = zip_sync(files)
  let result = unzip_sync(archive)
  assert_eq(result.length(), 3)
  let (n1, c1) = result[0]
  assert_eq(n1, "file1.txt")
  assert_true(bytes_equal(data1, c1))
  let (n2, c2) = result[1]
  assert_eq(n2, "dir/file2.txt")
  assert_true(bytes_equal(data2, c2))
  let (n3, c3) = result[2]
  assert_eq(n3, "binary.bin")
  assert_true(bytes_equal(data3, c3))
}

///|
test "zip: empty file round-trip" {
  let data : FixedArray[Byte] = []
  let files : Array[(String, FixedArray[Byte])] = [("empty.txt", data)]
  let archive = zip_sync(files)
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  let (name, content) = result[0]
  assert_eq(name, "empty.txt")
  assert_eq(content.length(), 0)
}

///|
test "zip: empty archive (no files)" {
  let files : Array[(String, FixedArray[Byte])] = []
  let archive = zip_sync(files)
  let result = unzip_sync(archive)
  assert_eq(result.length(), 0)
}

// === MS-DOS date/time tests ===

///|
test "zip: td/dt round-trip" {
  // 2023-11-14 12:30:00 UTC
  let ts = 1700000000 - 1700000000 % 2 // Ensure even seconds (DOS has 2s granularity)
  let (date, time) = td(ts)
  let recovered = dt(date, time)
  assert_eq(recovered, ts)
}

///|
test "zip: td/dt boundary 1980-01-01" {
  // 1980-01-01 00:00:00 UTC = 315532800
  let ts = 315532800
  let (date, time) = td(ts)
  let recovered = dt(date, time)
  assert_eq(recovered, ts)
  // Date should encode year=0 (1980), month=1, day=1
  let year = (date >> 9) & 0x7F
  let month = (date >> 5) & 0x0F
  let day = date & 0x1F
  assert_eq(year, 0)
  assert_eq(month, 1)
  assert_eq(day, 1)
  // Time should be 00:00:00
  assert_eq(time, 0)
}

///|
test "zip: td/dt boundary 2037-12-31" {
  // 2037-12-31 23:59:58 UTC (within 32-bit timestamp range)
  // Unix timestamp: 2145916798
  // Manually: days from 1970-01-01 to 2037-12-31
  let mut total_days = 0
  for y = 1970; y < 2037; y = y + 1 {
    let dy = if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 {
      366
    } else {
      365
    }
    total_days = total_days + dy
  }
  // Add days for Jan-Nov 2037
  let mdays : FixedArray[Int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  for m = 0; m < 11; m = m + 1 {
    total_days = total_days + mdays[m]
  }
  // Dec 31 (day 30 zero-indexed)
  total_days = total_days + 30
  let ts = total_days * 86400 + 23 * 3600 + 59 * 60 + 58
  let (date, time) = td(ts)
  let recovered = dt(date, time)
  assert_eq(recovered, ts)
}

///|
test "zip: td clamps pre-1980 timestamps" {
  // Timestamp before 1980 should be clamped to 1980-01-01
  let (date, time) = td(0)
  let recovered = dt(date, time)
  assert_eq(recovered, 315532800) // 1980-01-01 00:00:00
}

// === Header validation tests ===

///|
test "zip: local file header magic number" {
  let data = string_to_bytes("test data")
  let files : Array[(String, FixedArray[Byte])] = [("test.txt", data)]
  let archive = zip_sync(files)
  // First 4 bytes should be Local File Header signature
  assert_eq(archive[0], b'\x50')
  assert_eq(archive[1], b'\x4B')
  assert_eq(archive[2], b'\x03')
  assert_eq(archive[3], b'\x04')
}

///|
test "zip: EOCD signature present" {
  let data = string_to_bytes("test")
  let files : Array[(String, FixedArray[Byte])] = [("t.txt", data)]
  let archive = zip_sync(files)
  // Find EOCD signature by scanning from end
  let sl = archive.length()
  let mut found = false
  for i = sl - 22; i >= 0; i = i - 1 {
    if archive[i] == b'\x50' &&
      archive[i + 1] == b'\x4B' &&
      archive[i + 2] == b'\x05' &&
      archive[i + 3] == b'\x06' {
      found = true
      break
    }
  }
  assert_true(found)
}

///|
test "zip: central directory signature present" {
  let data = string_to_bytes("test")
  let files : Array[(String, FixedArray[Byte])] = [("t.txt", data)]
  let archive = zip_sync(files)
  // Find CD entry signature
  let sl = archive.length()
  let mut found = false
  for i = 0; i < sl - 4; i = i + 1 {
    if archive[i] == b'\x50' &&
      archive[i + 1] == b'\x4B' &&
      archive[i + 2] == b'\x01' &&
      archive[i + 3] == b'\x02' {
      found = true
      break
    }
  }
  assert_true(found)
}

// === Store vs Deflate tests ===

///|
test "zip: level 0 uses Store compression" {
  let data = string_to_bytes("Hello store")
  let files : Array[(String, FixedArray[Byte])] = [("store.txt", data)]
  let archive = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 0,
  })
  // Check compression method in Local File Header (offset 8-9)
  let comp = archive[8].to_int() | (archive[9].to_int() << 8)
  assert_eq(comp, 0)
  // Round-trip verification
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  let (_, content) = result[0]
  assert_true(bytes_equal(data, content))
}

///|
test "zip: level 6 uses Deflate compression" {
  let data = string_to_bytes(
    "Hello deflate test data that should be compressed",
  )
  let files : Array[(String, FixedArray[Byte])] = [("deflate.txt", data)]
  let archive = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 6,
  })
  // Check compression method in Local File Header (offset 8-9)
  let comp = archive[8].to_int() | (archive[9].to_int() << 8)
  assert_eq(comp, 8)
  // Round-trip verification
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  let (_, content) = result[0]
  assert_true(bytes_equal(data, content))
}

///|
test "zip: empty file uses Store regardless of level" {
  let data : FixedArray[Byte] = []
  let files : Array[(String, FixedArray[Byte])] = [("empty.txt", data)]
  let archive = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 9,
  })
  // Check compression method in Local File Header (offset 8-9)
  let comp = archive[8].to_int() | (archive[9].to_int() << 8)
  assert_eq(comp, 0)
}

// === UTF-8 filename tests ===

///|
test "zip: UTF-8 filename sets bit 11 flag" {
  let data = string_to_bytes("data")
  let files : Array[(String, FixedArray[Byte])] = [
    ("\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}.txt", data),
  ]
  let archive = zip_sync(files)
  // Check flags in Local File Header (offset 6-7)
  let flags = archive[6].to_int() | (archive[7].to_int() << 8)
  assert_true((flags & 0x800) != 0)
  // Round-trip should preserve the filename
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  let (name, _) = result[0]
  assert_eq(name, "\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}.txt")
}

///|
test "zip: ASCII filename does not set bit 11 flag" {
  let data = string_to_bytes("data")
  let files : Array[(String, FixedArray[Byte])] = [("ascii.txt", data)]
  let archive = zip_sync(files)
  // Check flags in Local File Header (offset 6-7)
  let flags = archive[6].to_int() | (archive[7].to_int() << 8)
  assert_true((flags & 0x800) == 0)
}

// === Error tests ===

///|
test "zip: error on invalid EOCD" {
  let data : FixedArray[Byte] = FixedArray::make(30, b'\x00')
  let mut got_error = false
  let mut error_code : @types.FlateErrorCode = @types.FlateErrorCode::UnexpectedEOF
  try {
    let _ = unzip_sync(data)
  } catch {
    @types.FlateError(code) => {
      got_error = true
      error_code = code
    }
  }
  assert_true(got_error)
  assert_eq(error_code, @types.FlateErrorCode::InvalidZipData)
}

///|
test "zip: error on truncated data" {
  // Too small for any valid ZIP
  let data : FixedArray[Byte] = [b'\x50', b'\x4B', b'\x05', b'\x06']
  let mut got_error = false
  try {
    let _ = unzip_sync(data)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "zip: error on unknown compression method" {
  // Create a valid-looking ZIP with unknown compression method
  let data = string_to_bytes("test")
  let files : Array[(String, FixedArray[Byte])] = [("test.txt", data)]
  let archive_orig = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 0,
  })
  // Tamper with compression method in local file header (offset 8)
  let archive = FixedArray::make(archive_orig.length(), b'\x00')
  for i = 0; i < archive_orig.length(); i = i + 1 {
    archive[i] = archive_orig[i]
  }
  archive[8] = b'\x05' // Unknown method = 5
  // Also tamper in central directory entry
  let sl = archive.length()
  for i = 0; i < sl - 4; i = i + 1 {
    if archive[i] == b'\x50' &&
      archive[i + 1] == b'\x4B' &&
      archive[i + 2] == b'\x01' &&
      archive[i + 3] == b'\x02' {
      // Compression method in CD entry is at offset +10
      archive[i + 10] = b'\x05'
      break
    }
  }
  let mut got_error = false
  let mut error_code : @types.FlateErrorCode = @types.FlateErrorCode::UnexpectedEOF
  try {
    let _ = unzip_sync(archive)
  } catch {
    @types.FlateError(code) => {
      got_error = true
      error_code = code
    }
  }
  assert_true(got_error)
  assert_eq(error_code, @types.FlateErrorCode::UnknownCompressionMethod)
}

// === CRC32 verification tests ===

///|
test "zip: CRC32 mismatch detected" {
  let data = string_to_bytes("Hello CRC check")
  let files : Array[(String, FixedArray[Byte])] = [("crc.txt", data)]
  let archive_orig = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 0,
  })
  // Copy and corrupt one byte of stored file data
  let archive = FixedArray::make(archive_orig.length(), b'\x00')
  for i = 0; i < archive_orig.length(); i = i + 1 {
    archive[i] = archive_orig[i]
  }
  // File data starts at offset 30 + filename_length
  // Filename is "crc.txt" = 7 chars, so data starts at 37
  let data_offset = 30 + 7
  archive[data_offset] = ((archive[data_offset].to_int() + 1) & 0xFF).to_byte()
  let mut got_error = false
  let mut error_code : @types.FlateErrorCode = @types.FlateErrorCode::UnexpectedEOF
  try {
    let _ = unzip_sync(archive)
  } catch {
    @types.FlateError(code) => {
      got_error = true
      error_code = code
    }
  }
  assert_true(got_error)
  assert_eq(error_code, @types.FlateErrorCode::InvalidZipData)
}

// === 1KB data round-trip ===

///|
test "zip: 1KB data round-trip" {
  let data = fill_bytes(b'\xCD', 1024)
  let files : Array[(String, FixedArray[Byte])] = [("large.bin", data)]
  let archive = zip_sync(files)
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  let (_, content) = result[0]
  assert_true(bytes_equal(data, content))
}

// === unzip_list tests ===

///|
test "zip: unzip_list multiple files with Store and Deflate" {
  let data1 = string_to_bytes("Hello, Store!")
  let data2 = string_to_bytes(
    "Hello deflate test data that should be compressed well enough",
  )
  let files_store : Array[(String, FixedArray[Byte])] = [("store.txt", data1)]
  let files_deflate : Array[(String, FixedArray[Byte])] = [
    ("deflate.txt", data2),
  ]
  let archive_store = zip_sync(files_store, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 0,
  })
  let archive_deflate = zip_sync(files_deflate, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 6,
  })
  // Test Store archive
  let list_store = unzip_list(archive_store)
  assert_eq(list_store.length(), 1)
  assert_eq(list_store[0].name, "store.txt")
  assert_eq(list_store[0].original_size, data1.length())
  assert_eq(list_store[0].size, data1.length())
  assert_eq(list_store[0].compression, 0)
  // Test Deflate archive
  let list_deflate = unzip_list(archive_deflate)
  assert_eq(list_deflate.length(), 1)
  assert_eq(list_deflate[0].name, "deflate.txt")
  assert_eq(list_deflate[0].original_size, data2.length())
  assert_eq(list_deflate[0].compression, 8)
  assert_true(list_deflate[0].size > 0)
}

///|
test "zip: unzip_list multiple files in single archive" {
  let data1 = string_to_bytes("File one")
  let data2 = string_to_bytes("File two content")
  let data3 = fill_bytes(b'\xAB', 100)
  let files : Array[(String, FixedArray[Byte])] = [
    ("a.txt", data1),
    ("dir/b.txt", data2),
    ("c.bin", data3),
  ]
  let archive = zip_sync(files)
  let list = unzip_list(archive)
  assert_eq(list.length(), 3)
  assert_eq(list[0].name, "a.txt")
  assert_eq(list[0].original_size, data1.length())
  assert_eq(list[1].name, "dir/b.txt")
  assert_eq(list[1].original_size, data2.length())
  assert_eq(list[2].name, "c.bin")
  assert_eq(list[2].original_size, data3.length())
}

///|
test "zip: unzip_list empty archive" {
  let files : Array[(String, FixedArray[Byte])] = []
  let archive = zip_sync(files)
  let list = unzip_list(archive)
  assert_eq(list.length(), 0)
}

// === Mtime option test ===

///|
test "zip: mtime option is written correctly" {
  let data = string_to_bytes("time test")
  let mtime = 1700000000
  let files : Array[(String, FixedArray[Byte])] = [("time.txt", data)]
  let archive = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    mtime: Some(mtime),
  })
  // Read DOS time and date from Local File Header
  let dos_time_read = archive[10].to_int() | (archive[11].to_int() << 8)
  let dos_date_read = archive[12].to_int() | (archive[13].to_int() << 8)
  let (expected_date, expected_time) = td(mtime)
  assert_eq(dos_time_read, expected_time)
  assert_eq(dos_date_read, expected_date)
}

///|
test "zip: leap year date round-trip (2000-02-29)" {
  // 2000-02-29 00:00:00 UTC = 951782400
  let ts = 951782400
  let (date, time) = td(ts)
  let recovered = dt(date, time)
  assert_eq(recovered, ts)
  // Verify month=2, day=29
  let month = (date >> 5) & 0x0F
  let day = date & 0x1F
  assert_eq(month, 2)
  assert_eq(day, 29)
}

///|
test "zip: 4-byte UTF-8 emoji filename round-trip" {
  let data = string_to_bytes("emoji content")
  let files : Array[(String, FixedArray[Byte])] = [("\u{1F4C1}test.txt", data)]
  let archive = zip_sync(files)
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  let (name, content) = result[0]
  assert_eq(name, "\u{1F4C1}test.txt")
  assert_true(bytes_equal(data, content))
}

///|
test "zip: invalid local header signature" {
  let data = string_to_bytes("test")
  let files : Array[(String, FixedArray[Byte])] = [("test.txt", data)]
  let archive_orig = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 0,
  })
  let archive = FixedArray::make(archive_orig.length(), b'\x00')
  for i = 0; i < archive_orig.length(); i = i + 1 {
    archive[i] = archive_orig[i]
  }
  // Tamper with local file header signature (first 4 bytes)
  archive[0] = b'\x00'
  let mut got_error = false
  let mut error_code : @types.FlateErrorCode = @types.FlateErrorCode::UnexpectedEOF
  try {
    let _ = unzip_sync(archive)
  } catch {
    @types.FlateError(code) => {
      got_error = true
      error_code = code
    }
  }
  assert_true(got_error)
  assert_eq(error_code, @types.FlateErrorCode::InvalidZipData)
}
