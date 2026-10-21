# Tsuzuri の作業の決まり

- 設計書の正本は ai-handout-studio の `doc_20261020_002`。作業の前に `ai-handout-studio document export doc_20261020_002 --text --out <一時ファイル>` で読む。設計と食い違う変更は、先に設計書を直して本人の合意を取る
- 作る順番は設計書の段階0〜4。段階の終わりの条件を満たしてから次へ進む。段階0(測る)は 2026-10-20 に終わった(主は Soniox、Mac 内は WhisperKit)。段階1(MVP)と段階2(辞書と予備)は 2026-10-21 に完了。次は段階3(辞書の自動追加)
- 副作用の無い処理は `TsuzuriCore` に置き、日本語の例でテストを付ける(swift-testing。テスト名は日本語)。OS や外部とのやり取りは `TsuzuriEngines`、評価の読み書きは `TsuzuriEvalKit`
- 検証は `swift build` と `swift test`。`Tools/Qwen3Eval` は別のパッケージなので、触ったらそこで `swift build`
- アプリの外部ライブラリは、Mac 内の認識の WhisperKit(段階2から)と KeyboardShortcuts(⌃⌥⌘V のため段階1から。登録画面は段階4)だけ。足すときは理由を設計書に書く
- Soniox の API キーはキーチェーン(サービス名 `Tsuzuri.Soniox`)に置く。キーをファイル・ログ・会話に出さない
- 録音(`eval/recordings/`)は本人の声なので git に入れない。評価の文に取引先の名前を入れない
- モデルの取得(WhisperKit・Qwen3-ASR・Apple の認識)は数百MB〜数GB になる。ディスクの空きが少ないので、本人に確認してから行う。置き場所は `~/Library/Caches/Tsuzuri/models`
- コミットメッセージは日本語で書く
