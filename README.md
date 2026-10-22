# Tsuzuri

日本語の音声入力を、どのアプリにも速く正確に打ち込むための、自分用の Mac アプリ。クラウドの Soniox で文字にし、辞書(語のヒントと置き換え)で表記をそろえる。貼った文から誤って認識したらしい語を Mac の中の LLM(Apple Foundation Models)が挙げ、本人が選んで辞書に足していく。

- 設計書: ai-handout-studio の `doc_20261020_002`。文字だけなら `ai-handout-studio document export doc_20261020_002 --text --out <保存先>` で読める
- いまの段階: 段階2(辞書と予備)まで完了(2026-10-21)。段階3(辞書の候補)も完了(2026-10-22)。次は **段階4(仕上げ)**。段階0の評価で、主の認識は Soniox(ヒントありで文字誤り率5.2%)、Mac 内の予備は WhisperKit に決めた(設計書の「段階0の結果」)

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

   Qwen3-ASR は依存が大きいので別のパッケージで測る(初回はモデル約2GB を取得)。MLX の GPU の部品(`mlx.metallib`)は `swift build` では作られないので、初回だけ Metal Toolchain(約690MB)を入れて作る

   ```bash
   xcodebuild -downloadComponent MetalToolchain
   cd Tools/Qwen3Eval && swift build -c release && BUILD_DIR=$PWD/.build .build/checkouts/speech-swift/scripts/build_mlx_metallib.sh release
   swift run -c release Qwen3Eval --allow-download
   ```

   作らずに流すと `MLX error: Failed to load the default metallib` で止まる。`swift package clean` などで `.build/release` を消したら作り直す

4. 表にする。`eval/results/report.md`(認識ごとの表)と `mistakes.md`(正解と違った文)を書く

   ```bash
   swift run tsuzuri-eval report
   ```

   `--shape` を付けると、保存した認識結果に段階2の整える規則(正規化・つなぎ言葉・`eval/dictionary.json` の置き換え・和欧間スペース)を当てた行も足す。録音は流し直さないので、Soniox の費用はかからない

モデルは `~/Library/Caches/Tsuzuri/models` に置く(iCloud で同期されない場所)。`--allow-download` を付けない限り取得しない。

## 段階1: アプリ(MVP)

`/Applications/Tsuzuri.app` に置いて起動する。署名はキーチェーンの Apple Development の証明書で行う(権限の許可は署名に結び付くため)。

```bash
scripts/build-app-bundle.sh --install
```

初回は設定の窓が開くので、マイクとアクセシビリティを許可する。API キーは `tsuzuri-eval set-key` で登録したものを読む(初回はキーチェーンの確認で「許可」を押す)。

| 操作 | すること |
| --- | --- |
| 右⌘を短く押す | 録音を始める。もう一度押すと止めて貼り付ける |
| 右⌘を長く押す(0.5秒以上) | 押している間だけ録り、離すと貼り付ける |
| 右⌘と一緒にほかのキー(0.2秒以内) | ⌘C などの同時押しとみなし、何もしない |
| 録音中に Esc | 取り消す(Esc は相手のアプリに届けない) |
| ⌃⌥⌘V | 直前の文字をもう一度貼る |

履歴(直近100件)と7日分の音声は `~/Library/Application Support/Tsuzuri/` に置く。段階1では整える規則が無いので、Soniox の出力をそのまま貼る。Soniox に2秒でつながらない・確定が3秒を超えたときは、画面で知らせて録音を履歴に残す。

## 段階2・3: 辞書と候補

| メニュー | すること |
| --- | --- |
| Mac 内だけで認識する | Soniox を使わず WhisperKit で認識する。Soniox が失敗したときは、自動で5分間 Mac 内に切り替わる |
| 直前の録音を認識し直す | 残した音声を Soniox か Mac 内でもう一度文字にして貼る |
| 辞書の候補(N件)… | 貼った文から挙げた候補を、入れるか捨てるか選ぶ。表記の案と入れ方(置き換える・ヒントだけ)は窓で直せる。捨てた組・入れた組は二度出さない |
| 辞書を編集… | 辞書を表で直す。「読みを提案」で、置き換え元にするカタカナの読みの候補を出す |

辞書は `~/Library/Application Support/Tsuzuri/dictionary.json`、候補は同じフォルダの `candidates.json`。Apple Intelligence が無効なときは、候補を出さない。

候補の洗い出しの質は、段階0の認識結果で測る(Apple Foundation Models を使う。録音は流し直さない)。`eval/results/suggest.md` に文ごとの候補を書く

```bash
swift run tsuzuri-eval suggest
```

## フォルダ

| 場所 | 中身 |
| --- | --- |
| `Sources/TsuzuriCore` | 副作用の無い処理(文字誤り率・用語正答率・集計・右⌘の状態・履歴・整える規則・置き換え・ヒントの選び方・候補の拾い方と除き方・候補の貯め方)。テストの中心 |
| `Sources/TsuzuriEngines` | Soniox(話しながら送る接続)・WhisperKit・Apple の認識・Apple Foundation Models(読みの提案・候補の洗い出し)・マイク・キーチェーン・音声ファイル |
| `Sources/TsuzuriApp` | メニューバーのアプリ(右⌘の検知・録音中の表示・貼り付け・設定・履歴・辞書の窓・候補の窓) |
| `Sources/TsuzuriEvalKit` | 評価セットと結果の読み書き |
| `Sources/TsuzuriEval` | 評価用の CLI(`tsuzuri-eval`) |
| `Tools/Qwen3Eval` | Qwen3-ASR の評価(speech-swift を使う別のパッケージ) |
| `eval/` | 評価セット(40文)と評価用の辞書(53語)。録音(`recordings/`)と結果(`results/`)は git に入れない |
| `scripts/build-app-bundle.sh` | アプリを .app にまとめて署名する(`--install` で /Applications に置いて起動) |
| `docs/design-sources/` | 設計書の図・画面のイメージの元と、組み立てスクリプト |

## 検証

```bash
swift build
swift test
```
