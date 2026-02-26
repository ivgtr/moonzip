# fflate アーキテクチャ分析

## 概要

- **リポジトリ**: https://github.com/101arrowz/fflate
- **バージョン**: 0.8.2
- **ソース**: `src/index.ts` 単一ファイル（3,778行）
- **依存関係**: ゼロ
- **サイズ**: 8KB (minified)、inflate-only で 3KB

---

## 対応フォーマット

| フォーマット | RFC/仕様 | 圧縮 | 解凍 | ストリーミング |
|---|---|---|---|---|
| DEFLATE | RFC 1951 | Yes | Yes | Yes |
| GZIP | RFC 1952 | Yes | Yes | Yes |
| Zlib | RFC 1950 | Yes | Yes | Yes |
| ZIP | PKZIP APPNOTE | Yes | Yes | Yes |

---

## 圧縮レベル

| レベル | nice閾値 | チェーン長 | 説明 |
|--------|----------|-----------|------|
| 0 | - | - | Store（無圧縮） |
| 1 | 8 | 4 | 最速 |
| 2 | 16 | 8 | |
| 3 | 16 | 16 | |
| 4 | 16 | 32 | |
| 5 | 32 | 32 | |
| 6 | 128 | 128 | **デフォルト** |
| 7 | 128 | 256 | |
| 8 | 256 | 512 | |
| 9 | 258 | 32768 | 最高圧縮 |

内部エンコーディング (`deo` テーブル): `nice << 13 | chain`

メモリレベル (`mem`): 0-12、ハッシュテーブルサイズ制御（2^(mem+2) バイト）

---

## コアアルゴリズム

### CRC32
- 多項式: 0xEDB88320（反転形式）
- 256エントリのルックアップテーブル
- 初期値: -1 (0xFFFFFFFF)、最終値: ビット反転 (`~c`)

### Adler-32
- デュアルアキュムレータ: `a` (バイト合計) + `b` (合計の合計)
- 2,655バイト毎に mod 65521 リダクション
- 結果: `(b << 16) | a`

### ハフマン符号

**ツリー構築 (`hTree`)**:
1. 頻度テーブルからノード作成
2. 頻度順ソート
3. デュアルポインタアルゴリズムで結合
4. 最大15ビット制限でdebトラッキング再配分

**コードマップ生成 (`hMap`)**:
- ビット長頻度表 → 最小コード計算
- 正方向/逆方向マップ生成
- 16ビットビット反転テーブル使用

**固定ハフマンテーブル**:
```
リテラル/長さ:
  0-143:   8ビット
  144-255: 9ビット
  256-279: 7ビット
  280-287: 8ビット
距離: 全て5ビット
```

### LZ77
- 3バイトローリングハッシュ: `(dat[i] ^ (dat[i+1] << bs1) ^ (dat[i+2] << bs2)) & mask`
- `head`/`prev` 配列によるハッシュチェーン
- 最大マッチ長: 258バイト、最大距離: 32,768バイト

### DEFLATE ブロック
- **Type 0**: 無圧縮（バイト境界アライン + 4バイトヘッダ + 生データ、最大65,535バイト）
- **Type 1**: 固定ハフマン
- **Type 2**: 動的ハフマン（コード長自体もハフマン符号化 + RLE）
- ブロック分割: 24,576シンボルまたは7,000文字マッチ

---

## GZIP フォーマット

### ヘッダ（10バイト固定 + オプション）
```
ID1:     0x1f (1バイト)
ID2:     0x8b (1バイト)
CM:      8 = deflate (1バイト)
FLG:     ビットフラグ (1バイト)
  FTEXT:    bit 0
  FHCRC:    bit 1
  FEXTRA:   bit 2
  FNAME:    bit 3
  FCOMMENT: bit 4
MTIME:   Unix timestamp (4バイト)
XFL:     圧縮レベル (1バイト) - level<=2で4, level>=7で2
OS:      OS識別子 (1バイト)
```

### フッタ（8バイト）
```
CRC32:   非圧縮データのCRC32 (4バイト)
ISIZE:   非圧縮データサイズ mod 2^32 (4バイト)
```

---

## Zlib フォーマット

### ヘッダ（2バイト + オプション4バイト）
```
CMF:     (1バイト)
  CM:      bits 0-3 = 8 (deflate)
  CINFO:   bits 4-7 = log2(window_size)-8
FLG:     (1バイト)
  FCHECK:  bits 0-4 (CMF*256+FLG が 31で割り切れるように)
  FDICT:   bit 5
  FLEVEL:  bits 6-7
[DICTID]: Adler-32 of dictionary (FDICT=1の場合、4バイト)
```

### フッタ（4バイト）
```
Adler-32: 非圧縮データのAdler-32 (4バイト、ビッグエンディアン)
```

---

## ZIP フォーマット

### Local File Header（30バイト + 可変）
```
Offset  Size  Field
0       4     Signature: 0x04034B50
4       2     Version needed: 20
6       2     Flags (bit 3=Data Descriptor, bit 11=UTF-8)
8       2     Compression: 0=Store, 8=Deflate
10      2     ModTime (DOS format)
12      2     ModDate (DOS format)
14      4     CRC32
18      4     Compressed size
22      4     Uncompressed size
26      2     Filename length
28      2     Extra field length
30      var   Filename
30+n    var   Extra field
```

### Data Descriptor（16バイト、ストリーミング時）
```
0       4     Signature: 0x08074B50
4       4     CRC32
8       4     Compressed size
12      4     Uncompressed size
```

### Central Directory Entry（46バイト + 可変）
Local File Header と同様の情報 + コメント + オフセット

### End of Central Directory（22バイト）
```
0       4     Signature: 0x06054B50
4       2     Disk number
6       2     CD start disk
8       2     Entries on this disk
10      2     Total entries
12      4     CD size
16      4     CD offset
20      2     Comment length
```

### MS-DOS 日時変換
```
日付: (year-1980) << 9 | month << 5 | day
時刻: hour << 11 | minute << 5 | seconds/2
```

### ZIP64
- 読み取りのみ対応（End of Central Directory Locator、Zip64 Extended Information）
- 書き込みは ZIP32 のみ

---

## エラーコード

| コード | 名前 | 説明 |
|--------|------|------|
| 0 | UnexpectedEOF | データが途中で切れている |
| 1 | InvalidBlockType | 不正なDEFLATEブロックタイプ |
| 2 | InvalidLengthLiteral | 不正な長さリテラル |
| 3 | InvalidDistance | 不正な距離コード |
| 4 | StreamFinished | 終了済みストリームへの入力 |
| 5 | NoStreamHandler | ondataハンドラ未設定 |
| 6 | InvalidHeader | 不正なヘッダ |
| 7 | NoCallback | コールバック未設定 |
| 8 | InvalidUTF8 | 不正なUTF-8シーケンス |
| 9 | ExtraFieldTooLong | 拡張フィールドが長すぎる |
| 10 | InvalidDate | 不正な日付 |
| 11 | FilenameTooLong | ファイル名が長すぎる |
| 12 | StreamFinishing | 終了処理中のストリーム |
| 13 | InvalidZipData | 不正なZIPデータ |
| 14 | UnknownCompressionMethod | 未知の圧縮方式 |

---

## 公開API一覧（同期 + ストリーミングのみ）

### 同期関数
```
deflateSync(data, opts?) → Uint8Array
inflateSync(data, opts?) → Uint8Array
gzipSync(data, opts?) → Uint8Array
gunzipSync(data, opts?) → Uint8Array
zlibSync(data, opts?) → Uint8Array
unzlibSync(data, opts?) → Uint8Array
decompressSync(data, opts?) → Uint8Array
compressSync(data, opts?) → Uint8Array    // gzipSync のエイリアス
zipSync(data, opts?) → Uint8Array
unzipSync(data, opts?) → Unzipped
strToU8(str, latin1?) → Uint8Array
strFromU8(dat, latin1?) → string
```

### ストリーミングクラス
```
Deflate        - DEFLATE圧縮ストリーム
Inflate        - DEFLATE解凍ストリーム
Gzip           - GZIP圧縮ストリーム
Gunzip         - GZIP解凍ストリーム
Zlib           - Zlib圧縮ストリーム
Unzlib         - Zlib解凍ストリーム
Compress       - Gzip のエイリアス
Decompress     - 自動検出解凍ストリーム
Zip            - ZIPアーカイブ作成ストリーム
Unzip          - ZIPアーカイブ解凍ストリーム
ZipPassThrough - ZIP無圧縮ファイル入力
ZipDeflate     - ZIP DEFLATE圧縮ファイル入力
EncodeUTF8     - 文字列→UTF-8バイト列変換ストリーム
DecodeUTF8     - UTF-8バイト列→文字列変換ストリーム
```

### 主要オプション型
```
DeflateOptions { level?: 0-9, mem?: 0-12, dictionary?: Uint8Array }
InflateOptions { size?: number, dictionary?: Uint8Array }
GzipOptions    extends DeflateOptions { mtime?: Date|string|number, filename?: string, ... }
ZlibOptions    extends DeflateOptions
ZipOptions     extends DeflateOptions, ZipAttributes
```

---

## 内部ヘルパー関数一覧

| 関数 | 用途 |
|------|------|
| `freb()` | 追加ビットテーブルからベース値/逆インデックス生成 |
| `hMap()` | ハフマンコードルックアップテーブル生成 |
| `hTree()` | 頻度テーブルからハフマンツリー構築 |
| `ln()` | 再帰的ビット長割り当て |
| `lc()` | コード長RLE符号化 |
| `clen()` | 出力ビット数計算 |
| `bits()` / `bits16()` | ビット読み取り |
| `wbits()` / `wbits16()` | ビット書き込み |
| `shft()` | バイト境界アライメント |
| `slc()` | TypedArray スライス |
| `inflt()` | DEFLATE解凍エンジン |
| `dflt()` | DEFLATE圧縮エンジン |
| `dopt()` | deflateオプション前処理 |
| `wfblk()` | 無圧縮ブロック書き込み |
| `wblk()` | ハフマンブロック書き込み |
| `crc()` | CRC32 |
| `adler()` | Adler-32 |
| `gzh()` | GZIPヘッダ書き込み |
| `gzs()` / `gzl()` | GZIPヘッダ/フッタ解析 |
| `zlh()` / `zls()` | Zlibヘッダ作成/検証 |
| `wzh()` | ZIPヘッダ書き込み |
| `wzf()` | ZIP End of CD書き込み |
| `zh()` | Central Directory解析 |
| `slzh()` | Local File Header解析 |
| `fltn()` | Zippableフラット化 |
| `exfl()` | 拡張フィールドサイズ計算 |
| `dbf()` | 圧縮レベル→DEFLATEフラグ変換 |
| `wbytes()` | リトルエンディアン書き込み |
| `b2()` / `b4()` / `b8()` | リトルエンディアン読み取り |
| `z64e()` | ZIP64拡張情報解析 |
| `mrg()` | オブジェクトマージ |
