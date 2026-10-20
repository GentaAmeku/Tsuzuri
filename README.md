# Tsuzuri

日本語の音声入力を、どのアプリにも速く正確に打ち込むための、自分用の Mac アプリ。クラウドの Soniox で文字にし、辞書(語のヒントと置き換え)で表記をそろえ、手で直した語を Mac の中の LLM が辞書に足していく。

- 設計書: ai-handout-studio の `doc_20261020_002`。文字だけなら `ai-handout-studio document export doc_20261020_002 --text --out <保存先>` で読める
- いまの段階: **段階0(測る)**。評価用の CLI ができ、本人の声の録音を待っている

## 段階0: 評価の手順

リポジトリの直下で実行する。

1. Soniox の API キーをキーチェーンに登録する(入力した文字は画面に出ない)

   ```bash
   swift run tsuzuri-eval set-key
   ```

2. 評価セットを1文ずつ読み上げて録る。入力の機器はシステム設定で切り替えておく(AirPods は最初の10文)

   ```bash
   swift run tsuzuri-eval record --mic macbook
   ```

3. 認識させる。`--hints both` が既定で、語のヒントあり・なしの両方を流す

   ```bash
   swift run tsuzuri-eval run --engine soniox
   swift run tsuzuri-eval run --engine whisperkit --allow-download
   swift run tsuzuri-eval run --engine apple-dictation --allow-download
   swift run tsuzuri-eval run --engine apple-speech --allow-download
   ```

   Qwen3-ASR は依存が大きいので別のパッケージで測る(初回はモデル約2GB を取得)

   ```bash
   cd Tools/Qwen3Eval && swift run -c release Qwen3Eval --allow-download
   ```

4. 表にする。`eval/results/report.md`(認識ごとの表)と `mistakes.md`(正解と違った文)を書く

   ```bash
   swift run tsuzuri-eval report
   ```

モデルは `~/Library/Caches/Tsuzuri/models` に置く(iCloud で同期されない場所)。`--allow-download` を付けない限り取得しない。

## フォルダ

| 場所 | 中身 |
| --- | --- |
| `Sources/TsuzuriCore` | 副作用の無い処理(文字誤り率・用語正答率・集計)。テストの中心 |
| `Sources/TsuzuriEngines` | Soniox・Apple の認識・キーチェーン・音声ファイル |
| `Sources/TsuzuriEvalKit` | 評価セットと結果の読み書き |
| `Sources/TsuzuriEval` | 評価用の CLI(`tsuzuri-eval`) |
| `Tools/Qwen3Eval` | Qwen3-ASR の評価(speech-swift を使う別のパッケージ) |
| `eval/` | 評価セット(40文)と評価用の辞書(53語)。録音(`recordings/`)と結果(`results/`)は git に入れない |
| `docs/design-sources/` | 設計書の図・画面のイメージの元と、組み立てスクリプト |

## 検証

```bash
swift build
swift test
```
