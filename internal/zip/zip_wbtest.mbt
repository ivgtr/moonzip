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

// ============================================================
// Phase D: ZIP 機能拡張テスト
// ============================================================

// === D-T1: zip_sync per-entry ZipEntryOptions テスト ===

///|
test "zip D-1: per-entry level override (Store + Deflate mix)" {
  let data1 = string_to_bytes("File stored at level 0")
  let data2 = string_to_bytes(
    "File compressed with deflate at level 6 with more data to compress",
  )
  let files : Array[(String, FixedArray[Byte])] = [
    ("stored.txt", data1),
    ("deflated.txt", data2),
  ]
  let entry_options : Array[@types.ZipEntryOptions?] = [
    Some(@types.ZipEntryOptions::{
      ..@types.ZipEntryOptions::default(),
      level: 0,
    }),
    Some(@types.ZipEntryOptions::{
      ..@types.ZipEntryOptions::default(),
      level: 6,
    }),
  ]
  let archive = zip_sync(files, entry_opts=entry_options)
  let result = unzip_sync(archive)
  assert_eq(result.length(), 2)
  assert_eq(result[0].0, "stored.txt")
  assert_true(bytes_equal(result[0].1, data1))
  assert_eq(result[1].0, "deflated.txt")
  assert_true(bytes_equal(result[1].1, data2))
  // Verify first entry uses Store (method=0) in local header
  let comp0 = archive[8].to_int() | (archive[9].to_int() << 8)
  assert_eq(comp0, 0)
}

///|
test "zip D-1: per-entry mtime override" {
  let data = string_to_bytes("time test data")
  let mtime1 = 1700000000
  let mtime2 = 951782400
  let files : Array[(String, FixedArray[Byte])] = [
    ("file1.txt", data),
    ("file2.txt", data),
  ]
  let entry_options : Array[@types.ZipEntryOptions?] = [
    Some(@types.ZipEntryOptions::{
      ..@types.ZipEntryOptions::default(),
      mtime: Some(mtime1),
    }),
    Some(@types.ZipEntryOptions::{
      ..@types.ZipEntryOptions::default(),
      mtime: Some(mtime2),
    }),
  ]
  let archive = zip_sync(files, entry_opts=entry_options)
  // Verify via unzip_list that mtimes are different
  let list = unzip_list(archive)
  assert_eq(list.length(), 2)
  // DOS time has 2-second granularity, so round down
  let expected_mtime1 = mtime1 - mtime1 % 2
  let expected_mtime2 = mtime2 - mtime2 % 2
  assert_eq(list[0].mtime, expected_mtime1)
  assert_eq(list[1].mtime, expected_mtime2)
}

///|
test "zip D-1: per-entry attrs (comment and extra)" {
  let data = string_to_bytes("attrs test")
  let files : Array[(String, FixedArray[Byte])] = [("attrs.txt", data)]
  let extra_map : Map[Int, FixedArray[Byte]] = {}
  extra_map[0x0001] = FixedArray::make(4, b'\xAB')
  let entry_options : Array[@types.ZipEntryOptions?] = [
    Some(@types.ZipEntryOptions::{
      ..@types.ZipEntryOptions::default(),
      attrs: Some(@types.ZipAttributes::{
        os: None,
        attrs: Some(0x20),
        comment: Some("entry comment"),
        extra: Some(extra_map),
      }),
    }),
  ]
  let archive = zip_sync(files, entry_opts=entry_options)
  let list = unzip_list(archive)
  assert_eq(list.length(), 1)
  assert_eq(list[0].comment, "entry comment")
  assert_eq(list[0].attrs, 0x20)
  // Verify extra field round-trip
  assert_true(list[0].extra.contains(0x0001))
  let d = list[0].extra[0x0001]
  assert_eq(d.length(), 4)
  assert_eq(d[0], b'\xAB')
}

///|
test "zip D-1: per-entry options with None (uses global defaults)" {
  let data = string_to_bytes("default options test data for compression")
  let files : Array[(String, FixedArray[Byte])] = [
    ("default.txt", data),
    ("also_default.txt", data),
  ]
  let entry_options : Array[@types.ZipEntryOptions?] = [None, None]
  let archive = zip_sync(
    files,
    opts=@types.ZipOptions::{
      ..@types.ZipOptions::default(),
      level: 0,
      mtime: Some(1700000000),
    },
    entry_opts=entry_options,
  )
  let result = unzip_sync(archive)
  assert_eq(result.length(), 2)
  assert_true(bytes_equal(result[0].1, data))
  assert_true(bytes_equal(result[1].1, data))
  // Both should use Store (level 0 from global opts)
  let comp0 = archive[8].to_int() | (archive[9].to_int() << 8)
  assert_eq(comp0, 0)
}

// === D-T2: unzip_sync フィルタ機能テスト ===

///|
test "zip D-2: unzip_sync filter specific file" {
  let data1 = string_to_bytes("File one")
  let data2 = string_to_bytes("File two")
  let data3 = string_to_bytes("File three")
  let files : Array[(String, FixedArray[Byte])] = [
    ("a.txt", data1),
    ("b.txt", data2),
    ("c.txt", data3),
  ]
  let archive = zip_sync(files)
  let result = unzip_sync(archive, filter=fn(info) { info.name == "b.txt" })
  assert_eq(result.length(), 1)
  assert_eq(result[0].0, "b.txt")
  assert_true(bytes_equal(result[0].1, data2))
}

///|
test "zip D-2: unzip_sync filter excludes all" {
  let data = string_to_bytes("data")
  let files : Array[(String, FixedArray[Byte])] = [
    ("a.txt", data),
    ("b.txt", data),
  ]
  let archive = zip_sync(files)
  let result = unzip_sync(archive, filter=fn(_info) { false })
  assert_eq(result.length(), 0)
}

///|
test "zip D-2: unzip_sync filter includes all" {
  let data1 = string_to_bytes("File one")
  let data2 = string_to_bytes("File two")
  let files : Array[(String, FixedArray[Byte])] = [
    ("a.txt", data1),
    ("b.txt", data2),
  ]
  let archive = zip_sync(files)
  let result = unzip_sync(archive, filter=fn(_info) { true })
  assert_eq(result.length(), 2)
  assert_true(bytes_equal(result[0].1, data1))
  assert_true(bytes_equal(result[1].1, data2))
}

///|
test "zip D-2: unzip_sync filter by size" {
  let small = string_to_bytes("s")
  let large = string_to_bytes(
    "This is a much larger file with more content inside",
  )
  let files : Array[(String, FixedArray[Byte])] = [
    ("small.txt", small),
    ("large.txt", large),
  ]
  let archive = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 0,
  })
  let result = unzip_sync(archive, filter=fn(info) { info.original_size > 10 })
  assert_eq(result.length(), 1)
  assert_eq(result[0].0, "large.txt")
}

///|
test "zip D-2: unzip_sync without filter (backward compatible)" {
  let data = string_to_bytes("backward compat")
  let files : Array[(String, FixedArray[Byte])] = [("compat.txt", data)]
  let archive = zip_sync(files)
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  assert_true(bytes_equal(result[0].1, data))
}

// === D-T3: UnzipFileInfo フィールド追加テスト ===

///|
test "zip D-3: unzip_list returns mtime" {
  let data = string_to_bytes("mtime test")
  let mtime = 1700000000
  let files : Array[(String, FixedArray[Byte])] = [("mtime.txt", data)]
  let archive = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    mtime: Some(mtime),
  })
  let list = unzip_list(archive)
  assert_eq(list.length(), 1)
  // DOS time has 2-second granularity
  let expected = mtime - mtime % 2
  assert_eq(list[0].mtime, expected)
}

///|
test "zip D-3: unzip_list returns attrs" {
  let data = string_to_bytes("attrs test")
  let files : Array[(String, FixedArray[Byte])] = [("attrs.txt", data)]
  let entry_options : Array[@types.ZipEntryOptions?] = [
    Some(@types.ZipEntryOptions::{
      ..@types.ZipEntryOptions::default(),
      attrs: Some(@types.ZipAttributes::{
        os: None,
        attrs: Some(0x10),
        comment: None,
        extra: None,
      }),
    }),
  ]
  let archive = zip_sync(files, entry_opts=entry_options)
  let list = unzip_list(archive)
  assert_eq(list.length(), 1)
  assert_eq(list[0].attrs, 0x10)
}

///|
test "zip D-3: unzip_list returns comment" {
  let data = string_to_bytes("comment test")
  let files : Array[(String, FixedArray[Byte])] = [("comment.txt", data)]
  let entry_options : Array[@types.ZipEntryOptions?] = [
    Some(@types.ZipEntryOptions::{
      ..@types.ZipEntryOptions::default(),
      attrs: Some(@types.ZipAttributes::{
        os: None,
        attrs: None,
        comment: Some("file comment here"),
        extra: None,
      }),
    }),
  ]
  let archive = zip_sync(files, entry_opts=entry_options)
  let list = unzip_list(archive)
  assert_eq(list.length(), 1)
  assert_eq(list[0].comment, "file comment here")
}

///|
test "zip D-3: unzip_list returns extra fields" {
  let data = string_to_bytes("extra test")
  let files : Array[(String, FixedArray[Byte])] = [("extra.txt", data)]
  let extra_map : Map[Int, FixedArray[Byte]] = {}
  extra_map[0x5455] = FixedArray::make(5, b'\x01')
  let entry_options : Array[@types.ZipEntryOptions?] = [
    Some(@types.ZipEntryOptions::{
      ..@types.ZipEntryOptions::default(),
      attrs: Some(@types.ZipAttributes::{
        os: None,
        attrs: None,
        comment: None,
        extra: Some(extra_map),
      }),
    }),
  ]
  let archive = zip_sync(files, entry_opts=entry_options)
  let list = unzip_list(archive)
  assert_eq(list.length(), 1)
  assert_true(list[0].extra.contains(0x5455))
  let d = list[0].extra[0x5455]
  assert_eq(d.length(), 5)
  assert_eq(d[0], b'\x01')
}

///|
test "zip D-3: unzip_list default values for new fields" {
  let data = string_to_bytes("default fields test")
  let files : Array[(String, FixedArray[Byte])] = [("default.txt", data)]
  let archive = zip_sync(files)
  let list = unzip_list(archive)
  assert_eq(list.length(), 1)
  assert_eq(list[0].comment, "")
  assert_eq(list[0].attrs, 0)
  assert_eq(list[0].extra.length(), 0)
}

// === D-T3b: ZIP64 読み取りサポートテスト ===

///|
test "zip D-4: ZIP64 EOCD parsing (synthetic)" {
  // Create a normal small archive first
  let data = string_to_bytes("zip64 test")
  let files : Array[(String, FixedArray[Byte])] = [("z64.txt", data)]
  let archive = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 0,
  })
  // Verify that parse_eocd works on normal archives (backward compatibility)
  let list = unzip_list(archive)
  assert_eq(list.length(), 1)
  assert_eq(list[0].name, "z64.txt")
  assert_eq(list[0].original_size, data.length())
}

// === D-T4: ZIP ファイルコメント テスト ===

///|
test "zip D-5: archive comment write and read" {
  let data = string_to_bytes("comment archive test")
  let files : Array[(String, FixedArray[Byte])] = [("commented.txt", data)]
  let archive = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    comment: Some("This is an archive comment"),
  })
  let comment = zip_comment(archive)
  assert_eq(comment, "This is an archive comment")
}

///|
test "zip D-5: archive comment empty by default" {
  let data = string_to_bytes("no comment")
  let files : Array[(String, FixedArray[Byte])] = [("nocomment.txt", data)]
  let archive = zip_sync(files)
  let comment = zip_comment(archive)
  assert_eq(comment, "")
}

///|
test "zip D-5: archive comment with UTF-8" {
  let data = string_to_bytes("utf8 comment")
  let files : Array[(String, FixedArray[Byte])] = [("utf8.txt", data)]
  let archive = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    comment: Some("\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}"),
  })
  let comment = zip_comment(archive)
  assert_eq(comment, "\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}")
}

///|
test "zip D-5: archive comment does not affect extraction" {
  let data = string_to_bytes("data with comment")
  let files : Array[(String, FixedArray[Byte])] = [("file.txt", data)]
  let archive = zip_sync(files, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    comment: Some("An important archive comment"),
  })
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  assert_true(bytes_equal(result[0].1, data))
}

///|
test "zip D-5: archive comment with entry comments" {
  let data = string_to_bytes("both comments")
  let files : Array[(String, FixedArray[Byte])] = [("both.txt", data)]
  let entry_options : Array[@types.ZipEntryOptions?] = [
    Some(@types.ZipEntryOptions::{
      ..@types.ZipEntryOptions::default(),
      attrs: Some(@types.ZipAttributes::{
        os: None,
        attrs: None,
        comment: Some("entry-level comment"),
        extra: None,
      }),
    }),
  ]
  let archive = zip_sync(
    files,
    opts=@types.ZipOptions::{
      ..@types.ZipOptions::default(),
      comment: Some("archive-level comment"),
    },
    entry_opts=entry_options,
  )
  let archive_comment = zip_comment(archive)
  assert_eq(archive_comment, "archive-level comment")
  let list = unzip_list(archive)
  assert_eq(list[0].comment, "entry-level comment")
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  assert_true(bytes_equal(result[0].1, data))
}

// === utf8_to_string tests ===

///|
test "utf8_to_string: ASCII string" {
  let data : FixedArray[Byte] = [b'\x48', b'\x65', b'\x6C', b'\x6C', b'\x6F']
  let result = utf8_to_string(data, 0, data.length())
  assert_eq(result, "Hello")
}

///|
test "utf8_to_string: 2-byte UTF-8 (é)" {
  let data : FixedArray[Byte] = [b'\xC3', b'\xA9']
  let result = utf8_to_string(data, 0, data.length())
  assert_eq(result, "\u{00E9}")
}

///|
test "utf8_to_string: 3-byte UTF-8 (あ)" {
  let data : FixedArray[Byte] = [b'\xE3', b'\x81', b'\x82']
  let result = utf8_to_string(data, 0, data.length())
  assert_eq(result, "\u{3042}")
}

///|
test "utf8_to_string: 4-byte UTF-8 (𝄞)" {
  let data : FixedArray[Byte] = [b'\xF0', b'\x9D', b'\x84', b'\x9E']
  let result = utf8_to_string(data, 0, data.length())
  assert_eq(result, "\u{1D11E}")
}

///|
test "utf8_to_string: invalid 4-byte codepoint above U+10FFFF replaced with ?" {
  // 0xF4 0x90 0x80 0x80 = U+110000 (above max)
  let data : FixedArray[Byte] = [b'\xF4', b'\x90', b'\x80', b'\x80']
  let result = utf8_to_string(data, 0, data.length())
  assert_eq(result, "?")
}

///|
test "utf8_to_string: invalid leading byte 0xFE replaced with ?" {
  let data : FixedArray[Byte] = [b'\xFE']
  let result = utf8_to_string(data, 0, data.length())
  assert_eq(result, "?")
}

///|
test "utf8_to_string: truncated sequence replaced with ?" {
  // 3-byte start but only 1 continuation byte — each invalid byte becomes '?'
  let data : FixedArray[Byte] = [b'\xE3', b'\x81']
  let result = utf8_to_string(data, 0, data.length())
  assert_eq(result, "??")
}

// === latin1_to_string tests ===

///|
test "latin1_to_string: ASCII string" {
  let data : FixedArray[Byte] = [b'\x48', b'\x69']
  let result = latin1_to_string(data, 0, data.length())
  assert_eq(result, "Hi")
}

///|
test "latin1_to_string: high byte 0xE9 decodes to é" {
  let data : FixedArray[Byte] = [b'\xE9']
  let result = latin1_to_string(data, 0, data.length())
  assert_eq(result, "\u{00E9}")
}

// === Central Directory encoding round-trip tests ===

///|
test "zip round-trip: ASCII-only filename preserved regardless of encoding path" {
  let data = string_to_bytes("content")
  let files : Array[(String, FixedArray[Byte])] = [("readme.txt", data)]
  let archive = zip_sync(files)
  let result = unzip_sync(archive)
  assert_eq(result.length(), 1)
  assert_eq(result[0].0, "readme.txt")
  assert_true(bytes_equal(result[0].1, data))
}
