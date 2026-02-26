///|
/// CRC32 lookup table (polynomial 0xEDB88320, reflected form).
let crc32_table : FixedArray[UInt] = {
  let t : FixedArray[UInt] = FixedArray::make(256, 0U)
  for i = 0; i < 256; i = i + 1 {
    let mut c = i.reinterpret_as_uint()
    for _k = 0; _k < 8; _k = _k + 1 {
      if (c & 1U) != 0U {
        c = 0xEDB88320U ^ (c >> 1)
      } else {
        c = c >> 1
      }
    }
    t[i] = c
  }
  t
}

///|
/// Compute CRC32 checksum of data (one-shot).
pub fn crc32(data : FixedArray[Byte]) -> UInt {
  let c = crc32_update(0xFFFFFFFFU, data, offset=0, length=data.length())
  c ^ 0xFFFFFFFFU
}

///|
/// Incrementally update CRC32 state.
/// Initial state should be 0xFFFFFFFF. Finalize with XOR 0xFFFFFFFF.
pub fn crc32_update(
  prev : UInt,
  data : FixedArray[Byte],
  offset? : Int = 0,
  length? : Int = -1,
) -> UInt {
  let len = if length < 0 { data.length() - offset } else { length }
  let mut c = prev
  for i = offset; i < offset + len; i = i + 1 {
    let b = data[i].to_uint()
    c = crc32_table[((c & 0xFFU) ^ b).reinterpret_as_int()] ^ (c >> 8)
  }
  c
}

///|
/// Adler-32 modulus.
let adler32_mod : UInt = 65521U

///|
/// Compute Adler-32 checksum of data (one-shot).
pub fn adler32(data : FixedArray[Byte]) -> UInt {
  adler32_update(1U, data, offset=0, length=data.length())
}

///|
/// Incrementally update Adler-32 state.
/// Initial state should be 1. The value is the checksum at all times.
pub fn adler32_update(
  prev : UInt,
  data : FixedArray[Byte],
  offset? : Int = 0,
  length? : Int = -1,
) -> UInt {
  let len = if length < 0 { data.length() - offset } else { length }
  let mut a = prev & 0xFFFFU
  let mut b = prev >> 16
  let end = offset + len
  let mut i = offset
  while i < end {
    let chunk_end = if i + 2655 < end { i + 2655 } else { end }
    while i < chunk_end {
      a = a + data[i].to_uint()
      b = b + a
      i = i + 1
    }
    a = a % adler32_mod
    b = b % adler32_mod
  }
  (b << 16) | a
}
