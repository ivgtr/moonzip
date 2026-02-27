// ============================================================
// moonzip CLI demo - compress / decompress examples
// ============================================================
// Run with: moon run cmd/

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
      let cp = ((b0 & 0x0F) << 12) |
        ((data[i + 1].to_int() & 0x3F) << 6) |
        (data[i + 2].to_int() & 0x3F)
      sb.write_char(cp.unsafe_to_char())
      i = i + 3
    } else if (b0 & 0xF8) == 0xF0 && i + 3 < len {
      let cp = ((b0 & 0x07) << 18) |
        ((data[i + 1].to_int() & 0x3F) << 12) |
        ((data[i + 2].to_int() & 0x3F) << 6) |
        (data[i + 3].to_int() & 0x3F)
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
fn demo_deflate() -> Unit {
  println("=== DEFLATE ===")
  let input = "Hello, moonzip! This is a DEFLATE compression demo."
  let data = str_to_bytes(input)
  println("  Original:     \{data.length()} bytes")
  try {
    let compressed = @deflate.deflate_sync(data)
    println("  Compressed:   \{compressed.length()} bytes")
    let decompressed = @deflate.inflate_sync(compressed)
    println("  Decompressed: \{decompressed.length()} bytes")
    println("  Content:      \{bytes_to_str(decompressed)}")
    println("  Round-trip OK: \{data.length() == decompressed.length()}")
  } catch {
    @types.FlateError(e) => println("  Error: \{e}")
  }
  println("")
}

///|
fn demo_gzip() -> Unit {
  println("=== GZIP ===")
  let input = "Hello, moonzip! This is a GZIP compression demo."
  let data = str_to_bytes(input)
  println("  Original:     \{data.length()} bytes")
  try {
    let compressed = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
      ..@types.GzipOptions::default(),
      filename: Some("hello.txt"),
    })
    println("  Compressed:   \{compressed.length()} bytes")
    let decompressed = @gzip.gunzip_sync(compressed)
    println("  Decompressed: \{decompressed.length()} bytes")
    println("  Content:      \{bytes_to_str(decompressed)}")
    println("  Round-trip OK: \{data.length() == decompressed.length()}")
  } catch {
    @types.FlateError(e) => println("  Error: \{e}")
  }
  println("")
}

///|
fn demo_zlib() -> Unit {
  println("=== Zlib ===")
  let input = "Hello, moonzip! This is a Zlib compression demo."
  let data = str_to_bytes(input)
  println("  Original:     \{data.length()} bytes")
  try {
    let compressed = @zlib.zlib_sync(data)
    println("  Compressed:   \{compressed.length()} bytes")
    let decompressed = @zlib.unzlib_sync(compressed)
    println("  Decompressed: \{decompressed.length()} bytes")
    println("  Content:      \{bytes_to_str(decompressed)}")
    println("  Round-trip OK: \{data.length() == decompressed.length()}")
  } catch {
    @types.FlateError(e) => println("  Error: \{e}")
  }
  println("")
}

///|
fn demo_zip() -> Unit {
  println("=== ZIP ===")
  let file1 = str_to_bytes("Content of file 1")
  let file2 = str_to_bytes("Content of file 2 with more data")
  let files : Array[(String, FixedArray[Byte])] = [
    ("hello.txt", file1),
    ("world.txt", file2),
  ]
  println("  Files to archive: \{files.length()}")
  try {
    let archive = @zip.zip_sync(files)
    println("  Archive size:     \{archive.length()} bytes")
    let listing = @zip.unzip_list(archive)
    println("  Entries:")
    for entry in listing {
      let comp_name = if entry.compression == 0 { "Store" } else { "Deflate" }
      println("    \{entry.name} (\{entry.original_size} bytes, \{comp_name})")
    }
    let extracted = @zip.unzip_sync(archive)
    println("  Extracted files:")
    for entry in extracted {
      println("    \{entry.0}: \{bytes_to_str(entry.1)}")
    }
  } catch {
    @types.FlateError(e) => println("  Error: \{e}")
  }
  println("")
}

///|
fn demo_gzip_multi_member() -> Unit {
  println("=== GZIP Multi-member ===")
  let data1 = str_to_bytes("First member. ")
  let data2 = str_to_bytes("Second member.")
  try {
    let gz1 = @gzip.gzip_sync(data1)
    let gz2 = @gzip.gzip_sync(data2)
    let multi = FixedArray::make(gz1.length() + gz2.length(), b'\x00')
    for i = 0; i < gz1.length(); i = i + 1 {
      multi[i] = gz1[i]
    }
    for i = 0; i < gz2.length(); i = i + 1 {
      multi[gz1.length() + i] = gz2[i]
    }
    println("  Member 1:         \{gz1.length()} bytes")
    println("  Member 2:         \{gz2.length()} bytes")
    println("  Concatenated:     \{multi.length()} bytes")
    let decompressed = @gzip.gunzip_sync(multi)
    println("  Decompressed:     \{decompressed.length()} bytes")
    println("  Content:          \{bytes_to_str(decompressed)}")
  } catch {
    @types.FlateError(e) => println("  Error: \{e}")
  }
  println("")
}

///|
fn main {
  println("moonzip - MoonBit compression library demo")
  println("==========================================")
  println("")
  demo_deflate()
  demo_gzip()
  demo_zlib()
  demo_zip()
  demo_gzip_multi_member()
  println("All demos completed.")
}
