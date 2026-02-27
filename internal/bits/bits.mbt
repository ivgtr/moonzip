///|
/// Read up to 15 bits from a byte array at a given bit position.
/// Returns the value of the bits read.
pub fn bits(data : FixedArray[Byte], pos : Int, count : Int) -> Int {
  let byte_pos = pos >> 3
  let bit_offset = pos & 7
  // Read up to 3 bytes to cover the bit range
  let mut v = data[byte_pos].to_int()
  if byte_pos + 1 < data.length() {
    v = v | (data[byte_pos + 1].to_int() << 8)
  }
  if byte_pos + 2 < data.length() {
    v = v | (data[byte_pos + 2].to_int() << 16)
  }
  (v >> bit_offset) & ((1 << count) - 1)
}

///|
/// Read 16 or more bits from a byte array at a given bit position.
pub fn bits16(data : FixedArray[Byte], pos : Int, count : Int) -> Int {
  let byte_pos = pos >> 3
  let bit_offset = pos & 7
  let mut v = data[byte_pos].to_int()
  if byte_pos + 1 < data.length() {
    v = v | (data[byte_pos + 1].to_int() << 8)
  }
  if byte_pos + 2 < data.length() {
    v = v | (data[byte_pos + 2].to_int() << 16)
  }
  if byte_pos + 3 < data.length() {
    v = v | (data[byte_pos + 3].to_int() << 24)
  }
  (v >> bit_offset) & ((1 << count) - 1)
}

///|
/// Write bits to a byte array at a given bit position.
pub fn wbits(
  data : FixedArray[Byte],
  pos : Int,
  value : Int,
  count : Int,
) -> Unit {
  let byte_pos = pos >> 3
  let bit_offset = pos & 7
  let mask = value << bit_offset
  data[byte_pos] = (data[byte_pos].to_int() | (mask & 0xFF)).to_byte()
  if byte_pos + 1 < data.length() {
    data[byte_pos + 1] = (data[byte_pos + 1].to_int() | ((mask >> 8) & 0xFF)).to_byte()
  }
  if byte_pos + 2 < data.length() && bit_offset + count > 16 {
    data[byte_pos + 2] = (data[byte_pos + 2].to_int() | ((mask >> 16) & 0xFF)).to_byte()
  }
}

///|
/// Write 16 or more bits to a byte array at a given bit position.
pub fn wbits16(
  data : FixedArray[Byte],
  pos : Int,
  value : Int,
  count : Int,
) -> Unit {
  let byte_pos = pos >> 3
  let bit_offset = pos & 7
  let mask = value << bit_offset
  data[byte_pos] = (data[byte_pos].to_int() | (mask & 0xFF)).to_byte()
  if byte_pos + 1 < data.length() {
    data[byte_pos + 1] = (data[byte_pos + 1].to_int() | ((mask >> 8) & 0xFF)).to_byte()
  }
  if byte_pos + 2 < data.length() {
    data[byte_pos + 2] = (data[byte_pos + 2].to_int() | ((mask >> 16) & 0xFF)).to_byte()
  }
  if byte_pos + 3 < data.length() && bit_offset + count > 24 {
    data[byte_pos + 3] = (data[byte_pos + 3].to_int() | ((mask >> 24) & 0xFF)).to_byte()
  }
}

///|
/// Advance to the next byte boundary.
/// Returns the bit position aligned to the next byte.
pub fn shft(pos : Int) -> Int {
  (pos + 7) >> 3 << 3
}

///|
/// Read a 2-byte little-endian unsigned integer.
pub fn b2(data : FixedArray[Byte], offset : Int) -> Int {
  data[offset].to_int() | (data[offset + 1].to_int() << 8)
}

///|
/// Read a 4-byte little-endian unsigned integer.
pub fn b4(data : FixedArray[Byte], offset : Int) -> Int {
  data[offset].to_int() |
  (data[offset + 1].to_int() << 8) |
  (data[offset + 2].to_int() << 16) |
  (data[offset + 3].to_int() << 24)
}

///|
/// Read an 8-byte little-endian unsigned integer (for ZIP64).
fn b8(data : FixedArray[Byte], offset : Int) -> Int64 {
  let lo = b4(data, offset).to_int64() & 0xFFFFFFFFL
  let hi = b4(data, offset + 4).to_int64() & 0xFFFFFFFFL
  lo | (hi << 32)
}

///|
/// Write a 2-byte little-endian unsigned integer.
pub fn wbytes2(data : FixedArray[Byte], offset : Int, value : Int) -> Unit {
  data[offset] = (value & 0xFF).to_byte()
  data[offset + 1] = ((value >> 8) & 0xFF).to_byte()
}

///|
/// Write a 4-byte little-endian unsigned integer.
pub fn wbytes4(data : FixedArray[Byte], offset : Int, value : Int) -> Unit {
  data[offset] = (value & 0xFF).to_byte()
  data[offset + 1] = ((value >> 8) & 0xFF).to_byte()
  data[offset + 2] = ((value >> 16) & 0xFF).to_byte()
  data[offset + 3] = ((value >> 24) & 0xFF).to_byte()
}
