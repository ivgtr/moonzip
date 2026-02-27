# ivgtr/moonzip

A MoonBit compression library compatible with [fflate](https://github.com/101arrowz/fflate).

fflate Sync API compatibility: 100% (27/27)

| Category        | Coverage |
| --------------- | -------- |
| Sync functions  | 12 / 12  |
| Sync streaming  | 13 / 13  |
| Utility         | 2 / 2   |

> Async APIs (Web Worker-based) are out of scope for MoonBit/WASM runtime.

## Supported Formats

| Format  | RFC/Spec       | Compress | Decompress | Streaming |
| ------- | -------------- | -------- | ---------- | --------- |
| DEFLATE | RFC 1951       | Yes      | Yes        | Yes       |
| GZIP    | RFC 1952       | Yes      | Yes        | Yes       |
| Zlib    | RFC 1950       | Yes      | Yes        | Yes       |
| ZIP     | PKZIP APPNOTE  | Yes      | Yes        | Yes       |

## Features

- LZ77 + Dynamic Huffman compression (levels 0-9)
- Dictionary support (DEFLATE / Zlib FDICT)
- Multi-member GZIP decompression
- ZIP64 read support, per-entry options, archive comments
- Incremental streaming with `ondata` callbacks
- UTF-8 / Latin-1 string conversion, custom filename decoder for non-UTF-8 archives

## Installation

```
moon add ivgtr/moonzip
```

## API

### DEFLATE

```moonbit
// Compress (level 0-9, mem 0-12)
let compressed = @moonzip.deflate_sync(data, opts={ level: 6, mem: 4, dictionary: None })

// Decompress
let decompressed = @moonzip.inflate_sync(compressed)
```

### GZIP

Supports concatenated multi-member GZIP streams (RFC 1952 section 2.2).

```moonbit
// Compress
let compressed = @moonzip.gzip_sync(data, opts={
  level: 6,
  mem: 4,
  filename: Some("hello.txt"),
  mtime: Some(1700000000),
  comment: None,
  extra: None,
})

// Decompress (handles single and multi-member streams)
let decompressed = @moonzip.gunzip_sync(compressed, opts={ dictionary: None })

// Alias: compress_sync = gzip_sync
let compressed = @moonzip.compress_sync(data)
```

### Zlib

Supports preset dictionaries via FDICT flag.

```moonbit
// Compress
let compressed = @moonzip.zlib_sync(data, opts={ level: 6, mem: 4, dictionary: None })

// Decompress
let decompressed = @moonzip.unzlib_sync(compressed, opts={ dictionary: None })

// With dictionary
let dict = @moonzip.str_to_u8("common words here")
let compressed = @moonzip.zlib_sync(data, opts={ level: 6, mem: 4, dictionary: Some(dict) })
let decompressed = @moonzip.unzlib_sync(compressed, opts={ dictionary: Some(dict) })
```

### ZIP

```moonbit
// Create archive
let files : Array[(String, FixedArray[Byte])] = [
  ("hello.txt", data1),
  ("dir/world.txt", data2),
]
let archive = @moonzip.zip_sync(files, opts={ level: 6, mtime: None, comment: None })

// Per-entry options
let entry_opts : Array[@types.ZipEntryOptions?] = [
  Some({ level: 0, mtime: None, comment: None, extra: None }),  // Store without compression
  None,  // Use global opts
]
let archive = @moonzip.zip_sync(files, opts={ level: 6, mtime: None, comment: None }, entry_opts~)

// List entries
let entries = @moonzip.unzip_list(archive)
// entries[i].name, entries[i].size, entries[i].original_size, entries[i].compression,
// entries[i].mtime, entries[i].attrs, entries[i].comment, entries[i].extra

// Extract all
let extracted = @moonzip.unzip_sync(archive)
// extracted[i].0 = filename, extracted[i].1 = data

// Extract with filter
let txt_only = @moonzip.unzip_sync(archive, filter=fn(info) { info.name.contains(".txt") })

// Custom filename decoder (for non-UTF-8 archives like Shift_JIS)
let decoded = @moonzip.unzip_list(archive, decode=fn(raw) {
  // raw contains the non-UTF-8 bytes; return decoded String
  my_shift_jis_decoder(raw)
})

let extracted = @moonzip.unzip_sync(archive, decode=fn(raw) {
  my_shift_jis_decoder(raw)
})
// decode is only called for entries without the UTF-8 flag (bit 11)
```

### Auto-detect Decompression

```moonbit
// Automatically detects GZIP, Zlib, or raw DEFLATE
let decompressed = @moonzip.decompress_sync(compressed_data)
```

### Streaming

```moonbit
// DEFLATE streaming with ondata callback
let stream = @stream.DeflateStream::new(level=6, ondata=fn(chunk, final) {
  // handle partial output
})
stream.push(chunk1, false)
stream.push(chunk2, true)  // true = final chunk
let result = stream.result()

// GZIP streaming
let gz = @stream.GzipStream::new(level=6)
gz.push(data, true)
let compressed = gz.result()

// Gunzip with multi-member callback
let gunz = @stream.GunzipStream::new(onmember=fn(member_data) {
  // called for each GZIP member
})
gunz.push(compressed, true)
let decompressed = gunz.result()

// Zlib / Inflate / Decompress streaming
let zs = @stream.ZlibStream::new(level=6)
let uzs = @stream.UnzlibStream::new()
let inf = @stream.InflateStream::new()
let dec = @stream.DecompressStream::new()  // auto-detect format

// ZIP streaming creation
let zip = @stream.Zip::new()
let entry = @stream.ZipDeflate::new("file.txt", level=6)
entry.push(data, true)
zip.add_deflate(entry)
let archive = zip.finish()

// UTF-8 streaming
let enc = @stream.EncodeUTF8::new(ondata=fn(bytes, final) { })
let dec = @stream.DecodeUTF8::new(ondata=fn(text, final) { })
```

### Utilities

```moonbit
// UTF-8 string <-> bytes conversion
let bytes = @moonzip.str_to_u8("Hello")
let text = @moonzip.str_from_u8(bytes)

// Latin-1 mode
let latin1_bytes = @moonzip.str_to_u8("café", latin1=true)

// Checksums
let crc = @moonzip.crc32(data)
let adl = @moonzip.adler32(data)
```

### Error Handling

Decompression functions (`inflate_sync`, `gunzip_sync`, `decompress_sync`, `unzlib_sync`, `unzip_sync`, `unzip_list`, `str_from_u8`) raise `@types.FlateError`. Compression functions are infallible. Error codes (0-14) match fflate's `FlateErrorCode`:

| Code | Name                      |
| ---- | ------------------------- |
| 0    | UnexpectedEOF             |
| 1    | InvalidBlockType          |
| 2    | InvalidLengthLiteral      |
| 3    | InvalidDistance            |
| 4    | StreamFinished            |
| 5    | NoStreamHandler           |
| 6    | InvalidHeader             |
| 7    | NoCallback                |
| 8    | InvalidUTF8               |
| 9    | ExtraFieldTooLong         |
| 10   | InvalidDate               |
| 11   | FilenameTooLong           |
| 12   | StreamFinishing           |
| 13   | InvalidZipData            |
| 14   | UnknownCompressionMethod  |

```moonbit
try {
  let result = @moonzip.gunzip_sync(data)
} catch {
  @types.FlateError(code) => println("Error: \{code}")
}
```

## Demo

**[Online Demo](https://ivgtr.github.io/moonzip/)**

```sh
# CLI demo
moon run cmd/

# Web demo
moon build --target js && cp _build/js/debug/build/demo/demo.js demo/demo.js
# Open demo/index.html in a browser
```

## License

MIT
