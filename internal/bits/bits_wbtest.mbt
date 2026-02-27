// === bits() read tests ===

///|
test "bits: read 1 bit from position 0" {
  let data : FixedArray[Byte] = [b'\x01']
  assert_eq(bits(data, 0, 1), 1)
}

///|
test "bits: read 8 bits from position 0" {
  let data : FixedArray[Byte] = [b'\xAB']
  assert_eq(bits(data, 0, 8), 0xAB)
}

///|
test "bits: read 3 bits crossing byte boundary" {
  // Byte 0: 0xF0 = bits[0..7] = 0,0,0,0,1,1,1,1 (LSB first)
  // Byte 1: 0x03 = bits[8..15] = 1,1,0,0,0,0,0,0 (LSB first)
  // At bit 6, reading 3 bits: bit6=1, bit7=1, bit8=1 → 0b111 = 7
  let data : FixedArray[Byte] = [b'\xF0', b'\x03']
  assert_eq(bits(data, 6, 3), 7)
}

///|
test "bits: read 15 bits" {
  let data : FixedArray[Byte] = [b'\xFF', b'\x7F']
  assert_eq(bits(data, 0, 15), 0x7FFF)
}

///|
test "bits: read from various bit offsets" {
  // 0xA5 = 0b10100101
  let data : FixedArray[Byte] = [b'\xA5']
  assert_eq(bits(data, 0, 1), 1) // bit 0
  assert_eq(bits(data, 1, 1), 0) // bit 1
  assert_eq(bits(data, 2, 1), 1) // bit 2
  assert_eq(bits(data, 5, 1), 1) // bit 5
}

// === bits16() read tests ===

///|
test "bits16: read 16 bits" {
  let data : FixedArray[Byte] = [b'\x34', b'\x12']
  assert_eq(bits16(data, 0, 16), 0x1234)
}

///|
test "bits16: read crossing byte boundary" {
  let data : FixedArray[Byte] = [b'\x00', b'\x34', b'\x12', b'\x00']
  assert_eq(bits16(data, 8, 16), 0x1234)
}

// === wbits() write tests ===

///|
test "wbits: write 1 bit" {
  let data : FixedArray[Byte] = [b'\x00']
  wbits(data, 0, 1, 1)
  assert_eq(data[0], b'\x01')
}

///|
test "wbits: write 8 bits" {
  let data : FixedArray[Byte] = [b'\x00']
  wbits(data, 0, 0xAB, 8)
  assert_eq(data[0], b'\xAB')
}

///|
test "wbits: write crossing byte boundary" {
  let data : FixedArray[Byte] = [b'\x00', b'\x00']
  wbits(data, 4, 0xFF, 8)
  assert_eq(data[0], b'\xF0')
  assert_eq(data[1], b'\x0F')
}

// === wbits16() write tests ===

///|
test "wbits16: write 16 bits" {
  let data : FixedArray[Byte] = [b'\x00', b'\x00']
  wbits16(data, 0, 0x1234, 16)
  assert_eq(data[0], b'\x34')
  assert_eq(data[1], b'\x12')
}

// === shft() tests ===

///|
test "shft: already aligned" {
  assert_eq(shft(0), 0)
  assert_eq(shft(8), 8)
  assert_eq(shft(16), 16)
}

///|
test "shft: not aligned" {
  assert_eq(shft(1), 8)
  assert_eq(shft(7), 8)
  assert_eq(shft(9), 16)
  assert_eq(shft(15), 16)
}

// === b2() tests ===

///|
test "b2: little-endian read" {
  let data : FixedArray[Byte] = [b'\x00', b'\x01']
  assert_eq(b2(data, 0), 0x0100)
}

///|
test "b2: 0xFFFF" {
  let data : FixedArray[Byte] = [b'\xFF', b'\xFF']
  assert_eq(b2(data, 0), 0xFFFF)
}

///|
test "b2: 0x0000" {
  let data : FixedArray[Byte] = [b'\x00', b'\x00']
  assert_eq(b2(data, 0), 0x0000)
}

// === b4() tests ===

///|
test "b4: little-endian read" {
  let data : FixedArray[Byte] = [b'\x04', b'\x03', b'\x02', b'\x01']
  assert_eq(b4(data, 0), 0x01020304)
}

///|
test "b4: 0xFFFFFFFF" {
  let data : FixedArray[Byte] = [b'\xFF', b'\xFF', b'\xFF', b'\xFF']
  // In MoonBit Int is 32-bit signed, so 0xFFFFFFFF = -1
  assert_eq(b4(data, 0), -1)
}

// === b8() tests ===

///|
test "b8: little-endian 8 byte read" {
  let data : FixedArray[Byte] = [
    b'\x08', b'\x07', b'\x06', b'\x05', b'\x04', b'\x03', b'\x02', b'\x01',
  ]
  assert_eq(b8(data, 0), 0x0102030405060708L)
}

// === wbytes2() / wbytes4() tests ===

///|
test "wbytes2: little-endian write" {
  let data : FixedArray[Byte] = [b'\x00', b'\x00']
  wbytes2(data, 0, 0x1234)
  assert_eq(data[0], b'\x34')
  assert_eq(data[1], b'\x12')
}

///|
test "wbytes4: little-endian write" {
  let data : FixedArray[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00']
  wbytes4(data, 0, 0x12345678)
  assert_eq(data[0], b'\x78')
  assert_eq(data[1], b'\x56')
  assert_eq(data[2], b'\x34')
  assert_eq(data[3], b'\x12')
}

// === Round-trip tests ===

///|
test "bits/wbits round-trip: various bit lengths" {
  let data : FixedArray[Byte] = FixedArray::make(4, b'\x00')
  // Write 5 bits at position 0
  wbits(data, 0, 0x15, 5)
  assert_eq(bits(data, 0, 5), 0x15)
  // Write 7 bits at position 5
  wbits(data, 5, 0x3A, 7)
  assert_eq(bits(data, 5, 7), 0x3A)
}

///|
test "wbytes/b2/b4 round-trip" {
  let data : FixedArray[Byte] = FixedArray::make(6, b'\x00')
  wbytes2(data, 0, 0xABCD)
  wbytes4(data, 2, 0x12345678)
  assert_eq(b2(data, 0), 0xABCD)
  assert_eq(b4(data, 2), 0x12345678)
}
