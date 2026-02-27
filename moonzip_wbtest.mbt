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

// === Phase 9: Integration / Compatibility Tests ===

// === 9-1: Cross-format round-trip tests ===

///|
test "integration: deflate round-trip all levels" {
  let data = string_to_bytes("Hello world!")
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.DeflateOptions::{
      ..@types.DeflateOptions::default(),
      level,
    }
    let compressed = @deflate.deflate_sync(data, opts~)
    let decompressed = @deflate.inflate_sync(compressed)
    assert_true(bytes_equal(data, decompressed))
  }
}

///|
test "integration: gzip round-trip all levels" {
  let data = string_to_bytes("Hello world!")
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.GzipOptions::{ ..@types.GzipOptions::default(), level, }
    let compressed = @gzip.gzip_sync(data, opts~)
    let decompressed = @gzip.gunzip_sync(compressed)
    assert_true(bytes_equal(data, decompressed))
  }
}

///|
test "integration: zlib round-trip all levels" {
  let data = string_to_bytes("Hello world!")
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.ZlibOptions::{ ..@types.ZlibOptions::default(), level, }
    let compressed = @zlib.zlib_sync(data, opts~)
    let decompressed = @zlib.unzlib_sync(compressed)
    assert_true(bytes_equal(data, decompressed))
  }
}

///|
test "integration: zip round-trip multiple files" {
  let file1 = string_to_bytes("Content of file 1")
  let file2 = string_to_bytes("Content of file 2 with more data")
  let file3 = string_to_bytes("Third file")
  let files : Array[(String, FixedArray[Byte])] = [
    ("file1.txt", file1),
    ("dir/file2.txt", file2),
    ("file3.txt", file3),
  ]
  let archive = @zip.zip_sync(files)
  let extracted = @zip.unzip_sync(archive)
  assert_eq(extracted.length(), 3)
  assert_eq(extracted[0].0, "file1.txt")
  assert_true(bytes_equal(extracted[0].1, file1))
  assert_eq(extracted[1].0, "dir/file2.txt")
  assert_true(bytes_equal(extracted[1].1, file2))
  assert_eq(extracted[2].0, "file3.txt")
  assert_true(bytes_equal(extracted[2].1, file3))
}

// === 9-4: Large data tests ===

///|
test "integration: deflate 1KB repeated pattern" {
  // "abcdefgh" repeated 128 times = 1024 bytes
  let data = FixedArray::make(1024, b'\x00')
  let pattern = "abcdefgh"
  for i = 0; i < 1024; i = i + 1 {
    let ch = match i % 8 {
      0 => b'\x61'
      1 => b'\x62'
      2 => b'\x63'
      3 => b'\x64'
      4 => b'\x65'
      5 => b'\x66'
      6 => b'\x67'
      _ => b'\x68'
    }
    data[i] = ch
  }
  let _ = pattern
  let compressed = @deflate.deflate_sync(data)
  let decompressed = @deflate.inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "integration: gzip 4KB binary data" {
  // All byte values 0-255 repeated to fill 4KB
  let data = FixedArray::make(4096, b'\x00')
  for i = 0; i < 4096; i = i + 1 {
    data[i] = (i % 256).to_byte()
  }
  let compressed = @gzip.gzip_sync(data)
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "integration: zlib 4KB binary data" {
  // All byte values 0-255 repeated to fill 4KB
  let data = FixedArray::make(4096, b'\x00')
  for i = 0; i < 4096; i = i + 1 {
    data[i] = (i % 256).to_byte()
  }
  let compressed = @zlib.zlib_sync(data)
  let decompressed = @zlib.unzlib_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "integration: zip 4KB data" {
  // All byte values 0-255 repeated to fill 4KB
  let data = FixedArray::make(4096, b'\x00')
  for i = 0; i < 4096; i = i + 1 {
    data[i] = (i % 256).to_byte()
  }
  let files : Array[(String, FixedArray[Byte])] = [("binary.bin", data)]
  let archive = @zip.zip_sync(files)
  let extracted = @zip.unzip_sync(archive)
  assert_eq(extracted.length(), 1)
  assert_eq(extracted[0].0, "binary.bin")
  assert_true(bytes_equal(extracted[0].1, data))
}

// === 9-5: Edge case tests ===

///|
test "integration: all formats empty data" {
  let data : FixedArray[Byte] = []
  // deflate
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  // gzip
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
  // zlib
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
  // zip
  let files : Array[(String, FixedArray[Byte])] = [("empty.txt", data)]
  let za = @zip.zip_sync(files)
  let ze = @zip.unzip_sync(za)
  assert_eq(ze.length(), 1)
  assert_true(bytes_equal(ze[0].1, data))
}

///|
test "integration: all formats 1 byte" {
  let data : FixedArray[Byte] = [b'\x42']
  // deflate
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  // gzip
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
  // zlib
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
  // zip
  let files : Array[(String, FixedArray[Byte])] = [("one.bin", data)]
  let za = @zip.zip_sync(files)
  let ze = @zip.unzip_sync(za)
  assert_eq(ze.length(), 1)
  assert_true(bytes_equal(ze[0].1, data))
}

///|
test "integration: all formats all zeros 1KB" {
  let data = FixedArray::make(1024, b'\x00')
  // deflate
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  // gzip
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
  // zlib
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
  // zip
  let files : Array[(String, FixedArray[Byte])] = [("zeros.bin", data)]
  let za = @zip.zip_sync(files)
  let ze = @zip.unzip_sync(za)
  assert_eq(ze.length(), 1)
  assert_true(bytes_equal(ze[0].1, data))
}

///|
test "integration: all formats all 0xFF 1KB" {
  let data = FixedArray::make(1024, b'\xFF')
  // deflate
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  // gzip
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
  // zlib
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
  // zip
  let files : Array[(String, FixedArray[Byte])] = [("ff.bin", data)]
  let za = @zip.zip_sync(files)
  let ze = @zip.unzip_sync(za)
  assert_eq(ze.length(), 1)
  assert_true(bytes_equal(ze[0].1, data))
}

///|
test "integration: deflate 64KB boundary" {
  // Test 65535 bytes (just under 64KB boundary)
  let data1 = FixedArray::make(65535, b'\x00')
  for i = 0; i < 65535; i = i + 1 {
    data1[i] = (i % 256).to_byte()
  }
  let compressed1 = @deflate.deflate_sync(data1)
  let decompressed1 = @deflate.inflate_sync(compressed1)
  assert_true(bytes_equal(data1, decompressed1))
  // Test 65536 bytes (exactly 64KB boundary)
  let data2 = FixedArray::make(65536, b'\x00')
  for i = 0; i < 65536; i = i + 1 {
    data2[i] = (i % 256).to_byte()
  }
  let compressed2 = @deflate.deflate_sync(data2)
  let decompressed2 = @deflate.inflate_sync(compressed2)
  assert_true(bytes_equal(data2, decompressed2))
}

///|
test "decompressSync: with size hint via GZIP" {
  let data = string_to_bytes("decompress with opts")
  let compressed = @gzip.gzip_sync(data)
  let decompressed = decompress_sync(compressed, opts=@types.InflateOptions::{
    size: Some(20),
    dictionary: None,
  })
  assert_true(bytes_equal(data, decompressed))
}

///|
test "decompressSync: with size hint via Zlib" {
  let data = string_to_bytes("decompress with opts zlib")
  let compressed = @zlib.zlib_sync(data)
  let decompressed = decompress_sync(compressed, opts=@types.InflateOptions::{
    size: Some(25),
    dictionary: None,
  })
  assert_true(bytes_equal(data, decompressed))
}

///|
test "decompressSync: with size hint via raw DEFLATE" {
  let data = string_to_bytes("decompress with opts deflate")
  let compressed = @deflate.deflate_sync(data)
  let decompressed = decompress_sync(compressed, opts=@types.InflateOptions::{
    size: Some(28),
    dictionary: None,
  })
  assert_true(bytes_equal(data, decompressed))
}

///|
test "decompressSync: with default opts" {
  let data = string_to_bytes("decompress default opts")
  let compressed = @gzip.gzip_sync(data)
  let decompressed = decompress_sync(
    compressed,
    opts=@types.InflateOptions::default(),
  )
  assert_true(bytes_equal(data, decompressed))
}

///|
test "integration: cross-format decompress_sync" {
  let data = string_to_bytes("Cross-format test data for decompress_sync")
  // GZIP format
  let gzip_compressed = @gzip.gzip_sync(data)
  let gzip_result = decompress_sync(gzip_compressed)
  assert_true(bytes_equal(data, gzip_result))
  // Zlib format
  let zlib_compressed = @zlib.zlib_sync(data)
  let zlib_result = decompress_sync(zlib_compressed)
  assert_true(bytes_equal(data, zlib_result))
  // Raw DEFLATE format
  let deflate_compressed = @deflate.deflate_sync(data)
  let deflate_result = decompress_sync(deflate_compressed)
  assert_true(bytes_equal(data, deflate_result))
}

// === Phase F: compress_sync tests ===

///|
test "compress_sync: round-trip with decompress_sync" {
  let data = string_to_bytes("Hello, compress_sync!")
  let compressed = compress_sync(data)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "compress_sync: empty data round-trip" {
  let data : FixedArray[Byte] = []
  let compressed = compress_sync(data)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "compress_sync: output is valid GZIP" {
  let data = string_to_bytes("Testing GZIP format")
  let compressed = compress_sync(data)
  // Verify GZIP magic number
  assert_eq(compressed[0], b'\x1F')
  assert_eq(compressed[1], b'\x8B')
  // Decompress via gunzip_sync to verify
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "compress_sync: with custom options" {
  let data = string_to_bytes("Custom options test")
  let opts = @types.GzipOptions::{ ..@types.GzipOptions::default(), level: 9 }
  let compressed = compress_sync(data, opts~)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "compress_sync: large data round-trip" {
  let data = FixedArray::make(4096, b'\x00')
  for i = 0; i < data.length(); i = i + 1 {
    data[i] = (i % 256).to_byte()
  }
  let compressed = compress_sync(data)
  let decompressed = decompress_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === Phase F: strToU8 / strFromU8 re-export tests ===

///|
test "str_to_u8: ASCII via top-level" {
  let result = str_to_u8("Hello")
  assert_eq(result.length(), 5)
  assert_eq(result[0], b'\x48')
  assert_eq(result[4], b'\x6F')
}

///|
test "str_to_u8: multi-byte via top-level" {
  let result = str_to_u8("\u65E5\u672C")
  // "日" = E6 97 A5, "本" = E6 9C AC = 6 bytes total
  assert_eq(result.length(), 6)
}

///|
test "str_from_u8: ASCII via top-level" {
  let data : FixedArray[Byte] = [b'\x48', b'\x69']
  let result = str_from_u8(data)
  assert_eq(result, "Hi")
}

///|
test "str_to_u8: latin1 via top-level" {
  let result = str_to_u8("\u00E9", latin1=true)
  assert_eq(result.length(), 1)
  assert_eq(result[0], b'\xE9')
}

///|
test "str_from_u8: latin1 via top-level" {
  let data : FixedArray[Byte] = [b'\xE9']
  let result = str_from_u8(data, latin1=true)
  assert_eq(result, "\u00E9")
}

///|
test "str round-trip: UTF-8 via top-level" {
  let original = "Hello \u4E16\u754C!"
  let bytes = str_to_u8(original)
  let decoded = str_from_u8(bytes)
  assert_eq(decoded, original)
}

///|
test "str round-trip: latin1 via top-level" {
  let original = "caf\u00E9"
  let bytes = str_to_u8(original, latin1=true)
  let decoded = str_from_u8(bytes, latin1=true)
  assert_eq(decoded, original)
}

// ============================================================
// Phase G: 互換性検証・品質保証
// ============================================================

// Helper: generate repeating text data

///|
fn generate_repeat_text(size : Int) -> FixedArray[Byte] {
  let pattern = "The quick brown fox jumps over the lazy dog. "
  let pat_bytes = string_to_bytes(pattern)
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = pat_bytes[i % pat_bytes.length()]
  }
  data
}

// Helper: simple pseudo-random number generator (xorshift32)

///|
fn pseudo_random_data(size : Int, seed : Int) -> FixedArray[Byte] {
  let data = FixedArray::make(size, b'\x00')
  let mut state = if seed == 0 { 1 } else { seed }
  for i = 0; i < size; i = i + 1 {
    state = state ^ (state << 13)
    state = state ^ (state >> 17)
    state = state ^ (state << 5)
    data[i] = (state & 0xFF).to_byte()
  }
  data
}

// Helper: read 2-byte little-endian value from FixedArray

///|
fn read_u16_le(data : FixedArray[Byte], offset : Int) -> Int {
  data[offset].to_int() | (data[offset + 1].to_int() << 8)
}

// Helper: read 4-byte little-endian value from FixedArray

///|
fn read_u32_le(data : FixedArray[Byte], offset : Int) -> Int {
  data[offset].to_int() |
  (data[offset + 1].to_int() << 8) |
  (data[offset + 2].to_int() << 16) |
  (data[offset + 3].to_int() << 24)
}

// ============================================================
// G-1: ラウンドトリップ検証（全フォーマット × 全レベル）
// ============================================================

///|
test "G1: DEFLATE round-trip all levels with varied data" {
  let data = generate_repeat_text(2048)
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.DeflateOptions::{
      ..@types.DeflateOptions::default(),
      level,
    }
    let compressed = @deflate.deflate_sync(data, opts~)
    let decompressed = @deflate.inflate_sync(compressed)
    assert_true(bytes_equal(data, decompressed))
  }
}

///|
test "G1: GZIP round-trip all levels with varied data" {
  let data = generate_repeat_text(2048)
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.GzipOptions::{ ..@types.GzipOptions::default(), level, }
    let compressed = @gzip.gzip_sync(data, opts~)
    let decompressed = @gzip.gunzip_sync(compressed)
    assert_true(bytes_equal(data, decompressed))
  }
}

///|
test "G1: Zlib round-trip all levels with varied data" {
  let data = generate_repeat_text(2048)
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.ZlibOptions::{ ..@types.ZlibOptions::default(), level, }
    let compressed = @zlib.zlib_sync(data, opts~)
    let decompressed = @zlib.unzlib_sync(compressed)
    assert_true(bytes_equal(data, decompressed))
  }
}

///|
test "G1: ZIP round-trip all levels" {
  let data = generate_repeat_text(2048)
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.ZipOptions::{ ..@types.ZipOptions::default(), level, }
    let files : Array[(String, FixedArray[Byte])] = [("test.txt", data)]
    let archive = @zip.zip_sync(files, opts~)
    let extracted = @zip.unzip_sync(archive)
    assert_eq(extracted.length(), 1)
    assert_eq(extracted[0].0, "test.txt")
    assert_true(bytes_equal(extracted[0].1, data))
  }
}

///|
test "G1: DEFLATE round-trip with random data all levels" {
  let data = pseudo_random_data(1024, 42)
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.DeflateOptions::{
      ..@types.DeflateOptions::default(),
      level,
    }
    let compressed = @deflate.deflate_sync(data, opts~)
    let decompressed = @deflate.inflate_sync(compressed)
    assert_true(bytes_equal(data, decompressed))
  }
}

///|
test "G1: GZIP round-trip with random data all levels" {
  let data = pseudo_random_data(1024, 42)
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.GzipOptions::{ ..@types.GzipOptions::default(), level, }
    let compressed = @gzip.gzip_sync(data, opts~)
    let decompressed = @gzip.gunzip_sync(compressed)
    assert_true(bytes_equal(data, decompressed))
  }
}

///|
test "G1: Zlib round-trip with random data all levels" {
  let data = pseudo_random_data(1024, 42)
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.ZlibOptions::{ ..@types.ZlibOptions::default(), level, }
    let compressed = @zlib.zlib_sync(data, opts~)
    let decompressed = @zlib.unzlib_sync(compressed)
    assert_true(bytes_equal(data, decompressed))
  }
}

///|
test "G1: ZIP round-trip with random data all levels" {
  let data = pseudo_random_data(1024, 42)
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.ZipOptions::{ ..@types.ZipOptions::default(), level, }
    let files : Array[(String, FixedArray[Byte])] = [("rand.bin", data)]
    let archive = @zip.zip_sync(files, opts~)
    let extracted = @zip.unzip_sync(archive)
    assert_eq(extracted.length(), 1)
    assert_true(bytes_equal(extracted[0].1, data))
  }
}

// ============================================================
// G-2: フォーマット仕様準拠テスト
// ============================================================

///|
test "G2: GZIP header magic number and fields" {
  let data = string_to_bytes("GZIP header test")
  let compressed = @gzip.gzip_sync(data)
  // Magic number: 0x1F 0x8B
  assert_eq(compressed[0], b'\x1F')
  assert_eq(compressed[1], b'\x8B')
  // CM = 8 (deflate)
  assert_eq(compressed[2], b'\x08')
  // FLG: no extra flags for default options
  assert_eq(compressed[3], b'\x00')
  // OS = 255 (unknown)
  assert_eq(compressed[9], b'\xFF')
}

///|
test "G2: GZIP header with filename" {
  let data = string_to_bytes("test data")
  let opts = @types.GzipOptions::{
    ..@types.GzipOptions::default(),
    filename: Some("hello.txt"),
  }
  let compressed = @gzip.gzip_sync(data, opts~)
  // FLG should have FNAME bit (0x08) set
  let flg = compressed[3].to_int()
  assert_true((flg & 0x08) != 0)
  // Filename starts at offset 10 and is null-terminated
  let mut pos = 10
  let expected = "hello.txt"
  let mut idx = 0
  for c in expected {
    assert_eq(compressed[pos], c.to_int().to_byte())
    pos = pos + 1
    idx = idx + 1
  }
  assert_eq(compressed[pos], b'\x00') // null terminator
}

///|
test "G2: GZIP header with mtime" {
  let data = string_to_bytes("test")
  let mtime = 1700000000
  let opts = @types.GzipOptions::{
    ..@types.GzipOptions::default(),
    mtime: Some(mtime),
  }
  let compressed = @gzip.gzip_sync(data, opts~)
  // MTIME at offset 4-7 (little-endian)
  let stored_mtime = read_u32_le(compressed, 4)
  assert_eq(stored_mtime, mtime)
}

///|
test "G2: GZIP XFL field reflects compression level" {
  let data = generate_repeat_text(256)
  // Level 1 (fastest): XFL should be 4
  let opts1 = @types.GzipOptions::{ ..@types.GzipOptions::default(), level: 1 }
  let c1 = @gzip.gzip_sync(data, opts=opts1)
  assert_eq(c1[8].to_int(), 4)
  // Level 9 (best): XFL should be 2
  let opts9 = @types.GzipOptions::{ ..@types.GzipOptions::default(), level: 9 }
  let c9 = @gzip.gzip_sync(data, opts=opts9)
  assert_eq(c9[8].to_int(), 2)
  // Level 6 (normal): XFL should be 0
  let opts6 = @types.GzipOptions::{ ..@types.GzipOptions::default(), level: 6 }
  let c6 = @gzip.gzip_sync(data, opts=opts6)
  assert_eq(c6[8].to_int(), 0)
}

///|
test "G2: GZIP footer CRC32 and ISIZE correctness" {
  let data = string_to_bytes("Test CRC32 and ISIZE verification")
  let compressed = @gzip.gzip_sync(data)
  let len = compressed.length()
  // ISIZE (last 4 bytes, little-endian) should match original size
  let isize = read_u32_le(compressed, len - 4)
  assert_eq(isize, data.length())
  // CRC32 (4 bytes before ISIZE) - verify via round-trip
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "G2: Zlib header CMF/FLG checksum" {
  // Test all levels produce valid CMF/FLG where (CMF*256+FLG) % 31 == 0
  let data = string_to_bytes("Zlib header test")
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.ZlibOptions::{ ..@types.ZlibOptions::default(), level, }
    let compressed = @zlib.zlib_sync(data, opts~)
    let cmf = compressed[0].to_int()
    let flg = compressed[1].to_int()
    // CM must be 8
    assert_eq(cmf & 0x0F, 8)
    // CINFO must be <= 7
    assert_true(((cmf >> 4) & 0x0F) <= 7)
    // (CMF*256 + FLG) % 31 must be 0
    assert_eq((cmf * 256 + flg) % 31, 0)
  }
}

///|
test "G2: Zlib header FLEVEL reflects compression level" {
  let data = string_to_bytes("test FLEVEL")
  // Level 0-1: FLEVEL=0
  let c0 = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: 0,
  })
  assert_eq((c0[1].to_int() >> 6) & 3, 0)
  let c1 = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: 1,
  })
  assert_eq((c1[1].to_int() >> 6) & 3, 0)
  // Level 2-5: FLEVEL=1
  let c5 = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: 5,
  })
  assert_eq((c5[1].to_int() >> 6) & 3, 1)
  // Level 6: FLEVEL=2
  let c6 = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: 6,
  })
  assert_eq((c6[1].to_int() >> 6) & 3, 2)
  // Level 7-9: FLEVEL=3
  let c9 = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{
    ..@types.ZlibOptions::default(),
    level: 9,
  })
  assert_eq((c9[1].to_int() >> 6) & 3, 3)
}

///|
test "G2: Zlib Adler-32 footer correctness" {
  let data = string_to_bytes("Adler-32 footer test data")
  let compressed = @zlib.zlib_sync(data)
  let len = compressed.length()
  // Footer is last 4 bytes (big-endian Adler-32)
  // Verify via successful round-trip (unzlib_sync validates Adler-32)
  let decompressed = @zlib.unzlib_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
  // Tamper with Adler-32 footer and verify it fails
  let tampered = FixedArray::make(len, b'\x00')
  for i = 0; i < len; i = i + 1 {
    tampered[i] = compressed[i]
  }
  tampered[len - 1] = tampered[len - 1].to_int().lxor(0xFF).to_byte()
  let mut got_error = false
  try {
    let _ = @zlib.unzlib_sync(tampered)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "G2: ZIP local file header signature" {
  let data = string_to_bytes("ZIP header test")
  let files : Array[(String, FixedArray[Byte])] = [("test.txt", data)]
  let archive = @zip.zip_sync(files)
  // Local file header signature: 0x04034B50 (little-endian: 50 4B 03 04)
  assert_eq(archive[0], b'\x50')
  assert_eq(archive[1], b'\x4B')
  assert_eq(archive[2], b'\x03')
  assert_eq(archive[3], b'\x04')
  // Version needed: 20
  assert_eq(read_u16_le(archive, 4), 20)
}

///|
test "G2: ZIP central directory signature" {
  let data = string_to_bytes("CD test")
  let files : Array[(String, FixedArray[Byte])] = [("a.txt", data)]
  let archive = @zip.zip_sync(files)
  // Find EOCD signature (0x06054B50)
  let len = archive.length()
  let mut eocd_offset = -1
  for i = len - 22; i >= 0; i = i - 1 {
    if archive[i] == b'\x50' &&
      archive[i + 1] == b'\x4B' &&
      archive[i + 2] == b'\x05' &&
      archive[i + 3] == b'\x06' {
      eocd_offset = i
      break
    }
  }
  assert_true(eocd_offset >= 0)
  // Read CD offset from EOCD
  let cd_offset = read_u32_le(archive, eocd_offset + 16)
  // Verify CD entry signature: 0x02014B50 (little-endian: 50 4B 01 02)
  assert_eq(archive[cd_offset], b'\x50')
  assert_eq(archive[cd_offset + 1], b'\x4B')
  assert_eq(archive[cd_offset + 2], b'\x01')
  assert_eq(archive[cd_offset + 3], b'\x02')
}

///|
test "G2: ZIP EOCD structure correctness" {
  let file1 = string_to_bytes("file 1")
  let file2 = string_to_bytes("file 2")
  let files : Array[(String, FixedArray[Byte])] = [
    ("a.txt", file1),
    ("b.txt", file2),
  ]
  let archive = @zip.zip_sync(files)
  let len = archive.length()
  // Find EOCD
  let mut eocd_offset = -1
  for i = len - 22; i >= 0; i = i - 1 {
    if read_u32_le(archive, i) == 0x06054B50 {
      eocd_offset = i
      break
    }
  }
  assert_true(eocd_offset >= 0)
  // Disk number: 0
  assert_eq(read_u16_le(archive, eocd_offset + 4), 0)
  // CD start disk: 0
  assert_eq(read_u16_le(archive, eocd_offset + 6), 0)
  // Entries on this disk: 2
  assert_eq(read_u16_le(archive, eocd_offset + 8), 2)
  // Total entries: 2
  assert_eq(read_u16_le(archive, eocd_offset + 10), 2)
  // CD size should be > 0
  let cd_size = read_u32_le(archive, eocd_offset + 12)
  assert_true(cd_size > 0)
  // CD offset should point before EOCD
  let cd_offset = read_u32_le(archive, eocd_offset + 16)
  assert_true(cd_offset < eocd_offset)
  assert_eq(cd_offset + cd_size, eocd_offset)
}

///|
test "G2: ZIP compression method field" {
  let data = string_to_bytes(
    "compression method test data repeated repeated repeated",
  )
  // Level 0 -> Store (method 0)
  let files0 : Array[(String, FixedArray[Byte])] = [("s.txt", data)]
  let a0 = @zip.zip_sync(files0, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 0,
  })
  // Compression method at offset 8 in local header
  assert_eq(read_u16_le(a0, 8), 0) // Store
  // Level 6 -> Deflate (method 8)
  let files6 : Array[(String, FixedArray[Byte])] = [("d.txt", data)]
  let a6 = @zip.zip_sync(files6, opts=@types.ZipOptions::{
    ..@types.ZipOptions::default(),
    level: 6,
  })
  assert_eq(read_u16_le(a6, 8), 8) // Deflate
}

// ============================================================
// G-3: 圧縮率検証
// ============================================================

///|
test "G3: level 0 produces larger output than levels 1-9" {
  // Use data where fixed Huffman encoding is slightly more efficient
  // than stored blocks due to per-block overhead differences
  let data = generate_repeat_text(4096)
  let sizes : Array[Int] = []
  for level = 0; level <= 9; level = level + 1 {
    let opts = @types.DeflateOptions::{
      ..@types.DeflateOptions::default(),
      level,
    }
    let compressed = @deflate.deflate_sync(data, opts~)
    sizes.push(compressed.length())
  }
  // Level 0 (stored) adds 5 bytes overhead per block
  // Level 1-9 (fixed Huffman) have consistent encoding size
  // Both produce similar sizes, but level 0 should always be >= level 1-9
  for level = 1; level <= 9; level = level + 1 {
    assert_true(sizes[level] <= sizes[0])
  }
  // All levels 1-9 should produce the same size (same fixed Huffman encoding)
  for level = 2; level <= 9; level = level + 1 {
    assert_eq(sizes[level], sizes[1])
  }
}

///|
test "G3: level 0 produces uncompressed output (stored)" {
  let data = generate_repeat_text(512)
  let opts = @types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: 0,
  }
  let compressed = @deflate.deflate_sync(data, opts~)
  // Stored blocks add overhead (5 bytes per block), so compressed >= original
  assert_true(compressed.length() >= data.length())
}

///|
test "G3: random data does not compress below original size" {
  let data = pseudo_random_data(4096, 12345)
  let opts = @types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: 9,
  }
  let compressed = @deflate.deflate_sync(data, opts~)
  // Fixed Huffman encoding without LZ77 cannot compress random data
  // below its original size - output is at least as large as input
  assert_true(compressed.length() >= data.length())
}

///|
test "G3: wrapper formats add known overhead" {
  let data = generate_repeat_text(2048)
  let deflate_c = @deflate.deflate_sync(data)
  let gzip_c = @gzip.gzip_sync(data)
  let zlib_c = @zlib.zlib_sync(data)
  // GZIP adds 10-byte header + 8-byte footer = 18 bytes overhead
  assert_eq(gzip_c.length(), deflate_c.length() + 18)
  // Zlib adds 2-byte header + 4-byte footer = 6 bytes overhead
  assert_eq(zlib_c.length(), deflate_c.length() + 6)
}

// ============================================================
// G-4: 大規模データテスト
// ============================================================

///|
test "G4: 1MB text data round-trip DEFLATE level 6" {
  let data = generate_repeat_text(1048576) // 1MB
  let compressed = @deflate.deflate_sync(data)
  let decompressed = @deflate.inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "G4: 1MB text data round-trip GZIP level 6" {
  let data = generate_repeat_text(1048576) // 1MB
  let compressed = @gzip.gzip_sync(data)
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "G4: 1MB text data round-trip Zlib level 6" {
  let data = generate_repeat_text(1048576) // 1MB
  let compressed = @zlib.zlib_sync(data)
  let decompressed = @zlib.unzlib_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "G4: 1MB text data round-trip ZIP level 6" {
  let data = generate_repeat_text(1048576) // 1MB
  let files : Array[(String, FixedArray[Byte])] = [("large.txt", data)]
  let archive = @zip.zip_sync(files)
  let extracted = @zip.unzip_sync(archive)
  assert_eq(extracted.length(), 1)
  assert_true(bytes_equal(extracted[0].1, data))
}

///|
test "G4: 100KB binary data round-trip DEFLATE level 6" {
  let data = FixedArray::make(102400, b'\x00') // 100KB
  for i = 0; i < 102400; i = i + 1 {
    data[i] = (i % 256).to_byte()
  }
  let compressed = @deflate.deflate_sync(data)
  let decompressed = @deflate.inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "G4: 100KB binary data round-trip GZIP level 6" {
  let data = FixedArray::make(102400, b'\x00') // 100KB
  for i = 0; i < 102400; i = i + 1 {
    data[i] = (i % 256).to_byte()
  }
  let compressed = @gzip.gzip_sync(data)
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "G4: 100KB binary data round-trip Zlib level 6" {
  let data = FixedArray::make(102400, b'\x00') // 100KB
  for i = 0; i < 102400; i = i + 1 {
    data[i] = (i % 256).to_byte()
  }
  let compressed = @zlib.zlib_sync(data)
  let decompressed = @zlib.unzlib_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "G4: 100KB binary data round-trip ZIP level 6" {
  let data = FixedArray::make(102400, b'\x00') // 100KB
  for i = 0; i < 102400; i = i + 1 {
    data[i] = (i % 256).to_byte()
  }
  let files : Array[(String, FixedArray[Byte])] = [("binary.bin", data)]
  let archive = @zip.zip_sync(files)
  let extracted = @zip.unzip_sync(archive)
  assert_eq(extracted.length(), 1)
  assert_true(bytes_equal(extracted[0].1, data))
}

// ============================================================
// G-5: エッジケース網羅テスト
// ============================================================

///|
test "G5: empty data all APIs" {
  let data : FixedArray[Byte] = []
  // DEFLATE
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_eq(dd.length(), 0)
  // GZIP
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_eq(gd.length(), 0)
  // Zlib
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_eq(zd.length(), 0)
  // ZIP
  let files : Array[(String, FixedArray[Byte])] = [("empty.bin", data)]
  let za = @zip.zip_sync(files)
  let ze = @zip.unzip_sync(za)
  assert_eq(ze.length(), 1)
  assert_eq(ze[0].1.length(), 0)
  // decompress_sync via GZIP
  let gd2 = decompress_sync(gc)
  assert_eq(gd2.length(), 0)
  // decompress_sync via Zlib
  let zd2 = decompress_sync(zc)
  assert_eq(zd2.length(), 0)
  // decompress_sync via raw DEFLATE
  let dd2 = decompress_sync(dc)
  assert_eq(dd2.length(), 0)
}

///|
test "G5: 1-byte data all APIs" {
  let data : FixedArray[Byte] = [b'\xAB']
  // DEFLATE
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  // GZIP
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
  // Zlib
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
  // ZIP
  let files : Array[(String, FixedArray[Byte])] = [("one.bin", data)]
  let za = @zip.zip_sync(files)
  let ze = @zip.unzip_sync(za)
  assert_eq(ze.length(), 1)
  assert_true(bytes_equal(ze[0].1, data))
}

///|
test "G5: all 0x00 1KB all formats" {
  let data = FixedArray::make(1024, b'\x00')
  // DEFLATE
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  // GZIP
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
  // Zlib
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
  // ZIP
  let files : Array[(String, FixedArray[Byte])] = [("zeros.bin", data)]
  let za = @zip.zip_sync(files)
  let ze = @zip.unzip_sync(za)
  assert_true(bytes_equal(ze[0].1, data))
}

///|
test "G5: all 0xFF 1KB all formats" {
  let data = FixedArray::make(1024, b'\xFF')
  // DEFLATE
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  // GZIP
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
  // Zlib
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
  // ZIP
  let files : Array[(String, FixedArray[Byte])] = [("ff.bin", data)]
  let za = @zip.zip_sync(files)
  let ze = @zip.unzip_sync(za)
  assert_true(bytes_equal(ze[0].1, data))
}

///|
test "G5: random data 1KB all formats" {
  let data = pseudo_random_data(1024, 99)
  // DEFLATE
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  // GZIP
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
  // Zlib
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
  // ZIP
  let files : Array[(String, FixedArray[Byte])] = [("rand.bin", data)]
  let za = @zip.zip_sync(files)
  let ze = @zip.unzip_sync(za)
  assert_true(bytes_equal(ze[0].1, data))
}

///|
test "G5: 64KB boundary - 65534 bytes" {
  let size = 65534
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = (i % 251).to_byte()
  }
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
}

///|
test "G5: 64KB boundary - 65535 bytes" {
  let size = 65535
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = (i % 251).to_byte()
  }
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
}

///|
test "G5: 64KB boundary - 65536 bytes" {
  let size = 65536
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = (i % 251).to_byte()
  }
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
}

///|
test "G5: 64KB boundary - 65537 bytes" {
  let size = 65537
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = (i % 251).to_byte()
  }
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  let gc = @gzip.gzip_sync(data)
  let gd = @gzip.gunzip_sync(gc)
  assert_true(bytes_equal(data, gd))
}

///|
test "G5: 32KB boundary - 32767 bytes" {
  let size = 32767
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = (i % 251).to_byte()
  }
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
}

///|
test "G5: 32KB boundary - 32768 bytes" {
  let size = 32768
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = (i % 251).to_byte()
  }
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
}

///|
test "G5: 32KB boundary - 32769 bytes" {
  let size = 32769
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = (i % 251).to_byte()
  }
  let dc = @deflate.deflate_sync(data)
  let dd = @deflate.inflate_sync(dc)
  assert_true(bytes_equal(data, dd))
  let zc = @zlib.zlib_sync(data)
  let zd = @zlib.unzlib_sync(zc)
  assert_true(bytes_equal(data, zd))
}
