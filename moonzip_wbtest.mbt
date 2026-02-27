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
