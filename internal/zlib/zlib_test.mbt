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
test "zlib: empty data round-trip" {
  let data : FixedArray[Byte] = []
  let compressed = @zlib.zlib_sync(data)
  let decompressed = @zlib.unzlib_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "zlib: 'Hello world!' round-trip" {
  let data = string_to_bytes("Hello world!")
  let compressed = @zlib.zlib_sync(data)
  let decompressed = @zlib.unzlib_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "zlib: 1KB data round-trip" {
  let data = fill_bytes(b'\xAB', 1024)
  let compressed = @zlib.zlib_sync(data)
  let decompressed = @zlib.unzlib_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === Header validation tests ===

///|
test "zlib: header CMF/FLG validation" {
  let data = string_to_bytes("test")
  let compressed = @zlib.zlib_sync(data)
  // CMF should be 0x78 (CM=8, CINFO=7)
  assert_eq(compressed[0], b'\x78')
  // Verify CM field
  let cmf = compressed[0].to_int()
  let cm = cmf & 0x0F
  assert_eq(cm, 8)
  // Verify CINFO field
  let cinfo = (cmf >> 4) & 0x0F
  assert_eq(cinfo, 7)
}

///|
test "zlib: FCHECK is correct" {
  let data = string_to_bytes("test")
  let compressed = @zlib.zlib_sync(data)
  let cmf = compressed[0].to_int()
  let flg = compressed[1].to_int()
  assert_eq((cmf * 256 + flg) % 31, 0)
}

///|
test "zlib: FLEVEL field for different compression levels" {
  let data = string_to_bytes("test")
  // Level 0 -> FLEVEL=0
  let c0 = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: 0,
  })
  let flevel0 = (c0[1].to_int() >> 6) & 0x03
  assert_eq(flevel0, 0)
  // Level 1 -> FLEVEL=0
  let c1 = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: 1,
  })
  let flevel1 = (c1[1].to_int() >> 6) & 0x03
  assert_eq(flevel1, 0)
  // Level 3 -> FLEVEL=1
  let c3 = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: 3,
  })
  let flevel3 = (c3[1].to_int() >> 6) & 0x03
  assert_eq(flevel3, 1)
  // Level 6 -> FLEVEL=2
  let c6 = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: 6,
  })
  let flevel6 = (c6[1].to_int() >> 6) & 0x03
  assert_eq(flevel6, 2)
  // Level 9 -> FLEVEL=3
  let c9 = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: 9,
  })
  let flevel9 = (c9[1].to_int() >> 6) & 0x03
  assert_eq(flevel9, 3)
}

// === Adler-32 footer verification ===

///|
test "zlib: Adler-32 footer verification" {
  let data = string_to_bytes("Hello world!")
  let compressed = @zlib.zlib_sync(data)
  // Read Adler-32 from footer (big-endian, last 4 bytes)
  let len = compressed.length()
  let stored_adler = (compressed[len - 4].to_uint() << 24) |
    (compressed[len - 3].to_uint() << 16) |
    (compressed[len - 2].to_uint() << 8) |
    compressed[len - 1].to_uint()
  let expected_adler = @checksum.adler32(data)
  assert_eq(stored_adler, expected_adler)
}

// === Error tests ===

///|
test "zlib: error on invalid CM" {
  // CMF with CM=4 (not 8), CINFO=7 -> CMF = 0x74
  // FLG with correct FCHECK for this CMF
  let cmf = 0x74
  let fcheck = 31 - cmf * 256 % 31
  let data : FixedArray[Byte] = [cmf.to_byte(), fcheck.to_byte()]
  let mut got_error = false
  try {
    let _ = @zlib.unzlib_sync(data)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "zlib: error on invalid CINFO" {
  // CMF with CM=8, CINFO=8 -> CMF = 0x88
  // FLG with correct FCHECK for this CMF
  let cmf = 0x88
  let fcheck = 31 - cmf * 256 % 31
  let data : FixedArray[Byte] = [cmf.to_byte(), fcheck.to_byte()]
  let mut got_error = false
  try {
    let _ = @zlib.unzlib_sync(data)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "zlib: error on FCHECK mismatch" {
  // Valid CMF=0x78 but wrong FLG (FCHECK incorrect)
  let data : FixedArray[Byte] = [b'\x78', b'\x00']
  let mut got_error = false
  try {
    let _ = @zlib.unzlib_sync(data)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "zlib: error on truncated data" {
  // Only 1 byte - not enough for header
  let data : FixedArray[Byte] = [b'\x78']
  let mut got_error = false
  try {
    let _ = @zlib.unzlib_sync(data)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "zlib: FDICT flag with valid data" {
  // CMF=0x78, FLG=0x20 (FDICT=1, FCHECK correct: (0x78*256+0x20)%31==0)
  // DICTID=4 bytes, then empty stored deflate block, then Adler32 of empty data
  let data : FixedArray[Byte] = [
    b'\x78', b'\x20', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00',
    b'\xFF', b'\xFF', b'\x00', b'\x00', b'\x00', b'\x01',
  ]
  let result = @zlib.unzlib_sync(data)
  assert_eq(result.length(), 0)
}

///|
test "zlib: unzlib_sync with size hint" {
  let data = string_to_bytes("Hello world!")
  let compressed = @zlib.zlib_sync(data)
  let decompressed = @zlib.unzlib_sync(compressed, opts=@types.InflateOptions::{
    size: Some(12),
    dictionary: None,
  })
  assert_true(bytes_equal(data, decompressed))
}

///|
test "zlib: unzlib_sync with default opts" {
  let data = string_to_bytes("test opts default")
  let compressed = @zlib.zlib_sync(data)
  let decompressed = @zlib.unzlib_sync(
    compressed,
    opts=@types.InflateOptions::default(),
  )
  assert_true(bytes_equal(data, decompressed))
}

///|
test "zlib: FDICT with insufficient data raises error" {
  // CMF=0x78, FLG=0x20 (FDICT=1), but only 4 bytes total (needs 6)
  let data : FixedArray[Byte] = [b'\x78', b'\x20', b'\x00', b'\x00']
  let mut got_error = false
  let mut error_code : @types.FlateErrorCode = @types.FlateErrorCode::InvalidHeader
  try {
    let _ = @zlib.unzlib_sync(data)
  } catch {
    @types.FlateError(code) => {
      got_error = true
      error_code = code
    }
  }
  assert_true(got_error)
  assert_eq(error_code, @types.FlateErrorCode::UnexpectedEOF)
}
