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
test "gzip: empty data round-trip" {
  let data : FixedArray[Byte] = []
  let compressed = @gzip.gzip_sync(data)
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "gzip: 'Hello world!' round-trip" {
  let data = string_to_bytes("Hello world!")
  let compressed = @gzip.gzip_sync(data)
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "gzip: 1KB data round-trip" {
  let data = fill_bytes(b'\xAB', 1024)
  let compressed = @gzip.gzip_sync(data)
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === Header validation tests ===

///|
test "gzip: header magic number and CM" {
  let data = string_to_bytes("test")
  let compressed = @gzip.gzip_sync(data)
  // Verify GZIP magic number
  assert_eq(compressed[0], b'\x1F')
  assert_eq(compressed[1], b'\x8B')
  // Verify CM = 8 (deflate)
  assert_eq(compressed[2], b'\x08')
}

// === Options tests ===

///|
test "gzip: with filename option" {
  let data = string_to_bytes("hello")
  let compressed = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    filename: Some("test.txt"),
  })
  // FLG should have FNAME bit set (bit 3 = 0x08)
  let flg = compressed[3].to_int()
  assert_true((flg & 0x08) != 0)
  // After the 10-byte header, the filename should be "test.txt\0"
  let expected = string_to_bytes("test.txt")
  for i = 0; i < expected.length(); i = i + 1 {
    assert_eq(compressed[10 + i], expected[i])
  }
  assert_eq(compressed[10 + expected.length()], b'\x00')
  // Round-trip should still work
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "gzip: with mtime option" {
  let data = string_to_bytes("hello")
  let mtime = 1700000000
  let compressed = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    mtime: Some(mtime),
  })
  // Read MTIME from bytes 4-7 (LE)
  let read_mtime = compressed[4].to_int() |
    (compressed[5].to_int() << 8) |
    (compressed[6].to_int() << 16) |
    (compressed[7].to_int() << 24)
  assert_eq(read_mtime, mtime)
  // Round-trip should still work
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "gzip: XFL field verification" {
  let data = string_to_bytes("test")
  // Level 1 (fastest) => XFL should be 4
  let c1 = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    level: 1,
  })
  assert_eq(c1[8], b'\x04')
  // Level 2 (fastest) => XFL should be 4
  let c2 = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    level: 2,
  })
  assert_eq(c2[8], b'\x04')
  // Level 6 (normal) => XFL should be 0
  let c6 = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    level: 6,
  })
  assert_eq(c6[8], b'\x00')
  // Level 7 (best compression) => XFL should be 2
  let c7 = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    level: 7,
  })
  assert_eq(c7[8], b'\x02')
  // Level 9 (best compression) => XFL should be 2
  let c9 = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    level: 9,
  })
  assert_eq(c9[8], b'\x02')
}

// === Error tests ===

///|
test "gzip: error on invalid magic number" {
  let data : FixedArray[Byte] = [
    b'\x00', b'\x00', b'\x08', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\xFF', b'\x03', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ]
  let mut got_error = false
  let mut error_code : @types.FlateErrorCode = @types.FlateErrorCode::UnexpectedEOF
  try {
    let _ = @gzip.gunzip_sync(data)
  } catch {
    @types.FlateError(code) => {
      got_error = true
      error_code = code
    }
  }
  assert_true(got_error)
  assert_eq(error_code, @types.FlateErrorCode::InvalidHeader)
}

///|
test "gzip: error on invalid CM" {
  let data : FixedArray[Byte] = [
    b'\x1F', b'\x8B', b'\x04', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\xFF', b'\x03', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ]
  let mut got_error = false
  let mut error_code : @types.FlateErrorCode = @types.FlateErrorCode::UnexpectedEOF
  try {
    let _ = @gzip.gunzip_sync(data)
  } catch {
    @types.FlateError(code) => {
      got_error = true
      error_code = code
    }
  }
  assert_true(got_error)
  assert_eq(error_code, @types.FlateErrorCode::UnknownCompressionMethod)
}

///|
test "gzip: error on truncated data" {
  // Only 5 bytes - too short for even the 10-byte header
  let data : FixedArray[Byte] = [b'\x1F', b'\x8B', b'\x08', b'\x00', b'\x00']
  let mut got_error = false
  let mut error_code : @types.FlateErrorCode = @types.FlateErrorCode::InvalidHeader
  try {
    let _ = @gzip.gunzip_sync(data)
  } catch {
    @types.FlateError(code) => {
      got_error = true
      error_code = code
    }
  }
  assert_true(got_error)
  assert_eq(error_code, @types.FlateErrorCode::UnexpectedEOF)
}
