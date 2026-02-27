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
// E-T1: ondata callback tests
// ============================================================

///|
test "E-T1: DeflateStream ondata callback fires on final" {
  let mut callback_called = false
  let mut callback_final = false
  let stream = @stream.DeflateStream::new(
    ondata=Some(fn(data : FixedArray[Byte], final_ : Bool) {
      let _ = data
      callback_called = true
      callback_final = final_
    }),
  )
  let data = make_test_data()
  stream.push(data, true)
  assert_true(callback_called)
  assert_true(callback_final)
}

///|
test "E-T1: InflateStream ondata callback fires on final" {
  let mut callback_called = false
  let mut received_data : FixedArray[Byte] = []
  let data = make_test_data()
  let compressed = @deflate.deflate_sync(data)
  let stream = @stream.InflateStream::new(
    ondata=Some(fn(decompressed : FixedArray[Byte], _final : Bool) {
      callback_called = true
      received_data = decompressed
    }),
  )
  stream.push(compressed, true)
  assert_true(callback_called)
  assert_true(bytes_equal(data, received_data))
}

///|
test "E-T1: GzipStream ondata callback fires on final" {
  let mut callback_called = false
  let mut callback_final = false
  let stream = @stream.GzipStream::new(
    ondata=Some(fn(_data : FixedArray[Byte], final_ : Bool) {
      callback_called = true
      callback_final = final_
    }),
  )
  let data = make_test_data()
  stream.push(data, true)
  assert_true(callback_called)
  assert_true(callback_final)
}

///|
test "E-T1: GunzipStream ondata callback fires on final" {
  let mut callback_called = false
  let mut received_data : FixedArray[Byte] = []
  let data = make_test_data()
  let compressed = @gzip.gzip_sync(data)
  let stream = @stream.GunzipStream::new(
    ondata=Some(fn(decompressed : FixedArray[Byte], _final : Bool) {
      callback_called = true
      received_data = decompressed
    }),
  )
  stream.push(compressed, true)
  assert_true(callback_called)
  assert_true(bytes_equal(data, received_data))
}

///|
test "E-T1: ZlibStream ondata callback fires on final" {
  let mut callback_called = false
  let mut callback_final = false
  let stream = @stream.ZlibStream::new(
    ondata=Some(fn(_data : FixedArray[Byte], final_ : Bool) {
      callback_called = true
      callback_final = final_
    }),
  )
  let data = make_test_data()
  stream.push(data, true)
  assert_true(callback_called)
  assert_true(callback_final)
}

///|
test "E-T1: UnzlibStream ondata callback fires on final" {
  let mut callback_called = false
  let mut received_data : FixedArray[Byte] = []
  let data = make_test_data()
  let compressed = @zlib.zlib_sync(data)
  let stream = @stream.UnzlibStream::new(
    ondata=Some(fn(decompressed : FixedArray[Byte], _final : Bool) {
      callback_called = true
      received_data = decompressed
    }),
  )
  stream.push(compressed, true)
  assert_true(callback_called)
  assert_true(bytes_equal(data, received_data))
}

///|
test "E-T1: DecompressStream ondata callback fires on final" {
  let mut callback_called = false
  let mut received_data : FixedArray[Byte] = []
  let data = make_test_data()
  let compressed = @gzip.gzip_sync(data)
  let stream = @stream.DecompressStream::new(
    ondata=Some(fn(decompressed : FixedArray[Byte], _final : Bool) {
      callback_called = true
      received_data = decompressed
    }),
  )
  stream.push(compressed, true)
  assert_true(callback_called)
  assert_true(bytes_equal(data, received_data))
}

// ============================================================
// E-T1: ondata callback data correctness
// ============================================================

///|
test "E-T1: DeflateStream ondata produces correct data" {
  let received : Array[FixedArray[Byte]] = []
  let data = make_test_data()
  let stream = @stream.DeflateStream::new(
    ondata=Some(fn(chunk : FixedArray[Byte], _final : Bool) {
      received.push(chunk)
    }),
  )
  stream.push(data, true)
  let result = stream.result()
  assert_true(received.length() > 0)
  let mut total = 0
  for i = 0; i < received.length(); i = i + 1 {
    total = total + received[i].length()
  }
  assert_eq(total, result.length())
}

// ============================================================
// E-T2: flush() tests
// ============================================================

///|
test "E-T2: DeflateStream flush produces output" {
  let data = make_test_data()
  let chunks = split_into_chunks(data, 16)
  let stream = @stream.DeflateStream::new()
  stream.push(chunks[0], false)
  stream.flush()
  for i = 1; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    stream.push(chunks[i], is_final)
  }
  let result = stream.result()
  assert_true(result.length() > 0)
}

///|
test "E-T2: GzipStream flush produces output" {
  let data = make_test_data()
  let stream = @stream.GzipStream::new()
  stream.push(data, false)
  stream.flush()
  let empty : FixedArray[Byte] = []
  stream.push(empty, true)
  let result = stream.result()
  assert_true(result.length() > 0)
}

///|
test "E-T2: flush on empty buffer is no-op" {
  let stream = @stream.DeflateStream::new()
  stream.flush()
  let data = make_test_data()
  stream.push(data, true)
  let result = stream.result()
  let decompressed = @deflate.inflate_sync(result)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "E-T2: flush on finished stream is no-op" {
  let data = make_test_data()
  let stream = @stream.DeflateStream::new()
  stream.push(data, true)
  stream.flush()
  let result = stream.result()
  let decompressed = @deflate.inflate_sync(result)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "E-T2: flush with ondata callback" {
  let mut flush_called = false
  let stream = @stream.DeflateStream::new(
    ondata=Some(fn(_data : FixedArray[Byte], final_ : Bool) {
      if not(final_) {
        flush_called = true
      }
    }),
  )
  let data = make_test_data()
  stream.push(data, false)
  stream.flush()
  assert_true(flush_called)
}

// ============================================================
// E-T2: Large data streaming test
// ============================================================

///|
test "E-T2: large data deflate stream" {
  let size = 4096
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = ((i * 7 + 13) % 256).to_byte()
  }
  let stream = @stream.DeflateStream::new()
  let chunks = split_into_chunks(data, 512)
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    stream.push(chunks[i], is_final)
  }
  let compressed = stream.result()
  let decompressed = @deflate.inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "E-T2: large data gzip stream" {
  let size = 4096
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = ((i * 11 + 3) % 256).to_byte()
  }
  let stream = @stream.GzipStream::new()
  stream.push(data, true)
  let compressed = stream.result()
  let decompressed = @gzip.gunzip_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "E-T2: large data zlib stream" {
  let size = 4096
  let data = FixedArray::make(size, b'\x00')
  for i = 0; i < size; i = i + 1 {
    data[i] = ((i * 3 + 17) % 256).to_byte()
  }
  let stream = @stream.ZlibStream::new()
  stream.push(data, true)
  let compressed = stream.result()
  let decompressed = @zlib.unzlib_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

// ============================================================
// E-T3: ZIP streaming tests
// ============================================================

///|
test "E-T3: ZipPassThrough basic" {
  let data = string_to_bytes("Hello, ZIP!")
  let pt = @stream.ZipPassThrough::new("hello.txt")
  pt.push(data, true)
  let result = pt.result()
  assert_true(bytes_equal(data, result))
  assert_eq(pt.size(), data.length())
}

///|
test "E-T3: ZipPassThrough CRC32 is correct" {
  let data = string_to_bytes("Hello, ZIP!")
  let pt = @stream.ZipPassThrough::new("hello.txt")
  pt.push(data, true)
  let expected_crc = @checksum.crc32(data)
  assert_eq(pt.crc(), expected_crc)
}

///|
test "E-T3: ZipPassThrough chunked push" {
  let data = string_to_bytes("Hello, chunked ZIP world!")
  let chunks = split_into_chunks(data, 5)
  let pt = @stream.ZipPassThrough::new("chunked.txt")
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    pt.push(chunks[i], is_final)
  }
  let result = pt.result()
  assert_true(bytes_equal(data, result))
  assert_eq(pt.size(), data.length())
  assert_eq(pt.crc(), @checksum.crc32(data))
}

///|
test "E-T3: ZipDeflate basic" {
  let data = string_to_bytes("Hello, compressed ZIP!")
  let zd = @stream.ZipDeflate::new("hello.txt")
  zd.push(data, true)
  let compressed = zd.compressed_result()
  assert_true(compressed.length() > 0)
  assert_eq(zd.original_size(), data.length())
  assert_eq(zd.crc(), @checksum.crc32(data))
  let decompressed = @deflate.inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
}

///|
test "E-T3: ZipDeflate chunked push" {
  let data = string_to_bytes("Hello, chunked compressed ZIP world!")
  let chunks = split_into_chunks(data, 8)
  let zd = @stream.ZipDeflate::new("chunked.txt")
  for i = 0; i < chunks.length(); i = i + 1 {
    let is_final = i == chunks.length() - 1
    zd.push(chunks[i], is_final)
  }
  let compressed = zd.compressed_result()
  let decompressed = @deflate.inflate_sync(compressed)
  assert_true(bytes_equal(data, decompressed))
  assert_eq(zd.original_size(), data.length())
  assert_eq(zd.crc(), @checksum.crc32(data))
}

///|
test "E-T3: Zip streaming creation with passthrough" {
  let zip = @stream.Zip::new()
  let data1 = string_to_bytes("File 1 content")
  let pt1 = @stream.ZipPassThrough::new("file1.txt")
  pt1.push(data1, true)
  zip.add_passthrough(pt1)
  let data2 = string_to_bytes("File 2 content")
  let pt2 = @stream.ZipPassThrough::new("file2.txt")
  pt2.push(data2, true)
  zip.add_passthrough(pt2)
  let archive = zip.finish()
  let files = @zip.unzip_sync(archive)
  assert_eq(files.length(), 2)
  let (name1, content1) = files[0]
  let (name2, content2) = files[1]
  assert_eq(name1, "file1.txt")
  assert_eq(name2, "file2.txt")
  assert_true(bytes_equal(data1, content1))
  assert_true(bytes_equal(data2, content2))
}

///|
test "E-T3: Zip streaming creation with deflate" {
  let zip = @stream.Zip::new()
  let data = string_to_bytes("Hello, compressed ZIP streaming!")
  let zd = @stream.ZipDeflate::new("compressed.txt")
  zd.push(data, true)
  zip.add_deflate(zd)
  let archive = zip.finish()
  let files = @zip.unzip_sync(archive)
  assert_eq(files.length(), 1)
  let (name, content) = files[0]
  assert_eq(name, "compressed.txt")
  assert_true(bytes_equal(data, content))
}

///|
test "E-T3: Zip streaming mixed passthrough and deflate" {
  let zip = @stream.Zip::new()
  let data1 = string_to_bytes("Stored data")
  let pt = @stream.ZipPassThrough::new("stored.txt")
  pt.push(data1, true)
  zip.add_passthrough(pt)
  let data2 = string_to_bytes("Compressed data for ZIP streaming test")
  let zd = @stream.ZipDeflate::new("compressed.txt")
  zd.push(data2, true)
  zip.add_deflate(zd)
  let archive = zip.finish()
  let files = @zip.unzip_sync(archive)
  assert_eq(files.length(), 2)
  let (name1, content1) = files[0]
  let (name2, content2) = files[1]
  assert_eq(name1, "stored.txt")
  assert_eq(name2, "compressed.txt")
  assert_true(bytes_equal(data1, content1))
  assert_true(bytes_equal(data2, content2))
}

// ============================================================
// E-T3: Unzip streaming tests
// ============================================================

///|
test "E-T3: Unzip streaming basic" {
  let data1 = string_to_bytes("Content A")
  let data2 = string_to_bytes("Content B")
  let files : Array[(String, FixedArray[Byte])] = [
    ("a.txt", data1),
    ("b.txt", data2),
  ]
  let archive = @zip.zip_sync(files)
  let unzip = @stream.Unzip::new()
  unzip.push(archive, true)
  let result = unzip.result()
  assert_eq(result.length(), 2)
  let (name1, content1) = result[0]
  let (name2, content2) = result[1]
  assert_eq(name1, "a.txt")
  assert_eq(name2, "b.txt")
  assert_true(bytes_equal(data1, content1))
  assert_true(bytes_equal(data2, content2))
}

///|
test "E-T3: Unzip onfile callback" {
  let data1 = string_to_bytes("File A")
  let data2 = string_to_bytes("File B")
  let files : Array[(String, FixedArray[Byte])] = [
    ("a.txt", data1),
    ("b.txt", data2),
  ]
  let archive = @zip.zip_sync(files)
  let received_names : Array[String] = []
  let received_data : Array[FixedArray[Byte]] = []
  let unzip = @stream.Unzip::new(
    onfile=Some(fn(name : String, file_data : FixedArray[Byte]) {
      received_names.push(name)
      received_data.push(file_data)
    }),
  )
  unzip.push(archive, true)
  assert_eq(received_names.length(), 2)
  assert_eq(received_names[0], "a.txt")
  assert_eq(received_names[1], "b.txt")
  assert_true(bytes_equal(data1, received_data[0]))
  assert_true(bytes_equal(data2, received_data[1]))
}

// ============================================================
// E-T4: Gunzip onmember callback test
// ============================================================

///|
test "E-T4: GunzipStream single member with onmember" {
  let data = make_test_data()
  let compressed = @gzip.gzip_sync(data)
  let mut member_count = 0
  let member_data_arr : Array[FixedArray[Byte]] = []
  let stream = @stream.GunzipStream::new(
    onmember=Some(fn(member_data : FixedArray[Byte]) {
      member_count = member_count + 1
      member_data_arr.push(member_data)
    }),
  )
  stream.push(compressed, true)
  assert_eq(member_count, 1)
  assert_true(bytes_equal(data, member_data_arr[0]))
  let result = stream.result()
  assert_true(bytes_equal(data, result))
}

///|
test "E-T4: GunzipStream multi-member with onmember" {
  let data1 = string_to_bytes("Hello")
  let data2 = string_to_bytes("World")
  let gz1 = @gzip.gzip_sync(data1)
  let gz2 = @gzip.gzip_sync(data2)
  let combined = FixedArray::make(gz1.length() + gz2.length(), b'\x00')
  for i = 0; i < gz1.length(); i = i + 1 {
    combined[i] = gz1[i]
  }
  for i = 0; i < gz2.length(); i = i + 1 {
    combined[gz1.length() + i] = gz2[i]
  }
  let member_data_arr : Array[FixedArray[Byte]] = []
  let stream = @stream.GunzipStream::new(
    onmember=Some(fn(member_data : FixedArray[Byte]) {
      member_data_arr.push(member_data)
    }),
  )
  stream.push(combined, true)
  assert_eq(member_data_arr.length(), 2)
  assert_true(bytes_equal(data1, member_data_arr[0]))
  assert_true(bytes_equal(data2, member_data_arr[1]))
  let result = stream.result()
  let expected = FixedArray::make(data1.length() + data2.length(), b'\x00')
  for i = 0; i < data1.length(); i = i + 1 {
    expected[i] = data1[i]
  }
  for i = 0; i < data2.length(); i = i + 1 {
    expected[data1.length() + i] = data2[i]
  }
  assert_true(bytes_equal(expected, result))
}

// ============================================================
// E-T4: Zip ondata callback test
// ============================================================

///|
test "E-T4: Zip ondata callback fires on finish" {
  let mut callback_called = false
  let mut callback_final = false
  let zip = @stream.Zip::new(
    ondata=Some(fn(_data : FixedArray[Byte], final_ : Bool) {
      callback_called = true
      callback_final = final_
    }),
  )
  let data = string_to_bytes("Test")
  let pt = @stream.ZipPassThrough::new("test.txt")
  pt.push(data, true)
  zip.add_passthrough(pt)
  let _ = zip.finish()
  assert_true(callback_called)
  assert_true(callback_final)
}

///|
test "E-T4: ZipPassThrough ondata callback" {
  let mut callback_called = false
  let mut cb_final = false
  let mut cb_data : FixedArray[Byte] = []
  let data = string_to_bytes("Test data")
  let pt = @stream.ZipPassThrough::new(
    "test.txt",
    ondata=Some(fn(chunk : FixedArray[Byte], final_ : Bool) {
      callback_called = true
      cb_final = final_
      cb_data = chunk
    }),
  )
  pt.push(data, true)
  assert_true(callback_called)
  assert_true(cb_final)
  assert_true(bytes_equal(data, cb_data))
}

///|
test "E-T4: ZipDeflate ondata callback" {
  let mut callback_called = false
  let mut cb_final = false
  let data = string_to_bytes("Test data for deflate")
  let zd = @stream.ZipDeflate::new(
    "test.txt",
    ondata=Some(fn(_chunk : FixedArray[Byte], final_ : Bool) {
      callback_called = true
      cb_final = final_
    }),
  )
  zd.push(data, true)
  assert_true(callback_called)
  assert_true(cb_final)
}

// ============================================================
// E-T2: Roundtrip streaming tests
// ============================================================

///|
test "E-T2: Deflate roundtrip streaming" {
  let data = make_test_data()
  let def_stream = @stream.DeflateStream::new()
  def_stream.push(data, true)
  let compressed = def_stream.result()
  let inf_stream = @stream.InflateStream::new()
  inf_stream.push(compressed, true)
  let decompressed = inf_stream.result()
  assert_true(bytes_equal(data, decompressed))
}

///|
test "E-T2: Gzip roundtrip streaming" {
  let data = make_test_data()
  let gz_stream = @stream.GzipStream::new()
  gz_stream.push(data, true)
  let compressed = gz_stream.result()
  let gunz_stream = @stream.GunzipStream::new()
  gunz_stream.push(compressed, true)
  let decompressed = gunz_stream.result()
  assert_true(bytes_equal(data, decompressed))
}

///|
test "E-T2: Zlib roundtrip streaming" {
  let data = make_test_data()
  let zlib_stream = @stream.ZlibStream::new()
  zlib_stream.push(data, true)
  let compressed = zlib_stream.result()
  let unz_stream = @stream.UnzlibStream::new()
  unz_stream.push(compressed, true)
  let decompressed = unz_stream.result()
  assert_true(bytes_equal(data, decompressed))
}

// ============================================================
// E-T3: Zip roundtrip via streaming
// ============================================================

///|
test "E-T3: Zip/Unzip streaming roundtrip" {
  let zip = @stream.Zip::new()
  let data1 = string_to_bytes("First file content")
  let pt = @stream.ZipPassThrough::new("first.txt")
  pt.push(data1, true)
  zip.add_passthrough(pt)
  let data2 = string_to_bytes("Second file, this one is compressed")
  let zd = @stream.ZipDeflate::new("second.txt")
  zd.push(data2, true)
  zip.add_deflate(zd)
  let archive = zip.finish()
  let unzip = @stream.Unzip::new()
  unzip.push(archive, true)
  let result = unzip.result()
  assert_eq(result.length(), 2)
  let (name1, content1) = result[0]
  let (name2, content2) = result[1]
  assert_eq(name1, "first.txt")
  assert_eq(name2, "second.txt")
  assert_true(bytes_equal(data1, content1))
  assert_true(bytes_equal(data2, content2))
}

// ============================================================
// Zip/Unzip error tests
// ============================================================

///|
test "Zip: finish after finished raises error" {
  let zip = @stream.Zip::new()
  let data = string_to_bytes("Test")
  let pt = @stream.ZipPassThrough::new("test.txt")
  pt.push(data, true)
  zip.add_passthrough(pt)
  let _ = zip.finish()
  let mut got_error = false
  try {
    let _ = zip.finish()
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "Zip: add_passthrough after finished raises error" {
  let zip = @stream.Zip::new()
  let data = string_to_bytes("Test")
  let pt = @stream.ZipPassThrough::new("test.txt")
  pt.push(data, true)
  zip.add_passthrough(pt)
  let _ = zip.finish()
  let pt2 = @stream.ZipPassThrough::new("test2.txt")
  pt2.push(data, true)
  let mut got_error = false
  zip.add_passthrough(pt2) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "Zip: add_passthrough with unfinished entry raises error" {
  let zip = @stream.Zip::new()
  let pt = @stream.ZipPassThrough::new("test.txt")
  let mut got_error = false
  zip.add_passthrough(pt) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "Unzip: result before finished raises error" {
  let unzip = @stream.Unzip::new()
  let mut got_error = false
  try {
    let _ = unzip.result()
  } catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "Unzip: push after finished raises error" {
  let data = string_to_bytes("Content")
  let files : Array[(String, FixedArray[Byte])] = [("test.txt", data)]
  let archive = @zip.zip_sync(files)
  let unzip = @stream.Unzip::new()
  unzip.push(archive, true)
  let mut got_error = false
  let chunk : FixedArray[Byte] = [b'\x00']
  unzip.push(chunk, false) catch {
    @types.FlateError(_) => got_error = true
  }
  assert_true(got_error)
}
