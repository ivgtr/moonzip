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
