# moonzip - MoonBit Compression Library

A [MoonBit](https://docs.moonbitlang.com) compression library aiming for 100% compatibility with [fflate](https://github.com/101arrowz/fflate).

## Architecture

### Package Structure

```
moonzip/                  # Public API (deflateSync, inflateSync, gzipSync, etc.)
├── internal/
│   ├── checksum/         # CRC32, Adler-32
│   ├── bits/             # Bit-level read/write operations
│   ├── huffman/          # Huffman tree construction and code mapping
│   ├── lz77/             # LZ77 compression engine
│   ├── deflate/          # DEFLATE compress/decompress engine
│   ├── gzip/             # GZIP format handling
│   ├── zlib/             # Zlib format handling
│   └── zip/              # ZIP archive format handling
```

### Supported Formats

| Format | RFC/Spec | Compress | Decompress | Streaming |
|--------|----------|----------|------------|-----------|
| DEFLATE | RFC 1951 | Yes | Yes | Yes |
| GZIP | RFC 1952 | Yes | Yes | Yes |
| Zlib | RFC 1950 | Yes | Yes | Yes |
| ZIP | PKZIP APPNOTE | Yes | Yes | Yes |

### Error Codes

15 error codes (0-14) matching fflate's `FlateErrorCode`:
- 0: UnexpectedEOF
- 1: InvalidBlockType
- 2: InvalidLengthLiteral
- 3: InvalidDistance
- 4: StreamFinished
- 5: NoStreamHandler
- 6: InvalidHeader
- 7: NoCallback
- 8: InvalidUTF8
- 9: ExtraFieldTooLong
- 10: InvalidDate
- 11: FilenameTooLong
- 12: StreamFinishing
- 13: InvalidZipData
- 14: UnknownCompressionMethod

## Development

### Testing Strategy

TDD (Test-Driven Development):
1. Write tests first (`moon check` must pass — stubs allowed)
2. Implement until all tests pass (`moon test`)
3. Commit per task

### Commands

```sh
moon check              # Compile check
moon test               # Run all tests
moon test --update      # Update snapshots
moon fmt                # Format code
moon info               # Update interfaces
```

### Coding Conventions

- MoonBit code uses block style separated by `///|`
- Blocks are order-independent
- Prefer `assert_eq` for stable results, snapshot tests for recording behavior
- Keep deprecated code in `deprecated.mbt`

### Commit Convention

Format: `<phase>: <taskID> <brief description>`
- Example: `phase0: 0-0a clean up template files`
- Example: `phase1: 1-T1 add CRC32 tests`
