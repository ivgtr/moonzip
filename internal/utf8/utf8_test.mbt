// === str_to_u8 Tests ===

///|
test "str_to_u8: ASCII string" {
  let result = @utf8.str_to_u8("Hello")
  let expected : FixedArray[Byte] = [
    b'\x48', b'\x65', b'\x6C', b'\x6C', b'\x6F',
  ]
  assert_eq(result.length(), expected.length())
  for i = 0; i < result.length(); i = i + 1 {
    assert_eq(result[i], expected[i])
  }
}

///|
test "str_to_u8: empty string" {
  let result = @utf8.str_to_u8("")
  assert_eq(result.length(), 0)
}

///|
test "str_to_u8: 2-byte char" {
  let result = @utf8.str_to_u8("\u00E9")
  let expected : FixedArray[Byte] = [b'\xC3', b'\xA9']
  assert_eq(result.length(), expected.length())
  for i = 0; i < result.length(); i = i + 1 {
    assert_eq(result[i], expected[i])
  }
}

///|
test "str_to_u8: 3-byte char" {
  let result = @utf8.str_to_u8("\u65E5")
  let expected : FixedArray[Byte] = [b'\xE6', b'\x97', b'\xA5']
  assert_eq(result.length(), expected.length())
  for i = 0; i < result.length(); i = i + 1 {
    assert_eq(result[i], expected[i])
  }
}

///|
test "str_to_u8: mixed string" {
  let result = @utf8.str_to_u8("Hello\u4E16\u754C")
  // "Hello" = 5 bytes, "世" = 3 bytes, "界" = 3 bytes = 11 bytes total
  assert_eq(result.length(), 11)
  // Verify "Hello" part
  assert_eq(result[0], b'\x48')
  assert_eq(result[1], b'\x65')
  assert_eq(result[2], b'\x6C')
  assert_eq(result[3], b'\x6C')
  assert_eq(result[4], b'\x6F')
  // Verify "世" (U+4E16) = E4 B8 96
  assert_eq(result[5], b'\xE4')
  assert_eq(result[6], b'\xB8')
  assert_eq(result[7], b'\x96')
  // Verify "界" (U+754C) = E7 95 8C
  assert_eq(result[8], b'\xE7')
  assert_eq(result[9], b'\x95')
  assert_eq(result[10], b'\x8C')
}

// === str_from_u8 Tests ===

///|
test "str_from_u8: ASCII" {
  let data : FixedArray[Byte] = [b'\x48', b'\x65', b'\x6C', b'\x6C', b'\x6F']
  let result = @utf8.str_from_u8(data)
  assert_eq(result, "Hello")
}

///|
test "str_from_u8: empty" {
  let data : FixedArray[Byte] = []
  let result = @utf8.str_from_u8(data)
  assert_eq(result, "")
}

///|
test "str_from_u8: multi-byte" {
  // "é" (U+00E9) = C3 A9, "日" (U+65E5) = E6 97 A5
  let data : FixedArray[Byte] = [b'\xC3', b'\xA9', b'\xE6', b'\x97', b'\xA5']
  let result = @utf8.str_from_u8(data)
  assert_eq(result, "\u00E9\u65E5")
}

///|
test "str_from_u8: invalid UTF-8" {
  let data : FixedArray[Byte] = [b'\xFF']
  let mut caught = false
  try {
    let _ = @utf8.str_from_u8(data)
  } catch {
    @types.FlateError(_) => caught = true
  }
  assert_true(caught)
}

///|
test "str_from_u8: truncated multi-byte" {
  let data : FixedArray[Byte] = [b'\xC3']
  let mut caught = false
  try {
    let _ = @utf8.str_from_u8(data)
  } catch {
    @types.FlateError(_) => caught = true
  }
  assert_true(caught)
}

// === Round-trip Tests ===

///|
test "round-trip: ASCII" {
  let original = "Hello, World!"
  let bytes = @utf8.str_to_u8(original)
  let decoded = @utf8.str_from_u8(bytes)
  assert_eq(decoded, original)
}

///|
test "round-trip: multi-byte" {
  let original = "\u00E9\u65E5\u4E16\u754C"
  let bytes = @utf8.str_to_u8(original)
  let decoded = @utf8.str_from_u8(bytes)
  assert_eq(decoded, original)
}

///|
test "round-trip: mixed" {
  let original = "Hello \u4E16\u754C!"
  let bytes = @utf8.str_to_u8(original)
  let decoded = @utf8.str_from_u8(bytes)
  assert_eq(decoded, original)
}
