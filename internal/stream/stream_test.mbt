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

///|
fn make_test_data() -> FixedArray[Byte] {
  string_to_bytes("Hello, streaming world! This is test data for moonzip.")
}

///|
fn split_into_chunks(
  data : FixedArray[Byte],
  chunk_size : Int,
) -> Array[FixedArray[Byte]] {
  let chunks : Array[FixedArray[Byte]] = []
  let mut offset = 0
  while offset < data.length() {
    let remaining = data.length() - offset
    let size = if remaining < chunk_size { remaining } else { chunk_size }
    let chunk = FixedArray::make(size, b'\x00')
    for i = 0; i < size; i = i + 1 {
      chunk[i] = data[offset + i]
    }
    chunks.push(chunk)
    offset = offset + size
  }
  chunks
}

// === DeflateStream tests ===

///|
test "DeflateStream: basic compression with chunks" {
  let data = make_test_data()
  let chunks = split_into_chunks(data, 16)
  let stream = @stream.DeflateStream::new()
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    stream.push(chunks[i], is_final)
  }
  let compressed = stream.result()
  let decompressed = @deflate.inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === InflateStream tests ===

///|
test "InflateStream: basic decompression with chunks" {
  let data = make_test_data()
  let compressed = @deflate.deflate_sync(data)
  let chunks = split_into_chunks(compressed, 10)
  let stream = @stream.InflateStream::new()
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    stream.push(chunks[i], is_final)
  }
  let result = stream.result()
  assert_true(bytes_equal(data, result))
}

// === GzipStream tests ===

///|
test "GzipStream: basic compression with chunks" {
  let data = make_test_data()
  let chunks = split_into_chunks(data, 20)
  let stream = @stream.GzipStream::new()
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    stream.push(chunks[i], is_final)
  }
  let compressed = stream.result()
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === GunzipStream tests ===

///|
test "GunzipStream: basic decompression with chunks" {
  let data = make_test_data()
  let compressed = @gzip.gzip_sync(data)
  let chunks = split_into_chunks(compressed, 15)
  let stream = @stream.GunzipStream::new()
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    stream.push(chunks[i], is_final)
  }
  let result = stream.result()
  assert_true(bytes_equal(data, result))
}

// === ZlibStream tests ===

///|
test "ZlibStream: basic compression with chunks" {
  let data = make_test_data()
  let chunks = split_into_chunks(data, 12)
  let stream = @stream.ZlibStream::new()
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    stream.push(chunks[i], is_final)
  }
  let compressed = stream.result()
  let decompressed = @zlib.unzlib_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === UnzlibStream tests ===

///|
test "UnzlibStream: basic decompression with chunks" {
  let data = make_test_data()
  let compressed = @zlib.zlib_sync(data)
  let chunks = split_into_chunks(compressed, 8)
  let stream = @stream.UnzlibStream::new()
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    stream.push(chunks[i], is_final)
  }
  let result = stream.result()
  assert_true(bytes_equal(data, result))
}

// === DecompressStream tests ===

///|
test "DecompressStream: auto-detect gzip" {
  let data = make_test_data()
  let compressed = @gzip.gzip_sync(data)
  let stream = @stream.DecompressStream::new()
  stream.push(compressed, true)
  let result = stream.result()
  assert_true(bytes_equal(data, result))
}

///|
test "DecompressStream: auto-detect zlib" {
  let data = make_test_data()
  let compressed = @zlib.zlib_sync(data)
  let stream = @stream.DecompressStream::new()
  stream.push(compressed, true)
  let result = stream.result()
  assert_true(bytes_equal(data, result))
}

///|
test "DecompressStream: auto-detect raw deflate" {
  let data = make_test_data()
  let compressed = @deflate.deflate_sync(data)
  let stream = @stream.DecompressStream::new()
  stream.push(compressed, true)
  let result = stream.result()
  assert_true(bytes_equal(data, result))
}

// === Error: push after final ===

///|
test "Error: push after final raises StreamFinished" {
  let stream = @stream.DeflateStream::new()
  let data : FixedArray[Byte] = [b'\x41', b'\x42', b'\x43']
  stream.push(data, true)
  let mut got_error = false
  stream.push(data, false) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

// === Single byte chunks ===

///|
test "DeflateStream: single byte chunks" {
  let data = string_to_bytes("ABCDEFGH")
  let stream = @stream.DeflateStream::new()
  for i = 0; i < data.length(); i = i + 1 {
    let chunk : FixedArray[Byte] = [data[i]]
    let is_final = i == data.length() - 1
    stream.push(chunk, is_final)
  }
  let compressed = stream.result()
  let decompressed = @deflate.inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === Empty chunks ===

///|
test "DeflateStream: empty chunks between data" {
  let data = string_to_bytes("Hello")
  let empty : FixedArray[Byte] = []
  let stream = @stream.DeflateStream::new()
  stream.push(empty, false)
  stream.push(data, false)
  stream.push(empty, false)
  stream.push(empty, true)
  let compressed = stream.result()
  let decompressed = @deflate.inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === Single push ===

///|
test "DeflateStream: single push with final" {
  let data = make_test_data()
  let stream = @stream.DeflateStream::new()
  stream.push(data, true)
  let compressed = stream.result()
  let decompressed = @deflate.inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// === result() before finished tests ===

///|
test "DeflateStream: result before finished raises error" {
  let stream = @stream.DeflateStream::new()
  let mut got_error = false
  try {
    let _ = stream.result()
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "InflateStream: result before finished raises error" {
  let stream = @stream.InflateStream::new()
  let mut got_error = false
  try {
    let _ = stream.result()
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "GzipStream: result before finished raises error" {
  let stream = @stream.GzipStream::new()
  let mut got_error = false
  try {
    let _ = stream.result()
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "GunzipStream: result before finished raises error" {
  let stream = @stream.GunzipStream::new()
  let mut got_error = false
  try {
    let _ = stream.result()
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "ZlibStream: result before finished raises error" {
  let stream = @stream.ZlibStream::new()
  let mut got_error = false
  try {
    let _ = stream.result()
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "UnzlibStream: result before finished raises error" {
  let stream = @stream.UnzlibStream::new()
  let mut got_error = false
  try {
    let _ = stream.result()
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "DecompressStream: result before finished raises error" {
  let stream = @stream.DecompressStream::new()
  let mut got_error = false
  try {
    let _ = stream.result()
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

// === push after finished tests ===

///|
test "InflateStream: push after finished raises error" {
  let data = make_test_data()
  let compressed = @deflate.deflate_sync(data)
  let stream = @stream.InflateStream::new()
  stream.push(compressed, true)
  let mut got_error = false
  let chunk : FixedArray[Byte] = [b'\x00']
  stream.push(chunk, false) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "GzipStream: push after finished raises error" {
  let stream = @stream.GzipStream::new()
  let data : FixedArray[Byte] = [b'\x41']
  stream.push(data, true)
  let mut got_error = false
  stream.push(data, false) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "GunzipStream: push after finished raises error" {
  let data = make_test_data()
  let compressed = @gzip.gzip_sync(data)
  let stream = @stream.GunzipStream::new()
  stream.push(compressed, true)
  let mut got_error = false
  let chunk : FixedArray[Byte] = [b'\x00']
  stream.push(chunk, false) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "ZlibStream: push after finished raises error" {
  let stream = @stream.ZlibStream::new()
  let data : FixedArray[Byte] = [b'\x41']
  stream.push(data, true)
  let mut got_error = false
  stream.push(data, false) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "UnzlibStream: push after finished raises error" {
  let data = make_test_data()
  let compressed = @zlib.zlib_sync(data)
  let stream = @stream.UnzlibStream::new()
  stream.push(compressed, true)
  let mut got_error = false
  let chunk : FixedArray[Byte] = [b'\x00']
  stream.push(chunk, false) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "DecompressStream: push after finished raises error" {
  let data = make_test_data()
  let compressed = @deflate.deflate_sync(data)
  let stream = @stream.DecompressStream::new()
  stream.push(compressed, true)
  let mut got_error = false
  let chunk : FixedArray[Byte] = [b'\x00']
  stream.push(chunk, false) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

// ============================================================
// EncodeUTF8 tests
// ============================================================

///|
test "EncodeUTF8: ASCII string chunks match str_to_u8" {
  let chunks = ["Hello, ", "World!"]
  let collected : Array[FixedArray[Byte]] = []
  let enc = @stream.EncodeUTF8::new(ondata=fn(chunk, _final) {
    collected.push(chunk)
  })
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    enc.push(chunks[i], is_final)
  }
  let result = concat_test_chunks(collected)
  let expected = @utf8.str_to_u8("Hello, World!")
  assert_true(bytes_equal(result, expected))
}

///|
test "EncodeUTF8: multibyte string chunks match str_to_u8" {
  // "こんにちは世界" split into chunks
  let chunks = ["\u3053\u3093", "\u306B\u3061\u306F", "\u4E16\u754C"]
  let collected : Array[FixedArray[Byte]] = []
  let enc = @stream.EncodeUTF8::new(ondata=fn(chunk, _final) {
    collected.push(chunk)
  })
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    enc.push(chunks[i], is_final)
  }
  let result = concat_test_chunks(collected)
  let expected = @utf8.str_to_u8("\u3053\u3093\u306B\u3061\u306F\u4E16\u754C")
  assert_true(bytes_equal(result, expected))
}

///|
test "EncodeUTF8: empty string" {
  let collected : Array[FixedArray[Byte]] = []
  let enc = @stream.EncodeUTF8::new(ondata=fn(chunk, _final) {
    collected.push(chunk)
  })
  enc.push("", true)
  let result = concat_test_chunks(collected)
  assert_eq(result.length(), 0)
}

///|
test "EncodeUTF8: single push with final" {
  let collected : Array[FixedArray[Byte]] = []
  let enc = @stream.EncodeUTF8::new(ondata=fn(chunk, _final) {
    collected.push(chunk)
  })
  enc.push("Hello \u4E16\u754C!", true)
  let result = concat_test_chunks(collected)
  let expected = @utf8.str_to_u8("Hello \u4E16\u754C!")
  assert_true(bytes_equal(result, expected))
}

///|
test "EncodeUTF8: push after final raises error" {
  let enc = @stream.EncodeUTF8::new(ondata=fn(_chunk, _final) {  })
  enc.push("test", true)
  let mut got_error = false
  enc.push("more", false) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

// ============================================================
// DecodeUTF8 tests
// ============================================================

///|
test "DecodeUTF8: ASCII bytes to string" {
  let collected : Array[String] = []
  let dec = @stream.DecodeUTF8::new(ondata=fn(chunk, _final) {
    collected.push(chunk)
  })
  let data = @utf8.str_to_u8("Hello, World!")
  dec.push(data, true)
  let result = concat_strings(collected)
  assert_eq(result, "Hello, World!")
}

///|
test "DecodeUTF8: multibyte bytes to string in chunks" {
  let full_bytes = @utf8.str_to_u8("\u3053\u3093\u306B\u3061\u306F\u4E16\u754C")
  let chunks = split_into_chunks(full_bytes, 4)
  let collected : Array[String] = []
  let dec = @stream.DecodeUTF8::new(ondata=fn(chunk, _final) {
    collected.push(chunk)
  })
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    dec.push(chunks[i], is_final)
  }
  let result = concat_strings(collected)
  assert_eq(result, "\u3053\u3093\u306B\u3061\u306F\u4E16\u754C")
}

///|
test "DecodeUTF8: multibyte split at boundary" {
  // "日" (U+65E5) = E6 97 A5 (3 bytes)
  // Split: first chunk gets E6 97, second chunk gets A5
  let chunk1 : FixedArray[Byte] = [b'\xE6', b'\x97']
  let chunk2 : FixedArray[Byte] = [b'\xA5']
  let collected : Array[String] = []
  let dec = @stream.DecodeUTF8::new(ondata=fn(chunk, _final) {
    collected.push(chunk)
  })
  dec.push(chunk1, false)
  dec.push(chunk2, true)
  let result = concat_strings(collected)
  assert_eq(result, "\u65E5")
}

///|
test "DecodeUTF8: 4-byte char split across chunks" {
  // U+1F600 (😀) = F0 9F 98 80
  let chunk1 : FixedArray[Byte] = [b'\xF0', b'\x9F']
  let chunk2 : FixedArray[Byte] = [b'\x98', b'\x80']
  let collected : Array[String] = []
  let dec = @stream.DecodeUTF8::new(ondata=fn(chunk, _final) {
    collected.push(chunk)
  })
  dec.push(chunk1, false)
  dec.push(chunk2, true)
  let result = concat_strings(collected)
  // Compare byte-level to avoid potential display issues
  let result_bytes = @utf8.str_to_u8(result)
  let expected_bytes : FixedArray[Byte] = [b'\xF0', b'\x9F', b'\x98', b'\x80']
  assert_true(bytes_equal(result_bytes, expected_bytes))
}

///|
test "DecodeUTF8: invalid continuation byte raises error" {
  // 0xC3 starts a 2-byte sequence but 0x00 is not a valid continuation byte
  let data : FixedArray[Byte] = [b'\xC3', b'\x00']
  let dec = @stream.DecodeUTF8::new(ondata=fn(_chunk, _final) {  })
  let mut got_error = false
  dec.push(data, true) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "DecodeUTF8: truncated sequence at final raises error" {
  // 0xC3 starts a 2-byte sequence but stream ends
  let data : FixedArray[Byte] = [b'\xC3']
  let dec = @stream.DecodeUTF8::new(ondata=fn(_chunk, _final) {  })
  let mut got_error = false
  dec.push(data, true) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "DecodeUTF8: invalid leading byte raises error" {
  // 0xFF is not a valid UTF-8 leading byte
  let data : FixedArray[Byte] = [b'\xFF']
  let dec = @stream.DecodeUTF8::new(ondata=fn(_chunk, _final) {  })
  let mut got_error = false
  dec.push(data, true) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "DecodeUTF8: empty input" {
  let collected : Array[String] = []
  let dec = @stream.DecodeUTF8::new(ondata=fn(chunk, _final) {
    collected.push(chunk)
  })
  dec.push(FixedArray::make(0, b'\x00'), true)
  let result = concat_strings(collected)
  assert_eq(result, "")
}

///|
test "DecodeUTF8: push after final raises error" {
  let dec = @stream.DecodeUTF8::new(ondata=fn(_chunk, _final) {  })
  dec.push(FixedArray::make(0, b'\x00'), true)
  let mut got_error = false
  dec.push(FixedArray::make(0, b'\x00'), false) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "EncodeUTF8 -> DecodeUTF8 round-trip" {
  let original = "Hello \u4E16\u754C! \u00E9\u00E8\u00EA"
  let byte_chunks : Array[FixedArray[Byte]] = []
  let enc = @stream.EncodeUTF8::new(ondata=fn(chunk, _final) {
    byte_chunks.push(chunk)
  })
  enc.push(original, true)
  let string_chunks : Array[String] = []
  let dec = @stream.DecodeUTF8::new(ondata=fn(chunk, _final) {
    string_chunks.push(chunk)
  })
  for i = 0; i < byte_chunks.length(); i = i + 1 {
    let is_final = i == byte_chunks.length() - 1
    dec.push(byte_chunks[i], is_final)
  }
  let result = concat_strings(string_chunks)
  assert_eq(result, original)
}

// ============================================================
// Test helpers for UTF-8 streaming tests
// ============================================================

///|
fn concat_test_chunks(chunks : Array[FixedArray[Byte]]) -> FixedArray[Byte] {
  let mut total = 0
  for i = 0; i < chunks.length(); i = i + 1 {
    total = total + chunks[i].length()
  }
  let result = FixedArray::make(total, b'\x00')
  let mut pos = 0
  for i = 0; i < chunks.length(); i = i + 1 {
    let chunk = chunks[i]
    for j = 0; j < chunk.length(); j = j + 1 {
      result[pos] = chunk[j]
      pos = pos + 1
    }
  }
  result
}

///|
fn concat_strings(strings : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < strings.length(); i = i + 1 {
    buf.write_string(strings[i])
  }
  buf.to_string()
}
