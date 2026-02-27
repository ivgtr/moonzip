///|
/// Error codes compatible with fflate's FlateErrorCode (0-14).
pub(all) enum FlateErrorCode {
  UnexpectedEOF // 0
  InvalidBlockType // 1
  InvalidLengthLiteral // 2
  InvalidDistance // 3
  StreamFinished // 4
  NoStreamHandler // 5
  InvalidHeader // 6
  NoCallback // 7
  InvalidUTF8 // 8
  ExtraFieldTooLong // 9
  InvalidDate // 10
  FilenameTooLong // 11
  StreamFinishing // 12
  InvalidZipData // 13
  UnknownCompressionMethod // 14
} derive(Eq, Show)

///|
pub(all) suberror FlateError {
  FlateError(FlateErrorCode)
}

///|
/// Returns the numeric code for this error.
pub fn FlateErrorCode::code(self : FlateErrorCode) -> Int {
  match self {
    UnexpectedEOF => 0
    InvalidBlockType => 1
    InvalidLengthLiteral => 2
    InvalidDistance => 3
    StreamFinished => 4
    NoStreamHandler => 5
    InvalidHeader => 6
    NoCallback => 7
    InvalidUTF8 => 8
    ExtraFieldTooLong => 9
    InvalidDate => 10
    FilenameTooLong => 11
    StreamFinishing => 12
    InvalidZipData => 13
    UnknownCompressionMethod => 14
  }
}

///|
/// Options for DEFLATE compression.
pub(all) struct DeflateOptions {
  /// Compression level (0-9). 0 = no compression, 9 = best compression. Default: 6.
  level : Int
  /// Memory level (0-12). Controls hash table size. Default: 4.
  mem : Int
  /// Preset dictionary for compression.
  dictionary : FixedArray[Byte]?
} derive(Show)

///|
pub fn DeflateOptions::default() -> DeflateOptions {
  { level: 6, mem: 4, dictionary: None }
}

///|
/// Options for DEFLATE decompression.
pub(all) struct InflateOptions {
  /// Expected output size hint (for pre-allocation).
  size : Int?
  /// Preset dictionary for decompression.
  dictionary : FixedArray[Byte]?
} derive(Show)

///|
pub fn InflateOptions::default() -> InflateOptions {
  { size: None, dictionary: None }
}

///|
/// Options for GZIP compression (extends DeflateOptions).
pub(all) struct GzipOptions {
  /// Compression level (0-9). Default: 6.
  level : Int
  /// Memory level (0-12). Default: 4.
  mem : Int
  /// Modification time as Unix timestamp in seconds.
  mtime : Int?
  /// Original filename (null-terminated in output).
  filename : String?
  /// Comment string.
  comment : String?
  /// Extra field data.
  extra : FixedArray[Byte]?
} derive(Show)

///|
pub fn GzipOptions::default() -> GzipOptions {
  { level: 6, mem: 4, mtime: None, filename: None, comment: None, extra: None }
}

///|
/// Options for Zlib compression (extends DeflateOptions).
pub(all) struct ZlibOptions {
  /// Compression level (0-9). Default: 6.
  level : Int
  /// Memory level (0-12). Default: 4.
  mem : Int
  /// Preset dictionary.
  dictionary : FixedArray[Byte]?
} derive(Show)

///|
pub fn ZlibOptions::default() -> ZlibOptions {
  { level: 6, mem: 4, dictionary: None }
}

///|
/// File attributes for ZIP entries.
pub(all) struct ZipAttributes {
  /// OS identifier.
  os : Int?
  /// File attributes.
  attrs : Int?
  /// File comment.
  comment : String?
  /// Extra fields (tag -> data).
  extra : Map[Int, FixedArray[Byte]]?
} derive(Show)

///|
/// Options for individual ZIP file entries.
pub(all) struct ZipEntryOptions {
  /// Compression level (0-9). 0 = Store, 1-9 = Deflate. Default: 6.
  level : Int
  /// Modification time as Unix timestamp.
  mtime : Int?
  /// File attributes.
  attrs : ZipAttributes?
} derive(Show)

///|
pub fn ZipEntryOptions::default() -> ZipEntryOptions {
  { level: 6, mtime: None, attrs: None }
}

///|
/// Options for ZIP archive creation.
pub(all) struct ZipOptions {
  /// Default compression level for all entries. Default: 6.
  level : Int
  /// Default modification time for all entries.
  mtime : Int?
  /// Comment for the ZIP archive.
  comment : String?
} derive(Show)

///|
pub fn ZipOptions::default() -> ZipOptions {
  { level: 6, mtime: None, comment: None }
}

///|
/// Information about a file within a ZIP archive (used for filtering).
pub(all) struct UnzipFileInfo {
  /// File name (path within archive).
  name : String
  /// Compressed size in bytes.
  size : Int
  /// Original (uncompressed) size in bytes.
  original_size : Int
  /// Compression method (0 = Store, 8 = Deflate).
  compression : Int
  /// Modification time as Unix timestamp.
  mtime : Int
  /// File attributes.
  attrs : Int
  /// File comment.
  comment : String
  /// Extra fields (tag -> data).
  extra : Map[Int, FixedArray[Byte]]
} derive(Show)
