// ============================================================
// DEFLATE Constants
// ============================================================

///|
/// Length extra bits for DEFLATE length codes 257-285.
/// Index 0 corresponds to code 257, index 28 corresponds to code 285.
pub let fleb : FixedArray[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5,
  5, 0, 0, 0, 0,
]

///|
/// Distance extra bits for DEFLATE distance codes 0-29.
pub let fdeb : FixedArray[Int] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
  12, 12, 13, 13, 0, 0,
]

///|
/// Code length alphabet reorder map used during dynamic Huffman header encoding.
/// Specifies the order in which code length code lengths appear in the header.
pub let clim : FixedArray[Int] = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
]

///|
/// Extra bits count for code length alphabet symbols 0-18.
/// Index 16: 2 extra bits (repeat previous 3-6)
/// Index 17: 3 extra bits (repeat zero 3-10)
/// Index 18: 7 extra bits (repeat zero 11-138)
let fclim : FixedArray[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 7,
]

// ============================================================
// 15-bit Reversal Table
// ============================================================

///|
/// Pre-computed 15-bit reversal table. rev15[i] contains the bit-reversal
/// of i interpreted as a 15-bit value. Used for converting Huffman codes
/// between MSB-first canonical form and DEFLATE's LSB-first format.
let rev15 : FixedArray[Int] = {
  let t : FixedArray[Int] = FixedArray::make(32768, 0)
  for i = 0; i < 32768; i = i + 1 {
    let mut x = i
    x = ((x & 0xAAAA) >> 1) | ((x & 0x5555) << 1)
    x = ((x & 0xCCCC) >> 2) | ((x & 0x3333) << 2)
    x = ((x & 0xF0F0) >> 4) | ((x & 0x0F0F) << 4)
    t[i] = (((x & 0xFF00) >> 8) | ((x & 0x00FF) << 8)) >> 1
  }
  t
}

// ============================================================
// Fixed Huffman Tables
// ============================================================

///|
/// Fixed literal/length code lengths for DEFLATE (RFC 1951 section 3.2.6).
///   Codes   0-143: 8-bit
///   Codes 144-255: 9-bit
///   Codes 256-279: 7-bit
///   Codes 280-287: 8-bit
pub let flt : FixedArray[Int] = {
  let t : FixedArray[Int] = FixedArray::make(288, 0)
  for i = 0; i < 144; i = i + 1 {
    t[i] = 8
  }
  for i = 144; i < 256; i = i + 1 {
    t[i] = 9
  }
  for i = 256; i < 280; i = i + 1 {
    t[i] = 7
  }
  for i = 280; i < 288; i = i + 1 {
    t[i] = 8
  }
  t
}

///|
/// Fixed distance code lengths for DEFLATE (RFC 1951 section 3.2.6).
/// All 32 distance codes use 5 bits.
let fdt : FixedArray[Int] = {
  let t : FixedArray[Int] = FixedArray::make(32, 0)
  for i = 0; i < 32; i = i + 1 {
    t[i] = 5
  }
  t
}

// ============================================================
// Extra Bits Base/Reverse Tables (freb)
// ============================================================

///|
/// Result of `freb`: base values and reverse lookup table.
pub(all) struct FrebResult {
  /// Base values for each code (length 31).
  b : FixedArray[Int]
  /// Reverse index: maps a literal value to ((value - base) << 5) | code.
  r : FixedArray[Int]
}

///|
/// Generate base value and reverse index tables from extra bits definitions.
/// This is used to build lookup tables for length codes (257-285) and
/// distance codes (0-29).
///
/// Parameters:
///   eb    - Extra bits array (e.g. fleb or fdeb)
///   start - Starting base value (2 for lengths, 0 for distances)
///
/// Returns a FrebResult containing:
///   b - base values for each code (31 entries)
///   r - reverse lookup mapping literal value -> (offset << 5) | code
fn freb(eb : FixedArray[Int], start : Int) -> FrebResult {
  let b : FixedArray[Int] = FixedArray::make(31, 0)
  let mut s = start
  for i = 0; i < 31; i = i + 1 {
    s = s + (1 << eb[i])
    b[i] = s
  }
  let r : FixedArray[Int] = FixedArray::make(b[30], 0)
  for i = 1; i < 30; i = i + 1 {
    for j = b[i]; j < b[i + 1]; j = j + 1 {
      r[j] = ((j - b[i]) << 5) | i
    }
  }
  { b, r }
}

// ============================================================
// Pre-computed Length/Distance Tables
// ============================================================

///|
/// Base values for length codes (codes 257-285).
/// fl[i] is the minimum match length for length code 257+i.
pub let fl : FixedArray[Int] = {
  let result = freb(fleb, 2)
  result.b[28] = 258
  result.b
}

///|
/// Reverse lookup for length values -> length code index.
/// For a match length L, revfl[L] = ((L - base) << 5) | code_index.
let revfl : FixedArray[Int] = {
  let result = freb(fleb, 2)
  result.b[28] = 258
  result.r[258] = 28
  result.r
}

///|
/// Base values for distance codes (codes 0-29).
/// fd[i] is the minimum distance for distance code i.
pub let fd : FixedArray[Int] = {
  let result = freb(fdeb, 0)
  result.b
}

///|
/// Reverse lookup for distance values -> distance code index.
/// For a distance D, revfd[D] = ((D - base) << 5) | code_index.
let revfd : FixedArray[Int] = {
  let result = freb(fdeb, 0)
  result.r
}

// ============================================================
// Huffman Code Map (hMap)
// ============================================================

///|
/// Direction for Huffman code map generation.
pub(all) enum HMapDirection {
  /// Forward mapping: symbol -> code (for encoding)
  Forward
  /// Reverse mapping: code -> symbol (for decoding)
  Reverse
}

///|
/// Generate Huffman code map from code length array.
///
/// Parameters:
///   cd  - Code length array: cd[symbol] = bit length for that symbol
///   mb  - Maximum bit length in the table
///   dir - Direction: Forward for encoding (symbol->code), Reverse for decoding (code->symbol)
///
/// Returns:
///   Forward mode: array of size cd.length(), where result[symbol] = Huffman code (bit-reversed)
///   Reverse mode: array of size 2^mb, where result[code] = (symbol << 4) | bit_length
pub fn h_map(
  cd : FixedArray[Int],
  mb : Int,
  dir : HMapDirection,
) -> FixedArray[Int] {
  let s = cd.length()
  // Count code lengths
  let l : FixedArray[Int] = FixedArray::make(mb, 0)
  for i = 0; i < s; i = i + 1 {
    if cd[i] != 0 {
      l[cd[i] - 1] = l[cd[i] - 1] + 1
    }
  }
  // Compute starting codes for each bit length
  let le : FixedArray[Int] = FixedArray::make(mb, 0)
  for i = 1; i < mb; i = i + 1 {
    le[i] = (le[i - 1] + l[i - 1]) << 1
  }
  match dir {
    Reverse => {
      let co : FixedArray[Int] = FixedArray::make(1 << mb, 0)
      let rvb = 15 - mb
      for i = 0; i < s; i = i + 1 {
        if cd[i] != 0 {
          let sv = (i << 4) | cd[i]
          let r = mb - cd[i]
          let mut v = le[cd[i] - 1] << r
          le[cd[i] - 1] = le[cd[i] - 1] + 1
          let m = v | ((1 << r) - 1)
          while v <= m {
            co[rev15[v] >> rvb] = sv
            v = v + 1
          }
        }
      }
      co
    }
    Forward => {
      let co : FixedArray[Int] = FixedArray::make(s, 0)
      for i = 0; i < s; i = i + 1 {
        if cd[i] != 0 {
          co[i] = rev15[le[cd[i] - 1]] >> (15 - cd[i])
          le[cd[i] - 1] = le[cd[i] - 1] + 1
        }
      }
      co
    }
  }
}

// ============================================================
// Pre-computed Fixed Huffman Maps
// ============================================================

///|
/// Fixed literal/length Huffman encoding map (symbol -> code).
pub let flm : FixedArray[Int] = h_map(flt, 9, Forward)

///|
/// Fixed literal/length Huffman decoding map (code -> symbol|length).
pub let flrm : FixedArray[Int] = h_map(flt, 9, Reverse)

///|
/// Fixed distance Huffman encoding map (symbol -> code).
let fdm : FixedArray[Int] = h_map(fdt, 5, Forward)

///|
/// Fixed distance Huffman decoding map (code -> symbol|length).
pub let fdrm : FixedArray[Int] = h_map(fdt, 5, Reverse)

// ============================================================
// Huffman Tree Construction (hTree)
// ============================================================

///|
/// Result of Huffman tree construction.
pub(all) struct HTreeResult {
  /// Code length table: result[symbol] = bit length for that symbol.
  t : FixedArray[Int]
  /// Maximum bit length in the tree.
  l : Int
}

///|
/// Construct a Huffman tree from a frequency table and return code lengths.
/// Uses the dual-pointer merge algorithm with depth limiting (max 15 bits).
///
/// Parameters:
///   d  - Frequency table: d[symbol] = frequency count
///   mb - Maximum allowed bit depth (typically 15 for DEFLATE)
///
/// Returns HTreeResult containing code length array and actual max bit length.
fn h_tree(d : FixedArray[Int], mb : Int) -> HTreeResult {
  // Collect non-zero frequency symbols
  let len = d.length()
  let mut count = 0
  for i = 0; i < len; i = i + 1 {
    if d[i] != 0 {
      count = count + 1
    }
  }
  // Edge case: empty tree
  if count == 0 {
    return { t: FixedArray::make(0, 0), l: 0 }
  }
  // Edge case: single symbol - assign length 1
  if count == 1 {
    let mut sym = 0
    for i = 0; i < len; i = i + 1 {
      if d[i] != 0 {
        sym = i
        break
      }
    }
    let v : FixedArray[Int] = FixedArray::make(sym + 1, 0)
    v[sym] = 1
    return { t: v, l: 1 }
  }
  let s = count
  // Build sorted leaf nodes (sorted by frequency, ascending)
  // Store in parallel arrays: leaf_sym[i], leaf_freq[i]
  let leaf_sym : FixedArray[Int] = FixedArray::make(s, 0)
  let leaf_freq : FixedArray[Int] = FixedArray::make(s, 0)
  let mut ni = 0
  for i = 0; i < len; i = i + 1 {
    if d[i] != 0 {
      leaf_sym[ni] = i
      leaf_freq[ni] = d[i]
      ni = ni + 1
    }
  }
  // Also save a copy for rebalancing (symbol + freq pairs)
  let t2_sym : FixedArray[Int] = FixedArray::make(s, 0)
  let t2_freq : FixedArray[Int] = FixedArray::make(s, 0)
  for i = 0; i < s; i = i + 1 {
    t2_sym[i] = leaf_sym[i]
    t2_freq[i] = leaf_freq[i]
  }
  // Sort leaves by frequency (insertion sort)
  for i = 1; i < s; i = i + 1 {
    let key_sym = leaf_sym[i]
    let key_freq = leaf_freq[i]
    let mut j = i - 1
    while j >= 0 && leaf_freq[j] > key_freq {
      leaf_sym[j + 1] = leaf_sym[j]
      leaf_freq[j + 1] = leaf_freq[j]
      j = j - 1
    }
    leaf_sym[j + 1] = key_sym
    leaf_freq[j + 1] = key_freq
  }
  // Build tree using dual-pointer merge (fflate algorithm)
  // Leaf nodes encoded as negative: -(index+1)
  // Internal nodes encoded as: index + s
  let int_freq : FixedArray[Int] = FixedArray::make(s, 0)
  let int_left : FixedArray[Int] = FixedArray::make(s, -1)
  let int_right : FixedArray[Int] = FixedArray::make(s, -1)
  // Temporary arrays for pick results: [0] = encoding, [1] = frequency
  let pick : FixedArray[Int] = FixedArray::make(2, 0)
  let mut i0 = 0 // pointer into leaf array
  let mut i1 = 0 // write pointer for internal nodes
  let mut i2 = 0 // read pointer for internal nodes
  // Perform s-1 merges
  for _merge = 0; _merge < s - 1; _merge = _merge + 1 {
    // Pick first lowest
    if i0 < s && (i2 >= i1 || leaf_freq[i0] <= int_freq[i2]) {
      pick[0] = -(i0 + 1)
      pick[1] = leaf_freq[i0]
      i0 = i0 + 1
    } else {
      pick[0] = i2 + s
      pick[1] = int_freq[i2]
      i2 = i2 + 1
    }
    let l_enc = pick[0]
    let l_f = pick[1]
    // Pick second lowest
    if i0 < s && (i2 >= i1 || leaf_freq[i0] <= int_freq[i2]) {
      pick[0] = -(i0 + 1)
      pick[1] = leaf_freq[i0]
      i0 = i0 + 1
    } else {
      pick[0] = i2 + s
      pick[1] = int_freq[i2]
      i2 = i2 + 1
    }
    let r_enc = pick[0]
    let r_f = pick[1]
    int_freq[i1] = l_f + r_f
    int_left[i1] = l_enc
    int_right[i1] = r_enc
    i1 = i1 + 1
  }
  // Traverse tree to assign code lengths
  let mut max_sym = 0
  for i = 0; i < s; i = i + 1 {
    if t2_sym[i] > max_sym {
      max_sym = t2_sym[i]
    }
  }
  let tr : FixedArray[Int] = FixedArray::make(max_sym + 1, 0)
  // Iterative traversal with stack
  let stack_enc : FixedArray[Int] = FixedArray::make(s * 4, 0)
  let stack_dep : FixedArray[Int] = FixedArray::make(s * 4, 0)
  let mut sp = 0
  // Root is internal node at index i1-1, encoded as (i1-1) + s
  stack_enc[0] = i1 - 1 + s
  stack_dep[0] = 0
  sp = 1
  let mut mbt = 0
  while sp > 0 {
    sp = sp - 1
    let enc = stack_enc[sp]
    let depth = stack_dep[sp]
    if enc < 0 {
      // Leaf: -(enc+1) is leaf index
      let leaf_idx = -(enc + 1)
      tr[leaf_sym[leaf_idx]] = depth
      if depth > mbt {
        mbt = depth
      }
    } else {
      // Internal node: enc - s is the internal node index
      let int_idx = enc - s
      // Push right
      stack_enc[sp] = int_right[int_idx]
      stack_dep[sp] = depth + 1
      sp = sp + 1
      // Push left
      stack_enc[sp] = int_left[int_idx]
      stack_dep[sp] = depth + 1
      sp = sp + 1
    }
  }
  // Depth limiting: if mbt > mb, rebalance
  if mbt > mb {
    let lft = mbt - mb
    let cst = 1 << lft
    let mut dt = 0
    // Sort t2 by descending code length, then ascending frequency
    for i = 1; i < s; i = i + 1 {
      let key_sym = t2_sym[i]
      let key_freq = t2_freq[i]
      let key_len = tr[key_sym]
      let mut j = i - 1
      while j >= 0 {
        let j_len = tr[t2_sym[j]]
        if j_len < key_len || (j_len == key_len && t2_freq[j] > key_freq) {
          t2_sym[j + 1] = t2_sym[j]
          t2_freq[j + 1] = t2_freq[j]
          j = j - 1
        } else {
          break
        }
      }
      t2_sym[j + 1] = key_sym
      t2_freq[j + 1] = key_freq
    }
    // Clamp codes that exceed mb
    let mut i = 0
    while i < s {
      let sym = t2_sym[i]
      if tr[sym] > mb {
        dt = dt + cst - (1 << (mbt - tr[sym]))
        tr[sym] = mb
      } else {
        break
      }
      i = i + 1
    }
    dt = dt >> lft
    // Distribute debt by incrementing shorter codes
    while dt > 0 && i < s {
      let sym = t2_sym[i]
      if tr[sym] < mb {
        dt = dt - (1 << (mb - tr[sym] - 1))
        tr[sym] = tr[sym] + 1
      } else {
        i = i + 1
      }
    }
    // If dt went negative, decrement some codes at max length
    let mut j = i - 1
    while j >= 0 && dt < 0 {
      let sym = t2_sym[j]
      if tr[sym] == mb {
        tr[sym] = tr[sym] - 1
        dt = dt + 1
      }
      j = j - 1
    }
    mbt = mb
  }
  { t: tr, l: mbt }
}

// ============================================================
// Code Length RLE Encoding (lc)
// ============================================================

///|
/// Result of code length RLE encoding.
pub(all) struct LcResult {
  /// Encoded code lengths using DEFLATE's code length alphabet.
  /// Each entry is either a raw code length (0-15) or a packed repeat symbol:
  ///   Symbol 16: ((repeat_count - 3) << 5) | 16, with base value 8208
  ///   Symbol 17: ((repeat_count - 3) << 5) | 17, with base value 12305
  ///   Symbol 18: ((repeat_count - 11) << 5) | 18, with base value 28690
  /// The packed format is decoded as: symbol = entry & 31, extra = (entry >> 5) & mask
  c : FixedArray[Int]
  /// Number of significant code lengths (trimmed trailing zeros).
  n : Int
}

///|
/// Encode code lengths using DEFLATE's code length RLE alphabet.
/// Uses symbols 16 (repeat previous), 17 (repeat zero 3-10), 18 (repeat zero 11-138).
///
/// Parameters:
///   c - Code length array to encode
///
/// Returns LcResult with encoded output and trimmed length.
fn lc(c : FixedArray[Int]) -> LcResult {
  let mut s = c.length()
  // Trim trailing zeros
  while s > 0 && c[s - 1] == 0 {
    s = s - 1
  }
  if s == 0 {
    return { c: FixedArray::make(0, 0), n: 0 }
  }
  // Worst case output size
  let cl : FixedArray[Int] = FixedArray::make(s * 2, 0)
  let mut cli = 0
  let mut cln = c[0]
  let mut cls = 1
  for i = 1; i <= s; i = i + 1 {
    if i < s && c[i] == cln {
      cls = cls + 1
    } else {
      if cln == 0 && cls > 2 {
        // Zero runs: use symbol 18 (11-138) and symbol 17 (3-10)
        while cls > 138 {
          cl[cli] = 32754 // symbol 18, repeat 138: ((127) << 5) | 28690 masked
          cli = cli + 1
          cls = cls - 138
        }
        if cls > 2 {
          if cls > 10 {
            cl[cli] = ((cls - 11) << 5) | 28690 // symbol 18
          } else {
            cl[cli] = ((cls - 3) << 5) | 12305 // symbol 17
          }
          cli = cli + 1
          cls = 0
        }
      } else if cls > 3 {
        // Non-zero value repeated: emit one literal then symbol 16 repeats
        cl[cli] = cln
        cli = cli + 1
        cls = cls - 1
        while cls > 6 {
          cl[cli] = 8304 // symbol 16, repeat 6: ((3) << 5) | 8208
          cli = cli + 1
          cls = cls - 6
        }
        if cls > 2 {
          cl[cli] = ((cls - 3) << 5) | 8208 // symbol 16
          cli = cli + 1
          cls = 0
        }
      }
      // Emit remaining individual values
      while cls > 0 {
        cl[cli] = cln
        cli = cli + 1
        cls = cls - 1
      }
      cls = 1
      cln = if i < s { c[i] } else { 0 }
    }
  }
  // Trim output
  let result : FixedArray[Int] = FixedArray::make(cli, 0)
  for i = 0; i < cli; i = i + 1 {
    result[i] = cl[i]
  }
  { c: result, n: s }
}

// ============================================================
// Utility Functions
// ============================================================

///|
/// Find the maximum value in a code length array.
pub fn max_bits(a : FixedArray[Int]) -> Int {
  let mut m = 0
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] > m {
      m = a[i]
    }
  }
  m
}

///|
/// Compute the total number of bits needed to encode data using given
/// frequency and code length tables.
///
/// Parameters:
///   cf - Frequency table: cf[symbol] = count
///   cl - Code length table: cl[symbol] = bit length
///
/// Returns the total number of bits.
fn clen(cf : FixedArray[Int], cl : FixedArray[Int]) -> Int {
  let mut l = 0
  let end = if cf.length() < cl.length() { cf.length() } else { cl.length() }
  for i = 0; i < end; i = i + 1 {
    l = l + cf[i] * cl[i]
  }
  l
}
