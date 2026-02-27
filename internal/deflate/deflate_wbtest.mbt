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

// === inflate basic tests (Type 0 stored blocks) ===

///|
test "inflate: empty stored block" {
  // A stored block with 0 bytes: BFINAL=1, BTYPE=00, then byte-aligned LEN=0, NLEN=0xFFFF
  // Bits: 1 (BFINAL) + 00 (BTYPE) = 0b001 = 0x01, then pad to byte boundary
  // Byte 0: 0x01 (BFINAL=1, BTYPE=00, pad=00000)
  // Bytes 1-2: 0x00, 0x00 (LEN=0)
  // Bytes 3-4: 0xFF, 0xFF (NLEN=0xFFFF)
  let data : FixedArray[Byte] = [b'\x01', b'\x00', b'\x00', b'\xFF', b'\xFF']
  let result = inflate_sync(data)
  assert_eq(result.length(), 0)
}

///|
test "inflate: stored block with data" {
  // Stored block with 3 bytes: [0x41, 0x42, 0x43] = "ABC"
  // BFINAL=1, BTYPE=00
  // Byte 0: 0x01
  // LEN=3 (0x03, 0x00), NLEN=0xFFFC (0xFC, 0xFF)
  // Data: 0x41, 0x42, 0x43
  let data : FixedArray[Byte] = [
    b'\x01', b'\x03', b'\x00', b'\xFC', b'\xFF', b'\x41', b'\x42', b'\x43',
  ]
  let result = inflate_sync(data)
  assert_eq(result.length(), 3)
  assert_eq(result[0], b'\x41')
  assert_eq(result[1], b'\x42')
  assert_eq(result[2], b'\x43')
}

// === deflate/inflate round-trip tests ===

///|
test "deflate level 0: empty data round-trip" {
  let data : FixedArray[Byte] = []
  let compressed = deflate_sync(data, opts=@types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: 0,
  })
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "deflate level 0: small data round-trip" {
  let data = string_to_bytes("Hello world!")
  let compressed = deflate_sync(data, opts=@types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: 0,
  })
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "deflate level 0: 1 byte round-trip" {
  let data : FixedArray[Byte] = [b'\x42']
  let compressed = deflate_sync(data, opts=@types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: 0,
  })
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "deflate level 0: all zeros 1KB round-trip" {
  let data = fill_bytes(b'\x00', 1024)
  let compressed = deflate_sync(data, opts=@types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: 0,
  })
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "deflate level 0: large data 64KB+ round-trip" {
  let data = fill_bytes(b'\xAB', 65536)
  let compressed = deflate_sync(data, opts=@types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: 0,
  })
  // Store blocks: should be larger than input (overhead per block)
  assert_true(compressed.length() > data.length())
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "deflate level 0: 65535 bytes (single block boundary)" {
  let data = fill_bytes(b'\x01', 65535)
  let compressed = deflate_sync(data, opts=@types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: 0,
  })
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === Fixed Huffman (level 1-9) round-trip tests ===

///|
test "deflate level 6: empty data round-trip" {
  let data : FixedArray[Byte] = []
  let compressed = deflate_sync(data)
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "deflate level 6: 'Hello world!' round-trip" {
  let data = string_to_bytes("Hello world!")
  let compressed = deflate_sync(data)
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "deflate level 6: all zeros 1KB round-trip" {
  let data = fill_bytes(b'\x00', 1024)
  let compressed = deflate_sync(data)
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "deflate level 6: binary data round-trip" {
  let data = FixedArray::make(256, b'\x00')
  for i = 0; i < 256; i = i + 1 {
    data[i] = i.to_byte()
  }
  let compressed = deflate_sync(data)
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === Error tests ===

///|
test "inflate: truncated data" {
  let data : FixedArray[Byte] = [b'\x01']
  let mut got_error = false
  try {
    let _ = inflate_sync(data)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "inflate: invalid block type 3" {
  // BFINAL=1, BTYPE=11 (invalid) = 0b111 = 0x07
  let data : FixedArray[Byte] = [b'\x07']
  let mut got_error = false
  try {
    let _ = inflate_sync(data)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "inflate: stored block len/nlen mismatch" {
  // BFINAL=1, BTYPE=00, LEN=1, NLEN=0 (should be 0xFFFE)
  let data : FixedArray[Byte] = [
    b'\x01', b'\x01', b'\x00', b'\x00', b'\x00', b'\x41',
  ]
  let mut got_error = false
  try {
    let _ = inflate_sync(data)
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

// === dopt tests ===

///|
test "dopt: clamps level" {
  let opts = @types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: 15,
  }
  let params = dopt(opts)
  assert_eq(params[0], 9)
}

///|
test "dopt: clamps negative level to 0" {
  let opts = @types.DeflateOptions::{
    ..@types.DeflateOptions::default(),
    level: -1,
  }
  let params = dopt(opts)
  assert_eq(params[0], 0)
}

///|
test "dopt: clamps mem above 12 to 12" {
  let opts = @types.DeflateOptions::{ level: 6, mem: 20, dictionary: None }
  let params = dopt(opts)
  assert_eq(params[1], 12)
}

///|
test "dopt: clamps negative mem to 0" {
  let opts = @types.DeflateOptions::{ level: 6, mem: -5, dictionary: None }
  let params = dopt(opts)
  assert_eq(params[1], 0)
}

///|
test "deflate: dictionary option raises error" {
  let data = string_to_bytes("test")
  let dict : FixedArray[Byte] = [b'\x01', b'\x02', b'\x03']
  let mut got_error = false
  try {
    let _ = deflate_sync(data, opts=@types.DeflateOptions::{
      level: 6,
      mem: 4,
      dictionary: Some(dict),
    })
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "deflate level 6: 70000 bytes round-trip (multi-block)" {
  let data = FixedArray::make(70000, b'\x00')
  for i = 0; i < 70000; i = i + 1 {
    data[i] = (i % 256).to_byte()
  }
  let compressed = deflate_sync(data)
  let decompressed = inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "inflate: with size hint" {
  let data = string_to_bytes("Hello world with size hint!")
  let compressed = deflate_sync(data)
  let decompressed = inflate_sync(compressed, opts=@types.InflateOptions::{
    size: Some(data.length()),
    dictionary: None,
  })
  assert_true(bytes_equal(data, decompressed))
}
