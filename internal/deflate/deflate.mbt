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
/// Core DEFLATE inflate function that also returns the number of
/// input bytes consumed. Used by GZIP multi-member decompression.
///
/// When a dictionary is provided, it is pre-loaded into the output buffer
/// so that back-references can reach into the dictionary data.
/// The dictionary portion is stripped from the final output.
///
/// Returns (decompressed_data, bytes_consumed).
pub fn inflt_pos(
  data : FixedArray[Byte],
  out_size_hint : Int,
  dictionary? : FixedArray[Byte]? = None,
) -> (FixedArray[Byte], Int) raise @types.FlateError {
  let sl = data.length()
  if sl == 0 {
    return (FixedArray::make(0, b'\x00'), 0)
  }
  // Dictionary: use last 32KB if provided
  let dict_len = match dictionary {
    Some(d) => if d.length() > 32768 { 32768 } else { d.length() }
    None => 0
  }
  // Output buffer: start with hint or reasonable default
  let base_size = if out_size_hint > 0 { out_size_hint } else { sl * 3 }
  let initial_size = base_size + dict_len
  let mut buf = FixedArray::make(initial_size, b'\x00')
  // Pre-load dictionary into the beginning of the output buffer
  match dictionary {
    Some(d) => {
      let d_offset = d.length() - dict_len
      for i = 0; i < dict_len; i = i + 1 {
        buf[i] = d[d_offset + i]
      }
    }
    None => ()
  }
  let mut bt = dict_len // output byte position (after dictionary)
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
  // Calculate bytes consumed (round up bit position to next byte)
  let bytes_consumed = (pos + 7) >> 3
  // Trim output to actual size, stripping dictionary prefix
  let out_len = bt - dict_len
  if out_len == buf.length() && dict_len == 0 {
    (buf, bytes_consumed)
  } else {
    let out = FixedArray::make(out_len, b'\x00')
    for i = 0; i < out_len; i = i + 1 {
      out[i] = buf[dict_len + i]
    }
    (out, bytes_consumed)
  }
}

// ============================================================
// inflt - Core DEFLATE decompression (convenience wrapper)
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
  dictionary? : FixedArray[Byte]? = None,
) -> FixedArray[Byte] raise @types.FlateError {
  let (result, _) = inflt_pos(data, out_size_hint, dictionary~)
  result
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
// Level parameters: nice match length and chain length per level
// ============================================================

///|
/// Nice match length threshold per compression level (1-9).
/// When a match of this length or longer is found, stop searching.
let nice_len : FixedArray[Int] = [0, 8, 16, 32, 64, 128, 128, 256, 258, 258]

///|
/// Maximum hash chain length per compression level (1-9).
/// Higher values find better matches but are slower.
let chain_len : FixedArray[Int] = [0, 4, 4, 8, 16, 32, 128, 256, 4096, 32768]

// ============================================================
// LZ77 match finder
// ============================================================

///|
/// Find the longest match at the current position using hash chains.
/// Returns (best_length, best_distance) where best_length >= 3 or 0 if no match.
/// Hash/prev arrays store 1-based positions (0 = empty sentinel).
fn find_match(
  data : FixedArray[Byte],
  pos : Int,
  dl : Int,
  hsh : FixedArray[Int],
  prev : FixedArray[Int],
  hash_size : Int,
  max_chain : Int,
  nice : Int,
) -> (Int, Int) {
  let max_len = if dl - pos < 258 { dl - pos } else { 258 }
  if max_len < 3 {
    return (0, 0)
  }
  // Compute 3-byte hash
  let h = (
      (data[pos].to_int() << 16) |
      (data[pos + 1].to_int() << 8) |
      data[pos + 2].to_int()
    ) %
    hash_size
  let old_head = hsh[h]
  // Update hash chain (1-based: store pos+1)
  prev[pos & 32767] = old_head
  hsh[h] = pos + 1
  let mut best_len = 0
  let mut best_dist = 0
  let mut chains = max_chain
  let max_dist = if pos < 32768 { pos } else { 32768 }
  let mut cur = old_head
  while cur > 0 && chains > 0 {
    let candidate = cur - 1 // Convert back to 0-based
    let dist = pos - candidate
    if dist > max_dist || dist < 1 {
      break
    }
    // Quick check: compare last matched byte + first byte before full scan
    if candidate + best_len < dl &&
      pos + best_len < dl &&
      data[candidate + best_len] == data[pos + best_len] &&
      data[candidate] == data[pos] {
      let mut len = 0
      let cmp_limit = if max_len < dl - candidate {
        max_len
      } else {
        dl - candidate
      }
      while len < cmp_limit && data[candidate + len] == data[pos + len] {
        len = len + 1
      }
      if len > best_len {
        best_len = len
        best_dist = dist
        if len >= nice {
          break
        }
      }
    }
    cur = prev[candidate & 32767]
    chains = chains - 1
  }
  if best_len < 3 {
    (0, 0)
  } else {
    (best_len, best_dist)
  }
}

// ============================================================
// wblk - Write a Huffman-encoded block with LZ77 symbols
// ============================================================

///|
/// Write a Huffman-encoded DEFLATE block from LZ77 symbol buffer.
///
/// The symbol buffer format: interleaved entries where:
///   - Literal byte: just the byte value (0-255) stored in syms[i], dsyms[i] = 0
///   - Length/distance pair: syms[i] = length (3-258), dsyms[i] = distance (1-32768)
///   - End marker: syms[i] = 256
///
/// Parameters:
///   out     - Output buffer
///   pos     - Current bit position in output
///   syms    - Symbol buffer (literals or lengths)
///   dsyms   - Distance buffer (0 for literals, >0 for back-references)
///   nsym    - Number of symbols
///   lit_freq - Literal/length frequency table (286 entries)
///   dist_freq - Distance frequency table (30 entries)
///   final_  - Whether this is the final block
///
/// Returns the new bit position after writing.
fn wblk(
  out : FixedArray[Byte],
  pos : Int,
  syms : FixedArray[Int],
  dsyms : FixedArray[Int],
  nsym : Int,
  lit_freq : FixedArray[Int],
  dist_freq : FixedArray[Int],
  final_ : Bool,
) -> Int {
  let mut p = pos
  // Build Huffman trees from frequency data
  let lt = @huffman.h_tree(lit_freq, 15)
  let dt_r = @huffman.h_tree(dist_freq, 15)
  let ltc = @huffman.lc(lt.t)
  let dtc = @huffman.lc(dt_r.t)
  // Compute bit costs for dynamic vs fixed
  let dyn_bits = @huffman.clen(lit_freq, lt.t) +
    @huffman.clen(dist_freq, dt_r.t)
  let fixed_bits = @huffman.clen(lit_freq, @huffman.flt) +
    @huffman.clen(dist_freq, @huffman.fdt)
  // Estimate dynamic header overhead
  let mut hdr_bits = 17 // BFINAL(1) + BTYPE(2) + HLIT(5) + HDIST(5) + HCLEN(4)
  let fclim = @huffman.fclim
  for i = 0; i < ltc.c.length(); i = i + 1 {
    hdr_bits = hdr_bits + 3 + fclim[ltc.c[i] & 31]
  }
  for i = 0; i < dtc.c.length(); i = i + 1 {
    hdr_bits = hdr_bits + 3 + fclim[dtc.c[i] & 31]
  }
  let use_dynamic = dyn_bits + hdr_bits < fixed_bits + 3
  // Write header and get encoding tables
  let (lm, lt_arr, dm, dt_arr) = if use_dynamic {
    p = write_dyn_header(out, p, ltc, dtc, final_)
    (
      @huffman.h_map(lt.t, lt.l, @huffman.Forward),
      lt.t,
      @huffman.h_map(dt_r.t, dt_r.l, @huffman.Forward),
      dt_r.t,
    )
  } else {
    let bfinal = if final_ { 1 } else { 0 }
    @bits.wbits(out, p, bfinal | 0b010, 3)
    p = p + 3
    (@huffman.flm, @huffman.flt, @huffman.fdm, @huffman.fdt)
  }
  // Write symbols
  p = write_syms(out, p, syms, dsyms, nsym, lm, lt_arr, dm, dt_arr)
  // Write end-of-block symbol (256)
  let eob_code = lm[256]
  let eob_bits = lt_arr[256]
  @bits.wbits16(out, p, eob_code, eob_bits)
  p = p + eob_bits
  p
}

///|
/// Write the dynamic Huffman header (HLIT, HDIST, HCLEN, code length tables).
/// Returns the new bit position.
fn write_dyn_header(
  out : FixedArray[Byte],
  pos : Int,
  ltc : @huffman.LcResult,
  dtc : @huffman.LcResult,
  final_ : Bool,
) -> Int {
  let mut p = pos
  let bfinal = if final_ { 1 } else { 0 }
  // BFINAL + BTYPE=10 (dynamic)
  @bits.wbits(out, p, bfinal | 0b100, 3)
  p = p + 3
  // Write HLIT, HDIST
  let hlit = ltc.n
  let hdist = if dtc.n == 0 { 1 } else { dtc.n }
  @bits.wbits(out, p, hlit - 257, 5)
  p = p + 5
  @bits.wbits(out, p, hdist - 1, 5)
  p = p + 5
  // Build code length alphabet frequency
  let clt : FixedArray[Int] = FixedArray::make(19, 0)
  for i = 0; i < ltc.c.length(); i = i + 1 {
    clt[ltc.c[i] & 31] = clt[ltc.c[i] & 31] + 1
  }
  if dtc.n == 0 {
    clt[0] = clt[0] + 1
  } else {
    for i = 0; i < dtc.c.length(); i = i + 1 {
      clt[dtc.c[i] & 31] = clt[dtc.c[i] & 31] + 1
    }
  }
  // Find HCLEN: number of code length codes to transmit
  let clim = @huffman.clim
  let mut hclen = 19
  while hclen > 4 && clt[clim[hclen - 1]] == 0 {
    hclen = hclen - 1
  }
  @bits.wbits(out, p, hclen - 4, 4)
  p = p + 4
  // Build code length Huffman tree
  let cl_tree = @huffman.h_tree(clt, 7)
  let clm = @huffman.h_map(cl_tree.t, cl_tree.l, @huffman.Forward)
  let cl_lens = cl_tree.t
  // Write code length code lengths in clim order
  for i = 0; i < hclen; i = i + 1 {
    let idx = clim[i]
    let len = if idx < cl_lens.length() { cl_lens[idx] } else { 0 }
    @bits.wbits(out, p, len, 3)
    p = p + 3
  }
  // Write encoded literal/length code lengths
  p = write_cl_codes(out, p, ltc.c, clm, cl_lens)
  // Write encoded distance code lengths
  if dtc.n == 0 {
    let code = clm[0]
    let bits = cl_lens[0]
    @bits.wbits16(out, p, code, bits)
    p = p + bits
  } else {
    p = write_cl_codes(out, p, dtc.c, clm, cl_lens)
  }
  p
}

///|
/// Write LZ77 symbols using the given Huffman encoding tables.
fn write_syms(
  out : FixedArray[Byte],
  pos : Int,
  syms : FixedArray[Int],
  dsyms : FixedArray[Int],
  nsym : Int,
  lm : FixedArray[Int],
  lt_arr : FixedArray[Int],
  dm : FixedArray[Int],
  dt_arr : FixedArray[Int],
) -> Int {
  let fleb = @huffman.fleb
  let fdeb = @huffman.fdeb
  let mut p = pos
  for i = 0; i < nsym; i = i + 1 {
    let s = syms[i]
    if dsyms[i] == 0 {
      // Literal
      let code = lm[s]
      let bits = lt_arr[s]
      @bits.wbits16(out, p, code, bits)
      p = p + bits
    } else {
      // Length/distance pair
      let length = s
      let dist = dsyms[i]
      let (lc, dc) = @huffman.enc_pair(length, dist)
      let li = lc & 31
      let lcode_sym = li + 257
      let code = lm[lcode_sym]
      let bits = lt_arr[lcode_sym]
      @bits.wbits16(out, p, code, bits)
      p = p + bits
      let leb = fleb[li]
      if leb > 0 {
        @bits.wbits(out, p, lc >> 5, leb)
        p = p + leb
      }
      let di = dc & 31
      let dcode = dm[di]
      let dbits = dt_arr[di]
      @bits.wbits16(out, p, dcode, dbits)
      p = p + dbits
      let deb = fdeb[di]
      if deb > 0 {
        @bits.wbits16(out, p, dc >> 5, deb)
        p = p + deb
      }
    }
  }
  p
}

// ============================================================
// write_cl_codes - Write RLE-encoded code lengths
// ============================================================

///|
/// Write RLE-encoded code length symbols using the code length Huffman table.
fn write_cl_codes(
  out : FixedArray[Byte],
  pos : Int,
  cl_syms : FixedArray[Int],
  clm : FixedArray[Int],
  cl_lens : FixedArray[Int],
) -> Int {
  let fclim = @huffman.fclim
  let mut p = pos
  for i = 0; i < cl_syms.length(); i = i + 1 {
    let entry = cl_syms[i]
    let sym = entry & 31
    let code = clm[sym]
    let bits = cl_lens[sym]
    @bits.wbits16(out, p, code, bits)
    p = p + bits
    let eb = fclim[sym]
    if eb > 0 {
      @bits.wbits(out, p, (entry >> 5) & ((1 << eb) - 1), eb)
      p = p + eb
    }
  }
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
// auto_mem - Automatic memory level selection
// ============================================================

///|
/// Select memory level based on input size if not explicitly set.
/// Larger inputs benefit from larger hash tables.
fn auto_mem(data_len : Int, user_mem : Int) -> Int {
  if user_mem > 0 {
    return user_mem
  }
  if data_len <= 256 {
    1
  } else if data_len <= 1024 {
    2
  } else if data_len <= 8192 {
    3
  } else {
    4
  }
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
  inflt(data, size_hint, dictionary=opts.dictionary)
}

// ============================================================
// deflate_sync - Synchronous compression
// ============================================================

///|
/// Synchronously compress data using DEFLATE.
///
/// Supports:
///   - Level 0: Store blocks (no compression)
///   - Level 1-9: LZ77 + dynamic/fixed Huffman coding
///
/// Parameters:
///   data - Uncompressed data
///   opts - Compression options (level, mem, dictionary)
///
/// Returns DEFLATE compressed data.
pub fn deflate_sync(
  data : FixedArray[Byte],
  opts? : @types.DeflateOptions = @types.DeflateOptions::default(),
) -> FixedArray[Byte] {
  let params = dopt(opts)
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
    // Level 1-9: LZ77 + Huffman compression
    let mem = auto_mem(dl, params[1])
    let hash_size = 1 << (mem + 8)
    let hsh : FixedArray[Int] = FixedArray::make(hash_size, 0)
    let prev : FixedArray[Int] = FixedArray::make(32768, 0)
    let nice = nice_len[level]
    let max_chain = chain_len[level]
    // Symbol buffers for current block (max block symbols = 131072)
    let cbuf = 131072
    let syms : FixedArray[Int] = FixedArray::make(cbuf, 0)
    let dsyms : FixedArray[Int] = FixedArray::make(cbuf, 0)
    // Worst case output: ~9/8 * dl + generous overhead
    let out_size = dl + (dl >> 3) + 16 + 128
    let mut out = FixedArray::make(out_size, b'\x00')
    let mut bit_pos = 0
    let mut i = 0
    if dl == 0 {
      // Write empty final block
      let empty_lit : FixedArray[Int] = FixedArray::make(286, 0)
      empty_lit[256] = 1
      let empty_dist : FixedArray[Int] = FixedArray::make(30, 0)
      bit_pos = wblk(out, bit_pos, syms, dsyms, 0, empty_lit, empty_dist, true)
    } else {
      while i < dl {
        // Start a new block
        let mut nsym = 0
        let lit_freq : FixedArray[Int] = FixedArray::make(286, 0)
        let dist_freq : FixedArray[Int] = FixedArray::make(30, 0)
        let block_start = i
        // Fill symbol buffer
        while i < dl && nsym < cbuf - 2 {
          if i + 2 < dl {
            let (mlen, mdist) = find_match(
              data, i, dl, hsh, prev, hash_size, max_chain, nice,
            )
            if mlen >= 3 {
              // Emit length/distance pair
              syms[nsym] = mlen
              dsyms[nsym] = mdist
              let (lc, dc) = @huffman.enc_pair(mlen, mdist)
              lit_freq[(lc & 31) + 257] = lit_freq[(lc & 31) + 257] + 1
              dist_freq[dc & 31] = dist_freq[dc & 31] + 1
              // Update hash for skipped positions (1-based)
              for j = 1; j < mlen; j = j + 1 {
                if i + j + 2 < dl {
                  let h = (
                      (data[i + j].to_int() << 16) |
                      (data[i + j + 1].to_int() << 8) |
                      data[i + j + 2].to_int()
                    ) %
                    hash_size
                  prev[(i + j) & 32767] = hsh[h]
                  hsh[h] = i + j + 1
                }
              }
              i = i + mlen
              nsym = nsym + 1
              continue
            }
          }
          // Emit literal
          let b = data[i].to_int()
          syms[nsym] = b
          dsyms[nsym] = 0
          lit_freq[b] = lit_freq[b] + 1
          // Update hash table for current position (1-based)
          if i + 2 < dl {
            let h = (
                (data[i].to_int() << 16) |
                (data[i + 1].to_int() << 8) |
                data[i + 2].to_int()
              ) %
              hash_size
            prev[i & 32767] = hsh[h]
            hsh[h] = i + 1
          }
          i = i + 1
          nsym = nsym + 1
        }
        let is_final = i >= dl
        // Ensure EOB symbol has non-zero frequency
        lit_freq[256] = lit_freq[256] + 1
        // Ensure at least one distance code is present
        let mut has_dist = false
        for d = 0; d < 30; d = d + 1 {
          if dist_freq[d] > 0 {
            has_dist = true
            break
          }
        }
        if not(has_dist) {
          dist_freq[0] = 1
        }
        // Ensure output buffer is large enough
        let needed = bit_pos / 8 + (nsym + 1) * 4 + 300
        if needed > out.length() {
          out = grow(out, needed + 32768)
        }
        bit_pos = wblk(
          out, bit_pos, syms, dsyms, nsym, lit_freq, dist_freq, is_final,
        )
        let _ = block_start
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
