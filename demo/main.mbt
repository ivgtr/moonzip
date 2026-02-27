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
      if cp >= 0x80 {
        sb.write_char(cp.unsafe_to_char())
      } else {
        sb.write_char('?')
      }
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 && i + 2 < len {
      let cp = ((b0 & 0x0F) << 12) |
        ((data[i + 1].to_int() & 0x3F) << 6) |
        (data[i + 2].to_int() & 0x3F)
      if cp >= 0x800 {
        sb.write_char(cp.unsafe_to_char())
      } else {
        sb.write_char('?')
      }
      i = i + 3
    } else if (b0 & 0xF8) == 0xF0 && i + 3 < len {
      let cp = ((b0 & 0x07) << 18) |
        ((data[i + 1].to_int() & 0x3F) << 12) |
        ((data[i + 2].to_int() & 0x3F) << 6) |
        (data[i + 3].to_int() & 0x3F)
      if cp >= 0x10000 && cp <= 0x10FFFF {
        sb.write_char(cp.unsafe_to_char())
      } else {
        sb.write_char('?')
      }
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
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd',
    'e', 'f',
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
  let len = s.length() / 2
  let arr = FixedArray::make(len, b'\x00')
  let mut i = 0
  let mut hi = 0
  for c in s {
    if i % 2 == 0 {
      hi = hex_val(c)
    } else {
      arr[i / 2] = ((hi << 4) | hex_val(c)).to_byte()
    }
    i = i + 1
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

///|
fn parse_int(s : String) -> Int {
  let mut n = 0
  for c in s {
    let d = c.to_int() - 48
    if d >= 0 && d <= 9 {
      n = n * 10 + d
    }
  }
  n
}

// Compression level / encoding state

///|
priv struct DemoState {
  mut level : Int
  mut encoding : String
}

///|
let demo_state : DemoState = { level: 6, encoding: "" }

///|
pub fn set_level(level_str : String) -> String {
  let lv = parse_int(level_str)
  demo_state.level = if lv > 9 { 9 } else { lv }
  "ok:" + demo_state.level.to_string()
}

///|
fn normalize_encoding(encoding : String) -> String {
  let chars = Array::new()
  for c in encoding {
    chars.push(c)
  }
  let mut start = 0
  while start < chars.length() && chars[start] == ' ' {
    start = start + 1
  }
  let mut end = chars.length()
  while end > start && chars[end - 1] == ' ' {
    end = end - 1
  }
  let sb = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    let n = chars[i].to_int()
    let ch = if n >= 65 && n <= 90 { (n + 32).unsafe_to_char() } else { chars[i] }
    sb.write_char(ch)
  }
  let lower = sb.to_string()
  if lower == "utf-8" { "" } else { lower }
}

///|
pub fn set_encoding(encoding : String) -> String {
  demo_state.encoding = normalize_encoding(encoding)
  "ok:" + demo_state.encoding
}

///|
fn make_decoder() -> ((FixedArray[Byte]) -> String)? {
  if demo_state.encoding == "" {
    None
  } else {
    let enc = demo_state.encoding
    Some(fn(raw) { js_text_decode(raw, enc) })
  }
}

// Compress / Decompress

///|
pub fn gzip_compress(input : String) -> String {
  let data = str_to_bytes(input)
  let opts : @types.GzipOptions = {
    level: demo_state.level,
    mem: 4,
    mtime: None,
    filename: None,
    comment: None,
    extra: None,
  }
  let compressed = @gzip.gzip_sync(data, opts~)
  "ok:" + bytes_to_hex(compressed)
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
  let opts : @types.ZlibOptions = {
    level: demo_state.level,
    mem: 4,
    dictionary: None,
  }
  let compressed = @zlib.zlib_sync(data, opts~)
  "ok:" + bytes_to_hex(compressed)
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
  let opts : @types.DeflateOptions = {
    level: demo_state.level,
    mem: 4,
    dictionary: None,
  }
  let compressed = @deflate.deflate_sync(data, opts~)
  "ok:" + bytes_to_hex(compressed)
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
pub fn decompress_auto(hex_input : String) -> String {
  let data = hex_to_bytes(hex_input)
  try {
    let result = if data.length() >= 2 {
      if data[0] == b'\x1F' && data[1] == b'\x8B' {
        @gzip.gunzip_sync(data)
      } else {
        let cmf = data[0].to_int()
        let flg = data[1].to_int()
        let cm = cmf & 0x0F
        let cinfo = (cmf >> 4) & 0x0F
        if cm == 8 && cinfo <= 7 && (cmf * 256 + flg) % 31 == 0 {
          @zlib.unzlib_sync(data)
        } else {
          @deflate.inflate_sync(data)
        }
      }
    } else {
      @deflate.inflate_sync(data)
    }
    "ok:" + bytes_to_str(result)
  } catch {
    @types.FlateError(e) => "err:" + e.to_string()
  }
}

// ZIP list / extract

///|
pub fn unzip_list(data : FixedArray[Byte]) -> String {
  try {
    let decoder = make_decoder()
    let entries = match decoder {
      Some(d) => @zip.unzip_list(data, decode=d)
      None => @zip.unzip_list(data)
    }
    let sb = StringBuilder::new()
    sb.write_string("ok:")
    for i = 0; i < entries.length(); i = i + 1 {
      let entry = entries[i]
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
pub fn unzip_extract(data : FixedArray[Byte], filename : String) -> String {
  try {
    let decoder = make_decoder()
    let files = match decoder {
      Some(d) => @zip.unzip_sync(data, decode=d)
      None => @zip.unzip_sync(data)
    }
    let mut i = 0
    while i < files.length() {
      let (name, content) = files[i]
      if name == filename {
        return "ok:" + bytes_to_str(content)
      }
      i = i + 1
    }
    "err:File not found: " + filename
  } catch {
    @types.FlateError(e) => "err:" + e.to_string()
  }
}

// ZIP creator

///|
let zip_entries : Array[(String, String)] = Array::new()

///|
pub fn zip_add_entry(name : String, content : String) -> String {
  zip_entries.push((name, content))
  "ok:" + zip_entries.length().to_string()
}

///|
pub fn zip_build() -> String {
  let files : Array[(String, FixedArray[Byte])] = Array::new()
  let mut i = 0
  while i < zip_entries.length() {
    let (name, content) = zip_entries[i]
    files.push((name, str_to_bytes(content)))
    i = i + 1
  }
  let opts : @types.ZipOptions = {
    level: demo_state.level,
    mtime: None,
    comment: None,
  }
  let result = @zip.zip_sync(files, opts~)
  while zip_entries.length() > 0 {
    let _ = zip_entries.pop()
  }
  "ok:" + bytes_to_hex(result)
}

///|
pub fn zip_clear() -> String {
  while zip_entries.length() > 0 {
    let _ = zip_entries.pop()
  }
  "ok:0"
}

///|
fn main {
  ()
}
