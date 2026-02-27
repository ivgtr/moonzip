///|
fn str_to_bytes(s : String) -> FixedArray[Byte] {
  let buf = Array::new()
  for c in s {
    let cp = c.to_int()
    if cp < 0x80 {
      buf.push(cp.to_byte())
    } else if cp < 0x800 {
      buf.push((0xC0 | (cp >> 6)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp < 0x10000 {
      buf.push((0xE0 | (cp >> 12)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      buf.push((0xF0 | (cp >> 18)).to_byte())
      buf.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  let arr = FixedArray::make(buf.length(), b'\x00')
  for i = 0; i < buf.length(); i = i + 1 {
    arr[i] = buf[i]
  }
  arr
}

///|
fn bytes_to_str(data : FixedArray[Byte]) -> String {
  let sb = StringBuilder::new()
  let len = data.length()
  let mut i = 0
  while i < len {
    let b0 = data[i].to_int()
    if b0 < 0x80 {
      sb.write_char(b0.unsafe_to_char())
      i = i + 1
    } else if (b0 & 0xE0) == 0xC0 && i + 1 < len {
      let cp = ((b0 & 0x1F) << 6) | (data[i + 1].to_int() & 0x3F)
      sb.write_char(cp.unsafe_to_char())
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 && i + 2 < len {
      let cp = ((b0 & 0x0F) << 12) | ((data[i + 1].to_int() & 0x3F) << 6) | (data[
        i + 2
      ].to_int() & 0x3F)
      sb.write_char(cp.unsafe_to_char())
      i = i + 3
    } else if (b0 & 0xF8) == 0xF0 && i + 3 < len {
      let cp = ((b0 & 0x07) << 18) | ((data[i + 1].to_int() & 0x3F) << 12) | ((data[
        i + 2
      ].to_int() & 0x3F) << 6) | (data[i + 3].to_int() & 0x3F)
      sb.write_char(cp.unsafe_to_char())
      i = i + 4
    } else {
      sb.write_char('?')
      i = i + 1
    }
  }
  sb.to_string()
}

///|
fn bytes_to_hex(data : FixedArray[Byte]) -> String {
  let sb = StringBuilder::new()
  let hex_chars : FixedArray[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e',
    'f',
  ]
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    sb.write_char(hex_chars[b >> 4])
    sb.write_char(hex_chars[b & 0x0F])
  }
  sb.to_string()
}

///|
fn hex_to_bytes(s : String) -> FixedArray[Byte] {
  let chars = Array::new()
  for c in s {
    chars.push(c)
  }
  let len = chars.length() / 2
  let arr = FixedArray::make(len, b'\x00')
  for i = 0; i < len; i = i + 1 {
    let hi = hex_val(chars[i * 2])
    let lo = hex_val(chars[i * 2 + 1])
    arr[i] = ((hi << 4) | lo).to_byte()
  }
  arr
}

///|
fn hex_val(c : Char) -> Int {
  let n = c.to_int()
  if n >= 48 && n <= 57 {
    n - 48
  } else if n >= 97 && n <= 102 {
    n - 87
  } else if n >= 65 && n <= 70 {
    n - 55
  } else {
    0
  }
}

// Exported functions: take String, return "ok:hex_data" or "err:message"

///|
pub fn gzip_compress(input : String) -> String {
  let data = str_to_bytes(input)
  try {
    let compressed = @gzip.gzip_sync(data)
    "ok:" + bytes_to_hex(compressed)
  } catch {
    @types.FlateError(e) => "err:" + e.to_string()
  }
}

///|
pub fn gzip_decompress(hex_input : String) -> String {
  let data = hex_to_bytes(hex_input)
  try {
    let decompressed = @gzip.gunzip_sync(data)
    "ok:" + bytes_to_str(decompressed)
  } catch {
    @types.FlateError(e) => "err:" + e.to_string()
  }
}

///|
pub fn zlib_compress(input : String) -> String {
  let data = str_to_bytes(input)
  try {
    let compressed = @zlib.zlib_sync(data)
    "ok:" + bytes_to_hex(compressed)
  } catch {
    @types.FlateError(e) => "err:" + e.to_string()
  }
}

///|
pub fn zlib_decompress(hex_input : String) -> String {
  let data = hex_to_bytes(hex_input)
  try {
    let decompressed = @zlib.unzlib_sync(data)
    "ok:" + bytes_to_str(decompressed)
  } catch {
    @types.FlateError(e) => "err:" + e.to_string()
  }
}

///|
pub fn deflate_compress(input : String) -> String {
  let data = str_to_bytes(input)
  try {
    let compressed = @deflate.deflate_sync(data)
    "ok:" + bytes_to_hex(compressed)
  } catch {
    @types.FlateError(e) => "err:" + e.to_string()
  }
}

///|
pub fn deflate_decompress(hex_input : String) -> String {
  let data = hex_to_bytes(hex_input)
  try {
    let decompressed = @deflate.inflate_sync(data)
    "ok:" + bytes_to_str(decompressed)
  } catch {
    @types.FlateError(e) => "err:" + e.to_string()
  }
}

///|
pub fn unzip_list(hex_input : String) -> String {
  let data = hex_to_bytes(hex_input)
  try {
    let entries = @zip.unzip_list(data)
    let sb = StringBuilder::new()
    sb.write_string("ok:")
    for i, entry in entries {
      if i > 0 {
        sb.write_char('\n')
      }
      sb.write_string(entry.name)
      sb.write_char('\t')
      sb.write_string(entry.original_size.to_string())
      sb.write_char('\t')
      sb.write_string(entry.size.to_string())
      sb.write_char('\t')
      sb.write_string(
        if entry.compression == 0 {
          "Store"
        } else if entry.compression == 8 {
          "Deflate"
        } else {
          "Unknown"
        },
      )
    }
    sb.to_string()
  } catch {
    @types.FlateError(e) => "err:" + e.to_string()
  }
}

///|
fn main {
  ()
}
