///|
/// Convert a string to UTF-8 byte array.
/// MoonBit strings use UTF-16 internally, so we iterate over characters
/// and encode each Unicode codepoint to 1-4 UTF-8 bytes.
pub fn str_to_u8(s : String) -> FixedArray[Byte] {
  // First pass: calculate total byte length
  let mut byte_len = 0
  for c in s {
    let cp = c.to_int()
    if cp <= 0x7F {
      byte_len += 1
    } else if cp <= 0x7FF {
      byte_len += 2
    } else if cp <= 0xFFFF {
      byte_len += 3
    } else {
      byte_len += 4
    }
  }
  let result = FixedArray::make(byte_len, b'\x00')
  let mut idx = 0
  for c in s {
    let cp = c.to_int()
    if cp <= 0x7F {
      result[idx] = cp.to_byte()
      idx += 1
    } else if cp <= 0x7FF {
      result[idx] = (0xC0 | (cp >> 6)).to_byte()
      result[idx + 1] = (0x80 | (cp & 0x3F)).to_byte()
      idx += 2
    } else if cp <= 0xFFFF {
      result[idx] = (0xE0 | (cp >> 12)).to_byte()
      result[idx + 1] = (0x80 | ((cp >> 6) & 0x3F)).to_byte()
      result[idx + 2] = (0x80 | (cp & 0x3F)).to_byte()
      idx += 3
    } else {
      result[idx] = (0xF0 | (cp >> 18)).to_byte()
      result[idx + 1] = (0x80 | ((cp >> 12) & 0x3F)).to_byte()
      result[idx + 2] = (0x80 | ((cp >> 6) & 0x3F)).to_byte()
      result[idx + 3] = (0x80 | (cp & 0x3F)).to_byte()
      idx += 4
    }
  }
  result
}

///|
/// Check if a byte is a valid UTF-8 continuation byte (10xxxxxx).
fn is_continuation(b : Int) -> Bool {
  (b & 0xC0) == 0x80
}

///|
/// Convert UTF-8 byte array back to string.
/// Validates UTF-8 sequences and raises InvalidUTF8 error on malformed input.
pub fn str_from_u8(data : FixedArray[Byte]) -> String raise @types.FlateError {
  let buf = StringBuilder::new()
  let len = data.length()
  let mut i = 0
  while i < len {
    let b0 = data[i].to_int()
    if b0 <= 0x7F {
      // 1-byte sequence: 0xxxxxxx
      buf.write_char(Int::unsafe_to_char(b0))
      i += 1
    } else if (b0 & 0xE0) == 0xC0 {
      // 2-byte sequence: 110xxxxx 10xxxxxx
      if i + 1 >= len {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      let b1 = data[i + 1].to_int()
      if not(is_continuation(b1)) {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      if cp < 0x80 {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      buf.write_char(Int::unsafe_to_char(cp))
      i += 2
    } else if (b0 & 0xF0) == 0xE0 {
      // 3-byte sequence: 1110xxxx 10xxxxxx 10xxxxxx
      if i + 2 >= len {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      let b1 = data[i + 1].to_int()
      let b2 = data[i + 2].to_int()
      if not(is_continuation(b1)) || not(is_continuation(b2)) {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      if cp < 0x800 {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      buf.write_char(Int::unsafe_to_char(cp))
      i += 3
    } else if (b0 & 0xF8) == 0xF0 {
      // 4-byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
      if i + 3 >= len {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      let b1 = data[i + 1].to_int()
      let b2 = data[i + 2].to_int()
      let b3 = data[i + 3].to_int()
      if not(is_continuation(b1)) ||
        not(is_continuation(b2)) ||
        not(is_continuation(b3)) {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      let cp = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
      }
      buf.write_char(Int::unsafe_to_char(cp))
      i += 4
    } else {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidUTF8)
    }
  }
  buf.to_string()
}
