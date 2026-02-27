# ivgtr/moonzip

A MoonBit compression library compatible with [fflate](https://github.com/101arrowz/fflate).

## Supported Formats

| Format  | RFC/Spec       | Compress | Decompress | Streaming |
| ------- | -------------- | -------- | ---------- | --------- |
| DEFLATE | RFC 1951       | Yes      | Yes        | Yes       |
| GZIP    | RFC 1952       | Yes      | Yes        | Yes       |
| Zlib    | RFC 1950       | Yes      | Yes        | Yes       |
| ZIP     | PKZIP APPNOTE  | Yes      | Yes        | -         |

## Installation

```
moon add ivgtr/moonzip
```

## API

### DEFLATE

```moonbit
// Compress
let compressed = @deflate.deflate_sync(data, opts=@types.DeflateOptions::{ level: 6, mem: 4, dictionary: None })

// Decompress
let decompressed = @deflate.inflate_sync(compressed)
```

### GZIP

Supports concatenated multi-member GZIP streams (RFC 1952 section 2.2).

```moonbit
// Compress
let compressed = @gzip.gzip_sync(data, opts=@types.GzipOptions::{
  level: 6,
  mem: 4,
  filename: Some("hello.txt"),
  mtime: Some(1700000000),
  comment: None,
  extra: None,
})

// Decompress (handles single and multi-member streams)
let decompressed = @gzip.gunzip_sync(compressed)
```

### Zlib

```moonbit
// Compress
let compressed = @zlib.zlib_sync(data, opts=@types.ZlibOptions::{ level: 6, mem: 4, dictionary: None })

// Decompress
let decompressed = @zlib.unzlib_sync(compressed)
```

### ZIP

```moonbit
// Create archive
let files : Array[(String, FixedArray[Byte])] = [
  ("hello.txt", data1),
  ("dir/world.txt", data2),
]
let archive = @zip.zip_sync(files, opts=@types.ZipOptions::{ level: 6, mtime: None, comment: None })

// List entries
let entries = @zip.unzip_list(archive)
// entries[i].name, entries[i].size, entries[i].original_size, entries[i].compression

// Extract all
let extracted = @zip.unzip_sync(archive)
// extracted[i].0 = filename, extracted[i].1 = data
```

### Auto-detect Decompression

```moonbit
// Automatically detects GZIP, Zlib, or raw DEFLATE
let decompressed = @moonzip.decompress_sync(compressed_data)
```

### Streaming

```moonbit
// DEFLATE streaming compression
let stream = @stream.DeflateStream::new(level=6)
stream.push(chunk1, false)
stream.push(chunk2, true)  // true = final chunk
let result = stream.result()

// GZIP streaming
let gz = @stream.GzipStream::new(level=6)
gz.push(data, true)
let compressed = gz.result()

let gunz = @stream.GunzipStream::new()
gunz.push(compressed, true)
let decompressed = gunz.result()

// Zlib streaming
let zs = @stream.ZlibStream::new(level=6)
let uzs = @stream.UnzlibStream::new()

// Raw inflate streaming
let inf = @stream.InflateStream::new()
let dec = @stream.DecompressStream::new()  // auto-detect format
```

### Utilities

```moonbit
// UTF-8 string <-> bytes conversion
let bytes = @utf8.str_to_u8("Hello")
let text = @utf8.str_from_u8(bytes)

// Checksums
let crc = @checksum.crc32(data)
let adl = @checksum.adler32(data)
```

### Error Handling

All compression/decompression functions raise `@types.FlateError`. Error codes (0-14) match fflate's `FlateErrorCode`:

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
  let result = @gzip.gunzip_sync(data)
} catch {
  @types.FlateError(code) => println("Error: \{code}")
}
```

## Demo

```sh
moon run cmd/
```

## License

MIT
