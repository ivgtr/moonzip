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

///|
test "gzip: extra option round-trip" {
  let data = string_to_bytes("extra test data")
  let extra : FixedArray[Byte] = [b'\xAA', b'\xBB', b'\xCC', b'\xDD']
  let compressed = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    extra: Some(extra),
  })
  // FLG should have FEXTRA bit set (bit 2 = 0x04)
  let flg = compressed[3].to_int()
  assert_true((flg & 0x04) != 0)
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "gzip: comment option round-trip" {
  let data = string_to_bytes("comment test data")
  let compressed = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    comment: Some("this is a comment"),
  })
  // FLG should have FCOMMENT bit set (bit 4 = 0x10)
  let flg = compressed[3].to_int()
  assert_true((flg & 0x10) != 0)
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "gzip: filename + extra + comment full options round-trip" {
  let data = string_to_bytes("full options test")
  let extra : FixedArray[Byte] = [b'\x01', b'\x02']
  let compressed = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
    level: 6,
    mem: 4,
    mtime: Some(1700000000),
    filename: Some("full.txt"),
    comment: Some("full comment"),
    extra: Some(extra),
  })
  // FLG should have FEXTRA, FNAME, FCOMMENT bits set
  let flg = compressed[3].to_int()
  assert_true((flg & 0x04) != 0)
  assert_true((flg & 0x08) != 0)
  assert_true((flg & 0x10) != 0)
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "gzip: ISIZE mismatch error" {
  let data = string_to_bytes("isize test")
  let compressed_orig = @gzip.gzip_sync(data)
  // Copy and tamper with ISIZE (last 4 bytes)
  let compressed = FixedArray::make(compressed_orig.length(), b'\x00')
  for i = 0; i < compressed_orig.length(); i = i + 1 {
    compressed[i] = compressed_orig[i]
  }
  let sl = compressed.length()
  compressed[sl - 1] = ((compressed[sl - 1].to_int() + 1) & 0xFF).to_byte()
  let mut got_error = false
  try {
    let _ = @gzip.gunzip_sync(compressed)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

// === Multi-member GZIP tests ===

///|
fn concat_bytes(a : FixedArray[Byte], b : FixedArray[Byte]) -> FixedArray[Byte] {
  let result = FixedArray::make(a.length() + b.length(), b'\x00')
  for i = 0; i < a.length(); i = i + 1 {
    result[i] = a[i]
  }
  for i = 0; i < b.length(); i = i + 1 {
    result[a.length() + i] = b[i]
  }
  result
}

///|
test "gzip: multi-member two members round-trip" {
  let data1 = string_to_bytes("Hello")
  let data2 = string_to_bytes(" World")
  let gz1 = @gzip.gzip_sync(data1)
  let gz2 = @gzip.gzip_sync(data2)
  let multi = concat_bytes(gz1, gz2)
  let decompressed = @gzip.gunzip_sync(multi)
  let expected = concat_bytes(data1, data2)
  assert_true(bytes_equal(decompressed, expected))
}

///|
test "gzip: multi-member three members round-trip" {
  let data1 = string_to_bytes("AAA")
  let data2 = string_to_bytes("BBB")
  let data3 = string_to_bytes("CCC")
  let gz1 = @gzip.gzip_sync(data1)
  let gz2 = @gzip.gzip_sync(data2)
  let gz3 = @gzip.gzip_sync(data3)
  let multi = concat_bytes(concat_bytes(gz1, gz2), gz3)
  let decompressed = @gzip.gunzip_sync(multi)
  let expected = string_to_bytes("AAABBBCCC")
  assert_true(bytes_equal(decompressed, expected))
}

///|
test "gzip: multi-member with empty first member" {
  let data1 : FixedArray[Byte] = []
  let data2 = string_to_bytes("data")
  let gz1 = @gzip.gzip_sync(data1)
  let gz2 = @gzip.gzip_sync(data2)
  let multi = concat_bytes(gz1, gz2)
  let decompressed = @gzip.gunzip_sync(multi)
  assert_true(bytes_equal(decompressed, data2))
}

///|
test "gzip: multi-member with empty second member" {
  let data1 = string_to_bytes("data")
  let data2 : FixedArray[Byte] = []
  let gz1 = @gzip.gzip_sync(data1)
  let gz2 = @gzip.gzip_sync(data2)
  let multi = concat_bytes(gz1, gz2)
  let decompressed = @gzip.gunzip_sync(multi)
  assert_true(bytes_equal(decompressed, data1))
}

///|
test "gzip: multi-member each member CRC32/ISIZE verified" {
  let data1 = string_to_bytes("First member data")
  let data2 = string_to_bytes("Second member data")
  let gz1 = @gzip.gzip_sync(data1)
  let gz2 = @gzip.gzip_sync(data2)
  // Tamper with CRC32 of first member (byte at offset len-8 from member1 end)
  let gz1_bad = FixedArray::make(gz1.length(), b'\x00')
  for i = 0; i < gz1.length(); i = i + 1 {
    gz1_bad[i] = gz1[i]
  }
  let crc_pos = gz1_bad.length() - 8
  gz1_bad[crc_pos] = ((gz1_bad[crc_pos].to_int() + 1) & 0xFF).to_byte()
  let multi_bad = concat_bytes(gz1_bad, gz2)
  let mut got_error = false
  try {
    let _ = @gzip.gunzip_sync(multi_bad)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "gzip: multi-member with different compression levels" {
  let data1 = string_to_bytes("Level 0 data")
  let data2 = string_to_bytes("Level 9 data")
  let gz1 = @gzip.gzip_sync(data1, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    level: 0,
  })
  let gz2 = @gzip.gzip_sync(data2, opts=@types.GzipOptions::{
    ..@types.GzipOptions::default(),
    level: 9,
  })
  let multi = concat_bytes(gz1, gz2)
  let decompressed = @gzip.gunzip_sync(multi)
  let expected = concat_bytes(data1, data2)
  assert_true(bytes_equal(decompressed, expected))
}

///|
test "gzip: gunzip_sync with size hint" {
  let data = string_to_bytes("Hello world!")
  let compressed = @gzip.gzip_sync(data)
  let decompressed = @gzip.gunzip_sync(compressed, opts=@types.InflateOptions::{
    size: Some(12),
    dictionary: None,
  })
  assert_true(bytes_equal(data, decompressed))
}

///|
test "gzip: gunzip_sync with default opts" {
  let data = string_to_bytes("test opts default")
  let compressed = @gzip.gzip_sync(data)
  let decompressed = @gzip.gunzip_sync(
    compressed,
    opts=@types.InflateOptions::default(),
  )
  assert_true(bytes_equal(data, decompressed))
}

///|
test "gzip: error on too short data (deflate_end < deflate_start)" {
  // Valid 10-byte header but not enough for 8-byte footer
  let data : FixedArray[Byte] = [
    b'\x1F', b'\x8B', b'\x08', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\xFF', b'\x00', b'\x00',
  ]
  let mut got_error = false
  try {
    let _ = @gzip.gunzip_sync(data)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}
