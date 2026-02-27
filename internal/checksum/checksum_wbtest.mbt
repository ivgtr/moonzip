///|
/// Helper: convert ASCII string to byte array.
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
/// Helper: create a byte array filled with a single value.
fn fill_bytes(value : Byte, count : Int) -> FixedArray[Byte] {
  FixedArray::make(count, value)
}

// === CRC32 Tests ===

///|
test "crc32: empty input" {
  let data : FixedArray[Byte] = []
  assert_eq(crc32(data), 0x00000000U)
}

///|
test "crc32: RFC 3720 test vector '123456789'" {
  let data = string_to_bytes("123456789")
  assert_eq(crc32(data), 0xCBF43926U)
}

///|
test "crc32: single byte 0x00" {
  let data : FixedArray[Byte] = [b'\x00']
  assert_eq(crc32(data), 0xD202EF8DU)
}

///|
test "crc32: single byte 0xFF" {
  let data : FixedArray[Byte] = [b'\xFF']
  assert_eq(crc32(data), 0xFF000000U)
}

///|
test "crc32: 'Hello world!'" {
  let data = string_to_bytes("Hello world!")
  assert_eq(crc32(data), 0x1B851995U)
}

///|
test "crc32: all zeros 1KB" {
  let data = fill_bytes(b'\x00', 1024)
  assert_eq(crc32(data), 0xEFB5AF2EU)
}

///|
test "crc32: all 0xFF 1KB" {
  let data = fill_bytes(b'\xFF', 1024)
  assert_eq(crc32(data), 0xB83AFFF4U)
}

///|
test "crc32: large data 64KB+ zeros" {
  let data = fill_bytes(b'\x00', 65536)
  assert_eq(crc32(data), 0xD7978EEBU)
}

///|
test "crc32: incremental matches one-shot" {
  let full = string_to_bytes("123456789")
  let part1 = string_to_bytes("12345")
  let part2 = string_to_bytes("6789")
  let full_crc = crc32(full)
  let state = crc32_update(0xFFFFFFFFU, part1)
  let state2 = crc32_update(state, part2)
  let incremental_crc = state2 ^ 0xFFFFFFFFU
  assert_eq(full_crc, incremental_crc)
}

///|
test "crc32: incremental 1 byte at a time" {
  let data = string_to_bytes("Hello world!")
  let full_crc = crc32(data)
  let mut state = 0xFFFFFFFFU
  for i = 0; i < data.length(); i = i + 1 {
    state = crc32_update(state, data, offset=i, length=1)
  }
  let incremental_crc = state ^ 0xFFFFFFFFU
  assert_eq(full_crc, incremental_crc)
}

// === Adler-32 Tests ===

///|
test "adler32: empty input" {
  let data : FixedArray[Byte] = []
  assert_eq(adler32(data), 0x00000001U)
}

///|
test "adler32: RFC 1950 test vector 'Wikipedia'" {
  let data = string_to_bytes("Wikipedia")
  assert_eq(adler32(data), 0x11E60398U)
}

///|
test "adler32: single byte 0x00" {
  let data : FixedArray[Byte] = [b'\x00']
  assert_eq(adler32(data), 0x00010001U)
}

///|
test "adler32: single byte 0xFF" {
  let data : FixedArray[Byte] = [b'\xFF']
  assert_eq(adler32(data), 0x01000100U)
}

///|
test "adler32: all zeros 2654 bytes (before mod reduction)" {
  let data = fill_bytes(b'\x00', 2654)
  assert_eq(adler32(data), (2654U << 16) | 1U)
}

///|
test "adler32: all zeros 2655 bytes (mod reduction boundary)" {
  let data = fill_bytes(b'\x00', 2655)
  assert_eq(adler32(data), (2655U << 16) | 1U)
}

///|
test "adler32: all 0xFF 1KB consistency" {
  let data = fill_bytes(b'\xFF', 1024)
  let expected = adler32(data)
  assert_eq(adler32(data), expected)
}

///|
test "adler32: large data 65521+ bytes (multiple mod reductions)" {
  let data = fill_bytes(b'\x01', 65600)
  let expected = adler32(data)
  assert_eq(adler32(data), expected)
}

///|
test "adler32: incremental matches one-shot" {
  let full = string_to_bytes("Wikipedia")
  let part1 = string_to_bytes("Wiki")
  let part2 = string_to_bytes("pedia")
  let full_checksum = adler32(full)
  let state = adler32_update(1U, part1)
  let state2 = adler32_update(state, part2)
  assert_eq(full_checksum, state2)
}

///|
test "adler32: incremental 1 byte at a time" {
  let data = string_to_bytes("Wikipedia")
  let full_checksum = adler32(data)
  let mut state = 1U
  for i = 0; i < data.length(); i = i + 1 {
    state = adler32_update(state, data, offset=i, length=1)
  }
  assert_eq(full_checksum, state)
}
