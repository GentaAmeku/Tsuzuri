# Tsuzuri の作業の決まり

- 設計書の正本は ai-handout-studio の `doc_20261020_002`。作業の前に `ai-handout-studio document export doc_20261020_002 --text --out <一時ファイル>` で読む。設計と食い違う変更は、先に設計書を直して本人の合意を取る
- 作る順番は設計書の段階0〜4。段階の終わりの条件を満たしてから次へ進む。段階0(測る)は 2026-10-20 に終わった(主は Soniox、Mac 内は WhisperKit)。段階1(MVP)と段階2(辞書と予備)は 2026-10-21 に完了。段階3(辞書の候補の洗い出し)と段階4(仕上げ)も 2026-10-22 に完了。以後は本人のフィードバックごとに直す
- 副作用の無い処理は `TsuzuriCore` に置き、日本語の例でテストを付ける(swift-testing。テスト名は日本語)。OS や外部とのやり取りは `TsuzuriEngines`、評価の読み書きは `TsuzuriEvalKit`
- 検証は `swift build` と `swift test`。`Tools/Qwen3Eval` は別のパッケージなので、触ったらそこで `swift build`
- アプリの外部ライブラリは、Mac 内の認識の WhisperKit(段階2から)と KeyboardShortcuts(⌃⌥⌘V のため段階1から。登録画面は段階4)だけ。足すときは理由を設計書に書く
- Soniox の API キーはキーチェーン(サービス名 `Tsuzuri.Soniox`)に置く。キーをファイル・ログ・会話に出さない
- 録音(`eval/recordings/`)は本人の声なので git に入れない。評価の文に取引先の名前を入れない
- モデルの取得(WhisperKit・Qwen3-ASR・Apple の認識)は数百MB〜数GB になる。ディスクの空きが少ないので、本人に確認してから行う。置き場所は `~/Library/Caches/Tsuzuri/models`
- コミットメッセージは日本語で書く
- README は英語(`README.md`)と日本語(`README.ja.md`)の2つで、中身をそろえる。載せるのはアプリの魅力・使い方・入れ方だけ(仕組みや測った結果の説明は載せない。本人の指示)。画像は `docs/images/`。開発の手順と評価の CLI の使い方は `docs/development.ja.md`
- 入れ方は AI Handout Studio と同じゲームブック: `SETUP.md`・`SETUP.ja.md`(節の番号をそろえる)、`scripts/doctor.sh`(状態を調べて次の節を返す。zsh と macOS の道具だけで書き、何も書き換えない)、スキル `.agents/skills/tsuzuri-setup`(`.claude/skills` から symlink)。入れ方・権限・設定の項目を変えたら、この3つを合わせて直す。アプリは権限の状態を `setup-status.json` に書き、doctor がそれを読む
- GitHub(`GentaAmeku/Tsuzuri`、公開)に置いている。README の画像は、本人の辞書・候補・履歴を写さないよう、見本の辞書と候補だけを置いた場所(`CFFIXED_USER_HOME`)でアプリを動かして写す。動作確認の起動引数(`--render-hud` など)は debug ビルド(`.build/debug/TsuzuriApp`)だけで効く
- 公開しているので、変更のたびに秘密の情報・本人の声や文字・取引先の名前を入れていないかを確かめる。セキュリティの考え方は `SECURITY.md` にあり、変えたら合わせて直す
