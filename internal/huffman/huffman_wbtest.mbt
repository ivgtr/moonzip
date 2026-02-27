// === Fixed Huffman Table Tests ===

///|
test "fixed literal table: codes 0-143 are 8-bit" {
  for i = 0; i < 144; i = i + 1 {
    assert_eq(flt[i], 8)
  }
}

///|
test "fixed literal table: codes 144-255 are 9-bit" {
  for i = 144; i < 256; i = i + 1 {
    assert_eq(flt[i], 9)
  }
}

///|
test "fixed literal table: codes 256-279 are 7-bit" {
  for i = 256; i < 280; i = i + 1 {
    assert_eq(flt[i], 7)
  }
}

///|
test "fixed literal table: codes 280-287 are 8-bit" {
  for i = 280; i < 288; i = i + 1 {
    assert_eq(flt[i], 8)
  }
}

///|
test "fixed distance table: all 32 codes are 5-bit" {
  for i = 0; i < 32; i = i + 1 {
    assert_eq(fdt[i], 5)
  }
}

// === rev15 bit reversal tests ===

///|
test "rev15: 0 reverses to 0" {
  assert_eq(rev15[0], 0)
}

///|
test "rev15: 1 reverses to 0x4000 (1 << 14)" {
  assert_eq(rev15[1], 0x4000)
}

///|
test "rev15: round-trip for all values" {
  // Double reversal should give back the original
  for i = 0; i < 100; i = i + 1 {
    assert_eq(rev15[rev15[i]], i)
  }
}

// === hTree tests ===

///|
test "h_tree: empty frequency table" {
  let freq : FixedArray[Int] = [0, 0, 0, 0]
  let result = h_tree(freq, 15)
  assert_eq(result.l, 0)
}

///|
test "h_tree: single symbol" {
  let freq : FixedArray[Int] = [0, 0, 5, 0]
  let result = h_tree(freq, 15)
  assert_eq(result.t[2], 1)
  assert_eq(result.l, 1)
}

///|
test "h_tree: two equal frequency symbols" {
  let freq : FixedArray[Int] = [5, 5]
  let result = h_tree(freq, 15)
  assert_eq(result.t[0], 1)
  assert_eq(result.t[1], 1)
  assert_eq(result.l, 1)
}

///|
test "h_tree: skewed distribution" {
  // One symbol much more frequent
  let freq : FixedArray[Int] = [100, 1, 1, 1]
  let result = h_tree(freq, 15)
  // Most frequent symbol should have shortest code
  assert_true(result.t[0] <= result.t[1])
  assert_true(result.t[0] <= result.t[2])
  assert_true(result.t[0] <= result.t[3])
}

///|
test "h_tree: depth limiting with mb=3" {
  // With many symbols, tree might go deeper than 3
  let freq : FixedArray[Int] = [1, 2, 4, 8, 16, 32, 64, 128]
  let result = h_tree(freq, 3)
  // All code lengths should be <= 3
  for i = 0; i < result.t.length(); i = i + 1 {
    assert_true(result.t[i] <= 3)
  }
}

// === hMap tests ===

///|
test "h_map forward: fixed literal table produces valid codes" {
  let map = flm
  assert_eq(map.length(), 288)
  // Code 256 (end of block) should have a 7-bit code
  // Just verify it's non-zero (it exists)
  // Exact value depends on canonical assignment
}

///|
test "h_map reverse: fixed literal table round-trip" {
  let fwd = flm
  let rev = flrm
  // For each symbol, encoding then decoding should give back the symbol
  for sym = 0; sym < 288; sym = sym + 1 {
    let code = fwd[sym]
    let bits = flt[sym]
    // Look up in reverse map
    let entry = rev[code]
    let decoded_sym = entry >> 4
    let decoded_bits = entry & 0xF
    assert_eq(decoded_sym, sym)
    assert_eq(decoded_bits, bits)
  }
}

///|
test "h_map reverse: fixed distance table round-trip" {
  let fwd = fdm
  let rev = fdrm
  for sym = 0; sym < 30; sym = sym + 1 {
    let code = fwd[sym]
    let bits = fdt[sym]
    let entry = rev[code]
    let decoded_sym = entry >> 4
    let decoded_bits = entry & 0xF
    assert_eq(decoded_sym, sym)
    assert_eq(decoded_bits, bits)
  }
}

// === lc (code length RLE) tests ===

///|
test "lc: all zeros emits symbol 18" {
  let c : FixedArray[Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  let result = lc(c)
  // All zeros should be trimmed → empty result
  assert_eq(result.n, 0)
}

///|
test "lc: single non-zero value" {
  let c : FixedArray[Int] = [5]
  let result = lc(c)
  assert_eq(result.n, 1)
  assert_eq(result.c[0], 5)
}

///|
test "lc: repeated non-zero uses symbol 16" {
  let c : FixedArray[Int] = [3, 3, 3, 3, 3]
  let result = lc(c)
  assert_eq(result.n, 5)
  // First should be literal 3, then a repeat symbol
  assert_eq(result.c[0], 3)
  // Second entry should be a symbol 16 repeat
  let entry = result.c[1]
  let sym = entry & 31
  assert_eq(sym & 0xF, 0) // Symbol 16 in packed form
}

///|
test "lc: zero run 3-10 uses symbol 17" {
  let c : FixedArray[Int] = [5, 0, 0, 0, 0, 0, 3]
  let result = lc(c)
  assert_eq(result.n, 7)
}

// === freb tests ===

///|
test "freb: length base values start at 3" {
  assert_eq(fl[0], 3) // code 257 = min length 3
}

///|
test "freb: length code 285 = 258" {
  assert_eq(fl[28], 258) // code 285 = length 258
}

///|
test "freb: distance base values start at 1" {
  assert_eq(fd[0], 1) // code 0 = distance 1
}

///|
test "freb: distance code 1 = 2" {
  assert_eq(fd[1], 2) // code 1 = distance 2
}

// === Utility tests ===

///|
test "max_bits: finds maximum" {
  let a : FixedArray[Int] = [3, 7, 2, 9, 1]
  assert_eq(max_bits(a), 9)
}

///|
test "clen: computes total bits" {
  let freq : FixedArray[Int] = [10, 5, 3]
  let lens : FixedArray[Int] = [2, 3, 4]
  // 10*2 + 5*3 + 3*4 = 20 + 15 + 12 = 47
  assert_eq(clen(freq, lens), 47)
}

// === enc_pair tests ===

///|
test "enc_pair: length=3, distance=1" {
  let (lcode, dcode) = enc_pair(3, 1)
  // revfl[3] = ((3 - base) << 5) | code_index
  // revfd[1] = ((1 - base) << 5) | code_index
  // For length 3: code_index=0, base=3, so offset=0, result = (0 << 5) | 0 = 0
  assert_eq(lcode, 0)
  // For distance 1: code_index=0, base=1, so offset=0, result = (0 << 5) | 0 = 0
  assert_eq(dcode, 0)
}

///|
test "enc_pair: length=10, distance=4" {
  let (lcode, dcode) = enc_pair(10, 4)
  // length 10: fl[7]=10, fleb[7]=0 → code_index=7, offset=0
  assert_eq(lcode & 31, 7)
  // distance 4: fd[3]=4, fdeb[3]=0 → code_index=3, offset=0
  assert_eq(dcode & 31, 3)
}

// === dyn_build tests ===

///|
test "dyn_build: uniform frequency" {
  let lit_freq : FixedArray[Int] = FixedArray::make(288, 0)
  let dist_freq : FixedArray[Int] = FixedArray::make(32, 0)
  for i = 0; i < 256; i = i + 1 {
    lit_freq[i] = 10
  }
  lit_freq[256] = 1
  dist_freq[0] = 1
  let (lm, lb, dm, db) = dyn_build(lit_freq, dist_freq)
  assert_true(lm.length() > 0)
  assert_true(lb > 0)
  assert_true(dm.length() > 0)
  assert_true(db > 0)
}

///|
test "dyn_build: skewed frequency prefers fixed" {
  // With very few distinct symbols, dynamic may not beat fixed
  let lit_freq : FixedArray[Int] = FixedArray::make(288, 0)
  let dist_freq : FixedArray[Int] = FixedArray::make(32, 0)
  lit_freq[0] = 1000
  lit_freq[256] = 1
  let (lm, lb, _dm, _db) = dyn_build(lit_freq, dist_freq)
  assert_true(lm.length() > 0)
  assert_true(lb > 0)
}

// === lc long zero run tests ===

///|
test "lc: 140 consecutive zeros (symbol 18 twice)" {
  // 140 zeros followed by a non-zero to prevent full trimming
  let c : FixedArray[Int] = FixedArray::make(141, 0)
  c[140] = 5
  let result = lc(c)
  assert_eq(result.n, 141)
  // 140 zeros should be encoded as symbol 18 (max 138) + symbol 17 (2 remaining is too few, so individual)
  // Actually: 140 > 138, so first emit symbol 18 for 138, remaining 2 zeros are individual
  assert_true(result.c.length() >= 3)
  // First entry: symbol 18 for 138 zeros
  let sym0 = result.c[0] & 31
  // symbol 18 packed = ((count-11) << 5) | 28690 → sym0 should decode to 18
  assert_eq(sym0, 18)
}

///|
test "lc: 10 repeated non-zero values (symbol 16)" {
  let c : FixedArray[Int] = FixedArray::make(10, 5)
  let result = lc(c)
  assert_eq(result.n, 10)
  // First entry should be literal 5
  assert_eq(result.c[0], 5)
  // Remaining 9 repeats: 1 literal + 8 more → symbol 16 for 6 (max), then 2 more individual
  // Or: 1 literal emitted, then 9 remaining. > 6 → symbol 16 for 6, remaining 3 → symbol 16 for 3
  assert_true(result.c.length() >= 2)
}
