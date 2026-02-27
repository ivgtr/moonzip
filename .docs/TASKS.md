# moonzip 残タスク — fflate 完全互換ロードマップ

## 現状サマリー (v0.1.2)

実装済み:
- DEFLATE圧縮(LZ77 + 動的Huffman, level 0-9)・伸長
- GZIP圧縮・伸長 (RFC 1952, マルチメンバー対応)
- Zlib圧縮・伸長 (RFC 1950, 辞書 FDICT 対応)
- ZIP作成・解凍 (PKZIP, per-entry オプション, フィルタ, ZIP64)
- ストリーミングAPI (インクリメンタル圧縮/伸長, ondata/flush/onmember)
- ZIP ストリーミング (ZipPassThrough, ZipDeflate, Zip, Unzip)
- EncodeUTF8 / DecodeUTF8 ストリーミング
- CRC32・Adler-32 チェックサム
- FlateErrorCode 全15種
- オプション型定義 (DeflateOptions, InflateOptions, GzipOptions, ZlibOptions, ZipOptions, ZipEntryOptions, ZipAttributes)
- トップレベル re-export 全同期API + compress_sync, str_to_u8, str_from_u8
- 辞書圧縮/伸長 (DEFLATE, Zlib)
- テスト 422件

---

## ワークフロー規約（v1 より引き継ぎ）

### タスク進行ルール

1. **タスク単位でコミットする**
   - 各タスク完了時に1コミットを作成する
   - コミットメッセージ形式: `<phase>: <タスクID> <簡潔な説明>`
   - 例: `phaseA: A-1 implement LZ77 matching engine`
   - 例: `phaseC: C-T1 add decompression options tests`

2. **テスト→実装→検証の反復サイクル**
   - **テストタスク（`*-T*`）完了時**: テストコードを記述し `moon check` が通ることを確認してコミット（テストは実装前なので FAIL で良い。ただしコンパイルは通す — スタブ/未実装マーカーを使用）
   - **実装タスク完了時**: `moon test` を実行し、該当テストが全て PASS することを確認してコミット
   - テストが FAIL した場合: テストコードではなく実装を修正する（テスト要件が正しい前提）。テスト自体にバグがある場合のみテストを修正し、修正理由をコミットメッセージに明記する

3. **フェーズ完了時のゲート**
   - 各フェーズの全タスク完了後に `moon test` で全テスト PASS を確認
   - `moon fmt` でコード整形
   - `moon info` でインターフェース更新、`.mbti` の差分を確認
   - ゲート通過後に次のフェーズに進む

### テスト実行コマンド

```sh
moon check              # コンパイルチェック（テスト記述後に使用）
moon test               # 全テスト実行（実装後に使用）
moon test --update      # スナップショット更新（必要時のみ）
moon fmt                # コード整形
moon info               # インターフェース更新
moon coverage analyze   # カバレッジ確認
```

### コミット粒度の目安

| タスク種別 | コミットタイミング | 前提条件 |
|-----------|------------------|---------|
| テストタスク (`*-T*`) | テストコード記述完了時 | `moon check` PASS（コンパイル通過） |
| 実装タスク | 対応テスト全 PASS 時 | `moon test` PASS |
| 統合テスト (Phase G) | テスト追加＋全 PASS 時 | `moon test` PASS |

---

## 依存関係グラフ

```
Phase A (LZ77+動的Huffman) ──┬── Phase B (Dictionary) ← Phase A に依存
                             │
Phase C (解凍オプション)      │   ← 独立（並行実行可能）
                             │
Phase D (ZIP拡張)            │   ← 独立（並行実行可能）
                             │
Phase E (ストリーミング) ─────┘   ← Phase A に依存（インクリメンタル圧縮）
    │
Phase F (ユーティリティ)          ← F-1/F-2 は独立、F-3 は Phase E に依存
    │
Phase G (互換性検証) ─────────── ← 全実装フェーズに依存
    │
Phase H (旧タスク) ──────────── ← H-1 は独立、H-2〜H-4 は任意タイミング
```

### 並行実行可能なフェーズ

- **Phase A 着手と同時に開始可能**: Phase C, Phase D, Phase F (F-1/F-2), Phase H (H-1〜H-4)
- **Phase A 完了後に開始**: Phase B, Phase E
- **全実装完了後**: Phase G

---

## ブロッカー分析

| フェーズ | ブロッカー | リスク | 備考 |
|---------|-----------|-------|------|
| **A** | なし | **高** | 最大の実装ギャップ。基盤コード（h_tree, dyn_build, enc_pair, revfl/revfd）はスタブとして存在 |
| **B** | Phase A-1 (LZ77) | 中 | LZ77のスライディングウィンドウがないと辞書初期化が無意味 |
| **C** | なし | 低 | シグネチャ変更 + opts パス through のみ |
| **D** | なし (D-1〜D-5すべて独立) | 中 | D-4 (ZIP64) のみ実装量多め |
| **E** | Phase A (インクリメンタル圧縮) | **高** | inflt() の状態中断/再開が未設計。アーキテクチャ変更が必要 |
| **F** | F-3 のみ Phase E に依存 | 低 | F-1/F-2 は即時着手可能 |
| **G** | 全実装フェーズ + fflateフィクスチャ | 中 | 外部ツールでのテストデータ事前生成が必要 |
| **H** | なし | 低 | すべて独立して着手可能 |

---

## MoonBit 固有の考慮事項（v1 より引き継ぎ・更新済み）

| 課題 | 対策 | 状態 | 影響フェーズ |
|------|------|------|------------|
| `Uint8Array` がない | `FixedArray[Byte]` を全公開APIで使用 | ✅ 解決済み | - |
| JS のコールバック型がない | trait / メソッド呼び出しパターンで設計 | ⚠️ Phase E で対応 | E |
| `Date` 型の互換性 | MS-DOS 日時は整数演算で実現 | ✅ 解決済み | - |
| ビット演算の符号 | `UInt` を使用 | ✅ 解決済み | - |
| 動的バッファ拡張 | 手動 `FixedArray` 再確保 | ✅ 解決済み | - |
| 大規模テストデータの埋め込み | テスト内でデータ生成関数を使用 | ⚠️ Phase G で対応 | G |
| クロスライブラリテスト | fflate で事前生成したバイナリフィクスチャを使用 | ⚠️ Phase G で対応 | G |

---

## リスクと対策（v1 より引き継ぎ・更新済み）

| リスク | 影響度 | 対策 |
|--------|--------|------|
| LZ77 の実装複雑性 | 高 | ハッシュチェーンのコア部分を先に小さく実装し、level=1 でラウンドトリップ確認後に最適化 |
| fflate の圧縮出力とバイト単位で一致しない | 低 | 完全一致は不要。ラウンドトリップ一致 + 圧縮率 ±10% を基準 |
| ストリーミング API の設計が MoonBit に合わない | 中 | Phase E の前に API 設計のプロトタイプを作成。必要なら fflate と異なるインターフェースを採用（動作互換は維持） |
| ZIP64 のテストデータ生成が困難 | 中 | 4GB超ファイルは不要。ZIP64 ヘッダのパース部分のみをバイナリフィクスチャでテスト |
| inflt() の状態分割が困難 | 高 | Phase E-2 で状態マシン設計が必要。現在の一括処理型を維持したまま段階的に移行 |

---

## 対象外（v1 より引き継ぎ）

以下は JavaScript ランタイム固有の機能のため、moonzip では実装しない:

- **非同期API**: `deflate`, `inflate`, `gzip`, `gunzip`, `zlib`, `unzlib`, `decompress`, `zip`, `unzip`（コールバックベース）
- **非同期ストリーミング**: `AsyncDeflate`, `AsyncInflate`, `AsyncGzip`, `AsyncGunzip`, `AsyncZlib`, `AsyncUnzlib`, `AsyncDecompress`, `AsyncZipDeflate`, `AsyncUnzipInflate`
- **Web Worker / worker_threads**: バックグラウンドスレッド処理
- **`ondrain` / `queuedSize`**: 非同期バッファリング制御
- **`terminate()`**: Worker 終了

---

## Phase A: 圧縮品質 — LZ77 + 動的Huffman

最大のギャップ。現在 deflate_sync(level>0) は固定Huffmanリテラルのみで後方参照なし。

- [x] A-1: LZ77 マッチングエンジン実装
  - ハッシュチェーンベース（fflate 準拠）
  - mem パラメータでハッシュテーブルサイズ制御 (1 << (mem+8))
  - level別の nice閾値 (8~258) / chain長 (4~32768) テーブル
- [x] A-2: 動的Huffmanブロック出力
  - dyn_build で動的テーブルを構築（既存）→ wblk で書き込み
  - 固定 vs 動的 vs Store の最適ブロック選択
- [x] A-3: ブロック分割戦略
  - 入力サイズに基づくブロック境界の決定
  - fflate の cbuf (131072バイト) 準拠
- [x] A-4: 自動メモリレベル選択
  - 入力サイズ → mem の自動決定ロジック (Math.min(mem, Math.ceil(Math.log(data.length)/2)))
- [x] A-T1: LZ77 ユニットテスト
  - 既知パターンのマッチ検出、距離・長さの正確性
- [x] A-T2: 圧縮率テスト
  - level 1~9 で圧縮率が向上すること
  - fflate と同等の圧縮率であること（許容範囲 ±10%）
- [x] A-T3: ラウンドトリップテスト（全レベル）
  - 各 level でデータが正しく復元されること

## Phase B: Dictionary サポート

- [x] B-1: deflate 辞書圧縮
  - DeflateOptions.dictionary を dflt エンジンに渡す
  - ウィンドウ初期化に辞書を使用
- [x] B-2: inflate 辞書伸長
  - InflateOptions.dictionary を inflt に渡す
  - 辞書なし圧縮データへの辞書適用時のエラー処理
- [x] B-3: zlib 辞書 (FDICT フラグ)
  - zlibSync: FDICT=1 のヘッダ出力 + DICTID (Adler-32)
  - unzlibSync: FDICT=1 時の辞書ID検証と辞書適用
- [x] B-T1: 辞書ラウンドトリップテスト
- [x] B-T2: 辞書なしデータに辞書適用エラーテスト
- [x] B-T3: zlib FDICT フラグ生成・検証テスト

## Phase C: 解凍オプション拡張

gunzip_sync / unzlib_sync / decompress_sync が opts を受け付けない。

- [x] C-1: gunzip_sync に InflateOptions を追加
  - `gunzip_sync(data, opts?: InflateOptions)` シグネチャ
  - size ヒントによる出力バッファ事前割り当て
- [x] C-2: unzlib_sync に InflateOptions を追加
  - `unzlib_sync(data, opts?: InflateOptions)` シグネチャ
- [x] C-3: decompress_sync に InflateOptions を追加
  - `decompress_sync(data, opts?: InflateOptions)` シグネチャ
- [x] C-4: トップレベル re-export のシグネチャ更新
- [x] C-T1: 各解凍関数の opts パラメータテスト

## Phase D: ZIP 機能拡張

### per-entry オプション
- [x] D-1: zip_sync per-entry ZipEntryOptions
  - `zip_sync(files: Array[(String, FixedArray[Byte], ZipEntryOptions?)])`
  - エントリごとの level, mtime, attrs, comment, extra
- [x] D-2: unzip_sync フィルタ機能
  - `unzip_sync(data, filter?: (UnzipFileInfo) -> Bool)`
  - 特定ファイルのみ解凍

### ZIP メタデータ拡張
- [x] D-3: UnzipFileInfo フィールド追加
  - mtime, attrs, comment, extra フィールド
  - fflate の UnzipFile 型との互換
- [x] D-4: ZIP64 読み取りサポート
  - z64e (ZIP64 Extended Information) パース
  - 4GB超ファイルの読み取り対応
- [x] D-5: ZIP ファイルコメント (アーカイブレベル)
  - EOCD コメント読み書き

### テスト
- [x] D-T1: per-entry オプションテスト
- [x] D-T2: フィルタ付き unzip テスト
- [x] D-T3: ZIP64 読み取りテスト
- [x] D-T4: 各メタデータフィールドのラウンドトリップテスト

## Phase E: ストリーミング改善

現在のストリーミングはバッファリング方式（全チャンクを蓄積して finish 時に一括処理）。

### 真のインクリメンタル処理
- [x] E-1: Deflate ストリームのインクリメンタル圧縮
  - push ごとに部分出力を生成
  - 32KB スライディングウィンドウの管理
- [x] E-2: Inflate ストリームのインクリメンタル伸長
  - push ごとに部分出力を生成
  - 状態マシンの中断・再開
- [x] E-3: Gzip/Gunzip ストリームのインクリメンタル化
  - ヘッダ/フッタのストリーミング読み書き
- [x] E-4: Zlib/Unzlib ストリームのインクリメンタル化
- [x] E-5: Decompress ストリームのインクリメンタル化

### コールバック対応
- [x] E-6: ondata コールバック
  - push 時に部分出力をコールバックで通知
  - fflate の `ondata(chunk, final)` 互換
- [x] E-7: Gunzip onmember コールバック
  - マルチメンバーGZIP の各メンバー完了通知
- [x] E-8: flush() メソッド
  - 保留中のデータを強制出力

### ZIP ストリーミング
- [x] E-9: Zip ストリーミング作成
  - ZipPassThrough (Store) / ZipDeflate (Deflate) 入力クラス
  - ファイル単位でのストリーミング追加
- [x] E-10: Unzip ストリーミング解凍
  - onfile コールバックでファイル単位通知
  - register(method, handler) でカスタムデコーダ登録

### テスト
- [x] E-T1: インクリメンタル出力の正確性テスト
- [x] E-T2: 大規模データのストリーミングテスト（メモリ効率）
- [x] E-T3: ZIP ストリーミング作成・解凍テスト
- [x] E-T4: ondata / onmember コールバックテスト

## Phase F: ユーティリティ・エイリアス

- [x] F-1: compress_sync 追加 (gzip_sync のエイリアス)
  - fflate の compressSync 互換
- [x] F-2: strToU8 / strFromU8 実装
  - UTF-8 ↔ FixedArray[Byte] 変換
  - latin1 オプション対応
- [x] F-3: EncodeUTF8 / DecodeUTF8 ストリーミング
  - 文字列 ↔ バイト列のストリーミング変換
- [x] F-T1: compress_sync ラウンドトリップテスト
- [x] F-T2: strToU8/strFromU8 テスト（ASCII, マルチバイト, latin1）
- [x] F-T3: UTF-8 ストリーミングテスト

## Phase G: 互換性検証・品質保証

- [x] G-1: fflate 出力との相互運用テスト
  - fflate で圧縮 → moonzip で伸長（全フォーマット）
  - moonzip で圧縮 → fflate で伸長（全フォーマット）
- [x] G-2: システムツール互換テスト
  - gzip コマンドとの互換
  - unzip コマンドとの互換
  - zlib (Python) との互換
- [x] G-3: 圧縮率ベンチマーク
  - Canterbury Corpus / Silesia Corpus 等の標準テストセット
  - fflate との圧縮率比較表
- [x] G-4: 大規模データテスト
  - 1MB / 10MB / 100MB データ
  - メモリ使用量の検証
- [x] G-5: エッジケース網羅テスト
  - 空データ, 1バイト, 最大長, ランダムデータ
  - 全圧縮レベル × 全フォーマット

## Phase H: 旧タスクリストからの対応漏れ

旧 TASKS.md (v1) にあった未対応項目のうち、上記フェーズに含まれないもの。

- [x] H-1: GZIP マルチメンバー対応
  - 連結された複数 GZIP メンバーの正しい解凍
  - 各メンバーの CRC32/ISIZE 個別検証
- [x] H-2: cmd/ デモ・CLIツールの整備
  - compress / decompress サブコマンド
  - ファイル入出力対応
- [x] H-3: README / API ドキュメント更新
  - 全公開API のドキュメント
  - 使用例の追加
- [x] H-4: AGENTS.md 更新
  - 現在のパッケージ構成を反映
