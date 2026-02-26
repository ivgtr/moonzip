// Phase 5: decompressSync tests

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

// === 5-T1: decompressSync normal tests ===

///|
test "decompressSync: GZIP data auto-detect" {
  let data = string_to_bytes("Hello from GZIP!")
  let compressed = @gzip.gzip_sync(data)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "decompressSync: Zlib data auto-detect" {
  let data = string_to_bytes("Hello from Zlib!")
  let compressed = @zlib.zlib_sync(data)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "decompressSync: raw DEFLATE data auto-detect" {
  let data = string_to_bytes("Hello from DEFLATE!")
  let compressed = @deflate.deflate_sync(data)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "decompressSync: same input via all formats produces same output" {
  let data = string_to_bytes("The quick brown fox jumps over the lazy dog")
  let gzip_compressed = @gzip.gzip_sync(data)
  let zlib_compressed = @zlib.zlib_sync(data)
  let deflate_compressed = @deflate.deflate_sync(data)
  let d1 = decompress_sync(gzip_compressed)
  let d2 = decompress_sync(zlib_compressed)
  let d3 = decompress_sync(deflate_compressed)
  assert_true(bytes_equal(data, d1))
  assert_true(bytes_equal(data, d2))
  assert_true(bytes_equal(data, d3))
}

///|
test "decompressSync: GZIP empty data" {
  let data : FixedArray[Byte] = []
  let compressed = @gzip.gzip_sync(data)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "decompressSync: Zlib empty data" {
  let data : FixedArray[Byte] = []
  let compressed = @zlib.zlib_sync(data)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "decompressSync: raw DEFLATE empty data" {
  let data : FixedArray[Byte] = []
  let compressed = @deflate.deflate_sync(data)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === 5-T2: decompressSync edge case tests ===

///|
test "decompressSync: raw DEFLATE stored block" {
  // A stored block: BFINAL=1, BTYPE=00, LEN=1, NLEN=0xFFFE, data=0x42
  let data : FixedArray[Byte] = [
    b'\x01', b'\x01', b'\x00', b'\xFE', b'\xFF', b'\x42',
  ]
  let result = decompress_sync(data)
  assert_eq(result.length(), 1)
  assert_eq(result[0], b'\x42')
}

///|
test "decompressSync: invalid data raises error" {
  // Invalid block type 3
  let data : FixedArray[Byte] = [b'\x07']
  let mut got_error = false
  try {
    let _ = decompress_sync(data)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "decompressSync: large data round-trip via GZIP" {
  let data = FixedArray::make(4096, b'\x00')
  for i = 0; i < data.length(); i = i + 1 {
    data[i] = (i % 256).to_byte()
  }
  let compressed = @gzip.gzip_sync(data)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}
