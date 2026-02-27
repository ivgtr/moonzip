// ============================================================
// DEFLATE Compression/Decompression Engine
// ============================================================
// Implements RFC 1951 DEFLATE compressed data format.
// Port of fflate's inflt/deflate functions to MoonBit.

// ============================================================
// Helper: Grow output buffer
// ============================================================

///|
fn grow(buf : FixedArray[Byte], new_len : Int) -> FixedArray[Byte] {
  let nb = FixedArray::make(new_len, b'\x00')
  for i = 0; i < buf.length(); i = i + 1 {
    nb[i] = buf[i]
  }
  nb
}

// ============================================================
// inflt - Core DEFLATE decompression
// ============================================================

///|
/// Core DEFLATE inflate function. Takes raw DEFLATE compressed data
/// and decompresses it. Handles all three block types:
///   - Type 0: Stored (uncompressed) blocks
///   - Type 1: Fixed Huffman codes
///   - Type 2: Dynamic Huffman codes
pub fn inflt(
  data : FixedArray[Byte],
  out_size_hint : Int,
) -> FixedArray[Byte] raise @types.FlateError {
  let sl = data.length()
  if sl == 0 {
    return FixedArray::make(0, b'\x00')
  }
  // Output buffer: start with hint or reasonable default
  let initial_size = if out_size_hint > 0 { out_size_hint } else { sl * 3 }
  let mut buf = FixedArray::make(initial_size, b'\x00')
  let mut bt = 0 // output byte position
  let mut pos = 0 // bit position in input
  let mut final_block = false
  // Pre-computed fixed Huffman tables (used for type 1 blocks)
  let flrm = @huffman.flrm
  let fdrm = @huffman.fdrm
  while not(final_block) {
    // Ensure we have enough bits for block header (3 bits minimum)
    if pos + 3 > sl * 8 {
      raise @types.FlateError::FlateError(@types.FlateErrorCode::UnexpectedEOF)
    }
    // Read BFINAL (1 bit) and BTYPE (2 bits)
    let bfinal = @bits.bits(data, pos, 1)
    pos = pos + 1
    let btype = @bits.bits(data, pos, 2)
    pos = pos + 2
    if bfinal != 0 {
      final_block = true
    }
    if btype == 0 {
      // ---- Type 0: Stored (uncompressed) block ----
      // Advance to byte boundary
      pos = @bits.shft(pos)
      let byte_pos = pos >> 3
      // Read LEN and NLEN (2 bytes each, little-endian)
      if byte_pos + 4 > sl {
        raise @types.FlateError::FlateError(
          @types.FlateErrorCode::UnexpectedEOF,
        )
      }
      let len = @bits.b2(data, byte_pos)
      let nlen = @bits.b2(data, byte_pos + 2)
      // Validate: LEN + NLEN should equal 0xFFFF
      if (len ^ nlen) != 0xFFFF {
        raise @types.FlateError::FlateError(
          @types.FlateErrorCode::InvalidLengthLiteral,
        )
      }
      let src_start = byte_pos + 4
      if src_start + len > sl {
        raise @types.FlateError::FlateError(
          @types.FlateErrorCode::UnexpectedEOF,
        )
      }
      // Ensure output buffer is large enough
      if bt + len > buf.length() {
        buf = grow(buf, bt + len + 32768)
      }
      // Copy raw bytes
      for i = 0; i < len; i = i + 1 {
        buf[bt + i] = data[src_start + i]
      }
      bt = bt + len
      pos = (src_start + len) * 8
    } else if btype == 1 || btype == 2 {
      // ---- Type 1 or 2: Huffman coded block ----
      let mut lmap : FixedArray[Int] = flrm // literal/length reverse map
      let mut dmap : FixedArray[Int] = fdrm // distance reverse map
      let mut lbits = 9 // max bits for literal/length
      let mut dbits = 5 // max bits for distance
      if btype == 2 {
        // ---- Type 2: Read dynamic Huffman tables ----
        // HLIT: number of literal/length codes (257-286)
        let hlit = @bits.bits(data, pos, 5) + 257
        pos = pos + 5
        // HDIST: number of distance codes (1-32)
        let hdist = @bits.bits(data, pos, 5) + 1
        pos = pos + 5
        // HCLEN: number of code length codes (4-19)
        let hclen = @bits.bits(data, pos, 4) + 4
        pos = pos + 4
        // Read code length code lengths (3 bits each, in clim order)
        let clt : FixedArray[Int] = FixedArray::make(19, 0)
        for i = 0; i < hclen; i = i + 1 {
          clt[@huffman.clim[i]] = @bits.bits(data, pos, 3)
          pos = pos + 3
        }
        // Build code length Huffman table
        let clb = @huffman.max_bits(clt)
        if clb == 0 {
          raise @types.FlateError::FlateError(
            @types.FlateErrorCode::InvalidLengthLiteral,
          )
        }
        let clm = @huffman.h_map(clt, clb, @huffman.Reverse)
        // Decode literal/length + distance code lengths
        let tl = hlit + hdist
        let ldt : FixedArray[Int] = FixedArray::make(tl, 0)
        let mut i = 0
        while i < tl {
          let r = clm[@bits.bits(data, pos, clb)]
          let s = r >> 4 // symbol
          let b = r & 15 // bit length
          pos = pos + b
          if s < 16 {
            // Literal code length
            ldt[i] = s
            i = i + 1
          } else if s == 16 {
            // Repeat previous value 3-6 times
            let rep = 3 + @bits.bits(data, pos, 2)
            pos = pos + 2
            let prev_val = if i > 0 { ldt[i - 1] } else { 0 }
            for _j = 0; _j < rep; _j = _j + 1 {
              ldt[i] = prev_val
              i = i + 1
            }
          } else if s == 17 {
            // Repeat 0 for 3-10 times
            let rep = 3 + @bits.bits(data, pos, 3)
            pos = pos + 3
            for _j = 0; _j < rep; _j = _j + 1 {
              ldt[i] = 0
              i = i + 1
            }
          } else {
            // s == 18: Repeat 0 for 11-138 times
            let rep = 11 + @bits.bits(data, pos, 7)
            pos = pos + 7
            for _j = 0; _j < rep; _j = _j + 1 {
              ldt[i] = 0
              i = i + 1
            }
          }
        }
        // Split into literal/length and distance code length tables
        let lt : FixedArray[Int] = FixedArray::make(hlit, 0)
        for j = 0; j < hlit; j = j + 1 {
          lt[j] = ldt[j]
        }
        let dt : FixedArray[Int] = FixedArray::make(hdist, 0)
        for j = 0; j < hdist; j = j + 1 {
          dt[j] = ldt[hlit + j]
        }
        // Build reverse maps
        lbits = @huffman.max_bits(lt)
        dbits = @huffman.max_bits(dt)
        if lbits == 0 {
          raise @types.FlateError::FlateError(
            @types.FlateErrorCode::InvalidLengthLiteral,
          )
        }
        lmap = @huffman.h_map(lt, lbits, @huffman.Reverse)
        if dbits > 0 {
          dmap = @huffman.h_map(dt, dbits, @huffman.Reverse)
        }
      }
      // ---- Decode Huffman symbols ----
      let mut done = false
      while not(done) {
        // Read literal/length symbol
        let r = lmap[@bits.bits(data, pos, lbits)]
        let sym = r >> 4
        let blen = r & 15
        if blen == 0 {
          raise @types.FlateError::FlateError(
            @types.FlateErrorCode::InvalidLengthLiteral,
          )
        }
        pos = pos + blen
        if sym < 256 {
          // Literal byte
          if bt >= buf.length() {
            buf = grow(buf, buf.length() + 32768)
          }
          buf[bt] = sym.to_byte()
          bt = bt + 1
        } else if sym == 256 {
          // End of block
          done = true
        } else {
          // Length/distance pair
          let lc = sym - 257 // length code index (0-28)
          // Validate length code
          if lc >= 29 {
            raise @types.FlateError::FlateError(
              @types.FlateErrorCode::InvalidLengthLiteral,
            )
          }
          // Base length + extra bits
          let add_bits = @huffman.fleb[lc]
          let mut length = @huffman.fl[lc]
          if add_bits > 0 {
            length = length + @bits.bits(data, pos, add_bits)
            pos = pos + add_bits
          }
          // Read distance code
          if dbits == 0 {
            raise @types.FlateError::FlateError(
              @types.FlateErrorCode::InvalidDistance,
            )
          }
          let dr = dmap[@bits.bits(data, pos, dbits)]
          let dsym = dr >> 4
          let dblen = dr & 15
          if dblen == 0 {
            raise @types.FlateError::FlateError(
              @types.FlateErrorCode::InvalidDistance,
            )
          }
          pos = pos + dblen
          // Base distance + extra bits
          let dadd_bits = @huffman.fdeb[dsym]
          let mut dist = @huffman.fd[dsym]
          if dadd_bits > 0 {
            dist = dist + @bits.bits16(data, pos, dadd_bits)
            pos = pos + dadd_bits
          }
          // Validate distance
          if dist > bt {
            raise @types.FlateError::FlateError(
              @types.FlateErrorCode::InvalidDistance,
            )
          }
          // Ensure output buffer is large enough
          if bt + length > buf.length() {
            buf = grow(buf, bt + length + 32768)
          }
          // Copy from back-reference (byte at a time for overlapping copies)
          let src = bt - dist
          for ci = 0; ci < length; ci = ci + 1 {
            buf[bt + ci] = buf[src + ci]
          }
          bt = bt + length
        }
      }
    } else {
      // Invalid block type (3)
      raise @types.FlateError::FlateError(
        @types.FlateErrorCode::InvalidBlockType,
      )
    }
  }
  // Trim output to actual size
  if bt == buf.length() {
    buf
  } else {
    let out = FixedArray::make(bt, b'\x00')
    for i = 0; i < bt; i = i + 1 {
      out[i] = buf[i]
    }
    out
  }
}

// ============================================================
// wfblk - Write uncompressed (stored) block
// ============================================================

///|
/// Write an uncompressed (stored) block to the output.
/// Returns the number of bytes written to `out`.
///
/// Parameters:
///   out     - Output buffer (must be large enough)
///   out_pos - Start position in output
///   data    - Source data
///   offset  - Start offset in source data
///   len     - Number of bytes to write
///   final_  - Whether this is the final block
fn wfblk(
  out : FixedArray[Byte],
  out_pos : Int,
  data : FixedArray[Byte],
  offset : Int,
  len : Int,
  final_ : Bool,
) -> Int {
  let mut pos = out_pos * 8
  // Write BFINAL (1 bit) + BTYPE=00 (2 bits)
  let header = if final_ { 1 } else { 0 }
  @bits.wbits(out, pos, header, 3)
  pos = pos + 3
  // Advance to byte boundary
  pos = @bits.shft(pos)
  let byte_pos = pos >> 3
  // Write LEN (2 bytes LE)
  @bits.wbytes2(out, byte_pos, len)
  // Write NLEN (2 bytes LE) - one's complement of LEN
  @bits.wbytes2(out, byte_pos + 2, len ^ 0xFFFF)
  // Copy data
  let data_start = byte_pos + 4
  for i = 0; i < len; i = i + 1 {
    out[data_start + i] = data[offset + i]
  }
  data_start + len
}

// ============================================================
// wblk - Write a Huffman-encoded block
// ============================================================

///|
/// Write a Huffman-encoded block (placeholder for LZ77-based compression).
/// Currently writes using fixed Huffman codes for literal-only data (no LZ77 matches).
///
/// Parameters:
///   out     - Output buffer
///   pos     - Current bit position in output
///   data    - Source data (literal bytes)
///   offset  - Start offset in source data
///   len     - Number of bytes to encode
///   final_  - Whether this is the final block
///
/// Returns the new bit position after writing.
fn wblk(
  out : FixedArray[Byte],
  pos : Int,
  data : FixedArray[Byte],
  offset : Int,
  len : Int,
  final_ : Bool,
) -> Int {
  let mut p = pos
  // Write BFINAL (1 bit) + BTYPE=01 (2 bits) for fixed Huffman
  let header = if final_ { 0b011 } else { 0b010 }
  @bits.wbits(out, p, header, 3)
  p = p + 3
  // Write each byte as a fixed Huffman literal
  let flm = @huffman.flm
  let flt = @huffman.flt
  for i = 0; i < len; i = i + 1 {
    let sym = data[offset + i].to_int()
    let code = flm[sym]
    let bits = flt[sym]
    @bits.wbits16(out, p, code, bits)
    p = p + bits
  }
  // Write end-of-block symbol (256)
  let eob_code = flm[256]
  let eob_bits = flt[256]
  @bits.wbits16(out, p, eob_code, eob_bits)
  p = p + eob_bits
  p
}

// ============================================================
// dopt - Process deflate options
// ============================================================

///|
/// Process and validate deflate options.
/// Returns (level, mem) clamped to valid ranges.
///
/// Parameters:
///   opts - DeflateOptions
///
/// Returns (level, mem) tuple as a FixedArray of 2 Ints.
fn dopt(opts : @types.DeflateOptions) -> FixedArray[Int] {
  let mut level = opts.level
  let mut mem = opts.mem
  // Clamp level to 0-9
  if level < 0 {
    level = 0
  }
  if level > 9 {
    level = 9
  }
  // Clamp mem to 0-12
  if mem < 0 {
    mem = 0
  }
  if mem > 12 {
    mem = 12
  }
  [level, mem]
}

// ============================================================
// inflate_sync - Synchronous decompression
// ============================================================

///|
/// Synchronously decompress DEFLATE compressed data.
///
/// Parameters:
///   data - DEFLATE compressed data
///   opts - Decompression options (optional size hint)
///
/// Returns decompressed data.
pub fn inflate_sync(
  data : FixedArray[Byte],
  opts? : @types.InflateOptions = @types.InflateOptions::default(),
) -> FixedArray[Byte] raise @types.FlateError {
  let size_hint = match opts.size {
    Some(s) => s
    None => 0
  }
  inflt(data, size_hint)
}

// ============================================================
// deflate_sync - Synchronous compression
// ============================================================

///|
/// Synchronously compress data using DEFLATE.
///
/// Currently supports:
///   - Level 0: Store blocks (no compression)
///   - Level 1-9: Fixed Huffman coding (literal-only, no LZ77 matches yet)
///
/// Parameters:
///   data - Uncompressed data
///   opts - Compression options (level, mem, dictionary)
///
/// Returns DEFLATE compressed data.
pub fn deflate_sync(
  data : FixedArray[Byte],
  opts? : @types.DeflateOptions = @types.DeflateOptions::default(),
) -> FixedArray[Byte] raise @types.FlateError {
  let params = dopt(opts)
  // TODO: dictionary support for LZ77 compression
  match opts.dictionary {
    Some(_) =>
      raise @types.FlateError::FlateError(@types.FlateErrorCode::InvalidHeader)
    None => ()
  }
  let level = params[0]
  let dl = data.length()
  if level == 0 {
    // Store blocks (no compression)
    // Each stored block can hold up to 65535 bytes
    let max_block = 65535
    let num_blocks = if dl == 0 { 1 } else { (dl + max_block - 1) / max_block }
    // Each block has 5 bytes overhead (1 header byte + 2 LEN + 2 NLEN)
    let out_size = dl + num_blocks * 5
    let out = FixedArray::make(out_size, b'\x00')
    let mut out_pos = 0
    let mut offset = 0
    let mut remaining = dl
    if dl == 0 {
      // Write a single empty final stored block
      out_pos = wfblk(out, out_pos, data, 0, 0, true)
    } else {
      while remaining > 0 {
        let block_len = if remaining > max_block {
          max_block
        } else {
          remaining
        }
        remaining = remaining - block_len
        let is_final = remaining == 0
        out_pos = wfblk(out, out_pos, data, offset, block_len, is_final)
        offset = offset + block_len
      }
    }
    // Trim output
    if out_pos == out.length() {
      out
    } else {
      let result = FixedArray::make(out_pos, b'\x00')
      for i = 0; i < out_pos; i = i + 1 {
        result[i] = out[i]
      }
      result
    }
  } else {
    // Level 1-9: Fixed Huffman coding (literal-only for now, LZ77 placeholder)
    // Maximum expansion: each byte as fixed Huffman literal is at most 9 bits,
    // plus 3 bits header + 7 bits end-of-block per block.
    // Worst case: ~9/8 * dl + overhead per block
    let max_block = 65535
    let num_blocks = if dl == 0 { 1 } else { (dl + max_block - 1) / max_block }
    let out_size = dl * 9 / 8 + num_blocks * 4 + 16
    let out = FixedArray::make(out_size, b'\x00')
    let mut bit_pos = 0
    let mut offset = 0
    let mut remaining = dl
    if dl == 0 {
      // Write empty final block with fixed Huffman (just header + EOB)
      bit_pos = wblk(out, bit_pos, data, 0, 0, true)
    } else {
      while remaining > 0 {
        let block_len = if remaining > max_block {
          max_block
        } else {
          remaining
        }
        remaining = remaining - block_len
        let is_final = remaining == 0
        bit_pos = wblk(out, bit_pos, data, offset, block_len, is_final)
        offset = offset + block_len
      }
    }
    // Calculate final byte length
    let byte_len = (bit_pos + 7) >> 3
    if byte_len == out.length() {
      out
    } else {
      let result = FixedArray::make(byte_len, b'\x00')
      for i = 0; i < byte_len; i = i + 1 {
        result[i] = out[i]
      }
      result
    }
  }
}
