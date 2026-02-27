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

// === A-T1: LZ77 unit tests ===

///|
test "find_match: detects 'abcabc' pattern (distance=3, length=3)" {
  let data = string_to_bytes("abcabc")
  let dl = data.length()
  let hash_size = 1 << (4 + 8) // mem=4
  let hsh : FixedArray[Int] = FixedArray::make(hash_size, 0)
  let prev : FixedArray[Int] = FixedArray::make(32768, 0)
  // Insert hashes for positions 0, 1, 2
  for i = 0; i < 3; i = i + 1 {
    if i + 2 < dl {
      let h = (
          (data[i].to_int() << 16) |
          (data[i + 1].to_int() << 8) |
          data[i + 2].to_int()
        ) %
        hash_size
      prev[i & 32767] = hsh[h]
      hsh[h] = i + 1 // 1-based
    }
  }
  // Now find match at position 3 ("abc" should match position 0)
  let (mlen, mdist) = find_match(data, 3, dl, hsh, prev, hash_size, 128, 258)
  assert_eq(mlen, 3)
  assert_eq(mdist, 3)
}

///|
test "find_match: minimum match length is 3" {
  // "abab" - at position 2, "ab" is only 2 bytes, should not match
  let data = string_to_bytes("abXab")
  let dl = data.length()
  let hash_size = 1 << (4 + 8)
  let hsh : FixedArray[Int] = FixedArray::make(hash_size, 0)
  let prev : FixedArray[Int] = FixedArray::make(32768, 0)
  // Insert hashes for positions 0, 1
  for i = 0; i < 2; i = i + 1 {
    if i + 2 < dl {
      let h = (
          (data[i].to_int() << 16) |
          (data[i + 1].to_int() << 8) |
          data[i + 2].to_int()
        ) %
        hash_size
      prev[i & 32767] = hsh[h]
      hsh[h] = i + 1
    }
  }
  // At position 3, "abX" != "Xab" - different hash, no 3-byte match
  // The hash of "ab" at position 3 won't match because it's different trigram
  let (mlen, _) = find_match(data, 3, dl, hsh, prev, hash_size, 128, 258)
  // No match because "abX" != "ab " trigram differs
  assert_true(mlen == 0 || mlen >= 3)
}

///|
test "find_match: max match length 258" {
  // Create data with 300+ identical bytes
  let data = FixedArray::make(520, b'\x41')
  let dl = data.length()
  let hash_size = 1 << (4 + 8)
  let hsh : FixedArray[Int] = FixedArray::make(hash_size, 0)
  let prev : FixedArray[Int] = FixedArray::make(32768, 0)
  // Insert hash for position 0
  let h0 = (
      (data[0].to_int() << 16) | (data[1].to_int() << 8) | data[2].to_int()
    ) %
    hash_size
  prev[0] = hsh[h0]
  hsh[h0] = 1 // 1-based
  // Find match at position 1
  let (mlen, mdist) = find_match(data, 1, dl, hsh, prev, hash_size, 128, 258)
  assert_eq(mlen, 258) // Capped at 258
  assert_eq(mdist, 1)
}

///|
test "find_match: max distance 32768" {
  // Create data where match is at exactly distance 32768
  let size = 32774
  let data = FixedArray::make(size, b'\x00')
  // Place unique pattern at position 0 and position 32768
  data[0] = b'\x61'
  data[1] = b'\x62'
  data[2] = b'\x63'
  // Make bytes after position 0's "abc" differ from position 32768's
  data[3] = b'\xFF'
  data[32768] = b'\x61'
  data[32769] = b'\x62'
  data[32770] = b'\x63'
  data[32771] = b'\x00'
  let dl = data.length()
  let hash_size = 1 << (4 + 8)
  let hsh : FixedArray[Int] = FixedArray::make(hash_size, 0)
  let prev : FixedArray[Int] = FixedArray::make(32768, 0)
  // Insert hash for position 0
  let h0 = (
      (data[0].to_int() << 16) | (data[1].to_int() << 8) | data[2].to_int()
    ) %
    hash_size
  prev[0] = hsh[h0]
  hsh[h0] = 1 // 1-based
  // Find match at position 32768 (distance = 32768, at boundary)
  let (mlen, mdist) = find_match(
    data, 32768, dl, hsh, prev, hash_size, 32768, 258,
  )
  assert_eq(mlen, 3)
  assert_eq(mdist, 32768)
}

///|
test "find_match: distance > 32768 yields no match" {
  let size = 32802
  let data = FixedArray::make(size, b'\x00')
  data[0] = b'\x61'
  data[1] = b'\x62'
  data[2] = b'\x63'
  data[32769] = b'\x61'
  data[32770] = b'\x62'
  data[32771] = b'\x63'
  let dl = data.length()
  let hash_size = 1 << (4 + 8)
  let hsh : FixedArray[Int] = FixedArray::make(hash_size, 0)
  let prev : FixedArray[Int] = FixedArray::make(32768, 0)
  // Insert hash for position 0
  let h0 = (
      (data[0].to_int() << 16) | (data[1].to_int() << 8) | data[2].to_int()
    ) %
    hash_size
  prev[0] = hsh[h0]
  hsh[h0] = 1
  // Position 32769: distance = 32769 > 32768
  let (mlen, _) = find_match(data, 32769, dl, hsh, prev, hash_size, 32768, 258)
  assert_eq(mlen, 0)
}

///|
test "find_match: no match with less than 3 remaining bytes" {
  let data = string_to_bytes("ab")
  let dl = data.length()
  let hash_size = 1 << (4 + 8)
  let hsh : FixedArray[Int] = FixedArray::make(hash_size, 0)
  let prev : FixedArray[Int] = FixedArray::make(32768, 0)
  // At position 0, only 2 bytes remain
  let (mlen, _) = find_match(data, 0, dl, hsh, prev, hash_size, 128, 258)
  assert_eq(mlen, 0)
}

///|
test "find_match: longer match preferred over shorter" {
  // "abcXabcabc" - at position 7, "abc" matches both position 0 (len=3) and position 4 (len=3)
  let data = string_to_bytes("abcdabcdabcd")
  let dl = data.length()
  let hash_size = 1 << (4 + 8)
  let hsh : FixedArray[Int] = FixedArray::make(hash_size, 0)
  let prev : FixedArray[Int] = FixedArray::make(32768, 0)
  // Insert hashes for positions 0-7
  for i = 0; i < 8; i = i + 1 {
    if i + 2 < dl {
      let h = (
          (data[i].to_int() << 16) |
          (data[i + 1].to_int() << 8) |
          data[i + 2].to_int()
        ) %
        hash_size
      prev[i & 32767] = hsh[h]
      hsh[h] = i + 1
    }
  }
  // At position 8, "abcd" matches position 4 (len=4, dist=4) and position 0 (len=4, dist=8)
  let (mlen, _) = find_match(data, 8, dl, hsh, prev, hash_size, 128, 258)
  assert_eq(mlen, 4)
}

///|
test "auto_mem: small data gets low mem" {
  assert_eq(auto_mem(100, 0), 1)
  assert_eq(auto_mem(256, 0), 1)
}

///|
test "auto_mem: medium data gets medium mem" {
  assert_eq(auto_mem(512, 0), 2)
  assert_eq(auto_mem(1024, 0), 2)
  assert_eq(auto_mem(4096, 0), 3)
}

///|
test "auto_mem: large data gets default mem" {
  assert_eq(auto_mem(10000, 0), 4)
  assert_eq(auto_mem(100000, 0), 4)
}

///|
test "auto_mem: user-specified mem is respected" {
  assert_eq(auto_mem(100, 8), 8)
  assert_eq(auto_mem(100000, 2), 2)
}
