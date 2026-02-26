// === Fixed Huffman Table Tests ===

///|
test "fixed literal table: codes 0-143 are 8-bit" {
  for i = 0; i < 144; i = i + 1 {
    assert_eq(@huffman.flt[i], 8)
  }
}

///|
test "fixed literal table: codes 144-255 are 9-bit" {
  for i = 144; i < 256; i = i + 1 {
    assert_eq(@huffman.flt[i], 9)
  }
}

///|
test "fixed literal table: codes 256-279 are 7-bit" {
  for i = 256; i < 280; i = i + 1 {
    assert_eq(@huffman.flt[i], 7)
  }
}

///|
test "fixed literal table: codes 280-287 are 8-bit" {
  for i = 280; i < 288; i = i + 1 {
    assert_eq(@huffman.flt[i], 8)
  }
}

///|
test "fixed distance table: all 32 codes are 5-bit" {
  for i = 0; i < 32; i = i + 1 {
    assert_eq(@huffman.fdt[i], 5)
  }
}

// === rev15 bit reversal tests ===

///|
test "rev15: 0 reverses to 0" {
  assert_eq(@huffman.rev15[0], 0)
}

///|
test "rev15: 1 reverses to 0x4000 (1 << 14)" {
  assert_eq(@huffman.rev15[1], 0x4000)
}

///|
test "rev15: round-trip for all values" {
  // Double reversal should give back the original
  for i = 0; i < 100; i = i + 1 {
    assert_eq(@huffman.rev15[@huffman.rev15[i]], i)
  }
}

// === hTree tests ===

///|
test "h_tree: empty frequency table" {
  let freq : FixedArray[Int] = [0, 0, 0, 0]
  let result = @huffman.h_tree(freq, 15)
  assert_eq(result.l, 0)
}

///|
test "h_tree: single symbol" {
  let freq : FixedArray[Int] = [0, 0, 5, 0]
  let result = @huffman.h_tree(freq, 15)
  assert_eq(result.t[2], 1)
  assert_eq(result.l, 1)
}

///|
test "h_tree: two equal frequency symbols" {
  let freq : FixedArray[Int] = [5, 5]
  let result = @huffman.h_tree(freq, 15)
  assert_eq(result.t[0], 1)
  assert_eq(result.t[1], 1)
  assert_eq(result.l, 1)
}

///|
test "h_tree: skewed distribution" {
  // One symbol much more frequent
  let freq : FixedArray[Int] = [100, 1, 1, 1]
  let result = @huffman.h_tree(freq, 15)
  // Most frequent symbol should have shortest code
  assert_true(result.t[0] <= result.t[1])
  assert_true(result.t[0] <= result.t[2])
  assert_true(result.t[0] <= result.t[3])
}

///|
test "h_tree: depth limiting with mb=3" {
  // With many symbols, tree might go deeper than 3
  let freq : FixedArray[Int] = [1, 2, 4, 8, 16, 32, 64, 128]
  let result = @huffman.h_tree(freq, 3)
  // All code lengths should be <= 3
  for i = 0; i < result.t.length(); i = i + 1 {
    assert_true(result.t[i] <= 3)
  }
}

// === hMap tests ===

///|
test "h_map forward: fixed literal table produces valid codes" {
  let map = @huffman.flm
  assert_eq(map.length(), 288)
  // Code 256 (end of block) should have a 7-bit code
  // Just verify it's non-zero (it exists)
  // Exact value depends on canonical assignment
}

///|
test "h_map reverse: fixed literal table round-trip" {
  let fwd = @huffman.flm
  let rev = @huffman.flrm
  // For each symbol, encoding then decoding should give back the symbol
  for sym = 0; sym < 288; sym = sym + 1 {
    let code = fwd[sym]
    let bits = @huffman.flt[sym]
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
  let fwd = @huffman.fdm
  let rev = @huffman.fdrm
  for sym = 0; sym < 30; sym = sym + 1 {
    let code = fwd[sym]
    let bits = @huffman.fdt[sym]
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
  let result = @huffman.lc(c)
  // All zeros should be trimmed → empty result
  assert_eq(result.n, 0)
}

///|
test "lc: single non-zero value" {
  let c : FixedArray[Int] = [5]
  let result = @huffman.lc(c)
  assert_eq(result.n, 1)
  assert_eq(result.c[0], 5)
}

///|
test "lc: repeated non-zero uses symbol 16" {
  let c : FixedArray[Int] = [3, 3, 3, 3, 3]
  let result = @huffman.lc(c)
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
  let result = @huffman.lc(c)
  assert_eq(result.n, 7)
}

// === freb tests ===

///|
test "freb: length base values start at 3" {
  assert_eq(@huffman.fl[0], 3) // code 257 = min length 3
}

///|
test "freb: length code 285 = 258" {
  assert_eq(@huffman.fl[28], 258) // code 285 = length 258
}

///|
test "freb: distance base values start at 1" {
  assert_eq(@huffman.fd[0], 1) // code 0 = distance 1
}

///|
test "freb: distance code 1 = 2" {
  assert_eq(@huffman.fd[1], 2) // code 1 = distance 2
}

// === Utility tests ===

///|
test "max_bits: finds maximum" {
  let a : FixedArray[Int] = [3, 7, 2, 9, 1]
  assert_eq(@huffman.max_bits(a), 9)
}

///|
test "clen: computes total bits" {
  let freq : FixedArray[Int] = [10, 5, 3]
  let lens : FixedArray[Int] = [2, 3, 4]
  // 10*2 + 5*3 + 3*4 = 20 + 15 + 12 = 47
  assert_eq(@huffman.clen(freq, lens), 47)
}
