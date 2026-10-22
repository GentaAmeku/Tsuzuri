# セットアップ

このファイルは、コーディングエージェント(Claude Code・Codex CLI など、シェルのコマンドを動かせるエージェント)が読むためのもの。入れるときは、次のどれかで始める。

- **Claude Code:** リポジトリを clone し、その中で Claude Code を起動して `/tsuzuri-setup` と打つ
- **Codex CLI:** リポジトリを clone して開き、`$tsuzuri-setup` と打つ
- **ほかのエージェント:** リポジトリを clone して開き、**「SETUP.md のとおりに入れて」** と頼む
- **clone する前:** エージェントに「https://github.com/GentaAmeku/Tsuzuri を clone して、SETUP.md のとおりに入れて」と頼む

セットアップはゲームブックの形で進む。`scripts/doctor.sh` が今の状態を調べ、次に読む節を返す。節の番号は [SETUP.md](SETUP.md)(英語)と同じ。

セットアップは、更新のあと(付録A)など、いつ流し直してもよい。済んだ節は済んだままで、doctor は足りないものと、まだ決めていないものだけで止まる。

## 1. はじめに(エージェントへ)

まず、リポジトリの直下で `scripts/doctor.sh --checklist` を実行し、出力をそのまま利用者に見せる。節ごとに1行の Markdown のチェックリストで、済んだもの・残りのもの・次の節が分かる。

そのあと、`ok` が `true` になるまで次を繰り返す。

1. リポジトリの直下で `scripts/doctor.sh --json` を実行する。macOS に最初からある道具だけで動くので、Xcode を入れる前でも使える
2. `next.section` の節を読む。`next.reason` に足りないものが書いてある。セットアップが済むまで終了コードは 1
3. その節のとおりに進め、doctor をもう一度実行する

`ok` が `true` になったら、この回で済ませた節があればチェックリストをもう一度見せる。

`checks` には、項目ごとに `status` が入る: `ok`、`missing`(無い、またはまだ決めていない)、`outdated`(あるが古い版から作った)、`skipped`(利用者が断った)。

利用者への約束:

- 利用者の言葉で話す。聞くのは選ぶものだけ: Soniox か Mac 内だけか(節5)、Mac 内のモデルを取るか(節6)、ログイン時に起動するか(節8)。ほかはエージェントが決める。doctor が `ok` か `skipped` と言うものは聞き直さない
- **Soniox の API キーを会話で聞かない。エージェント自身がキーを打ち込んだり、表示したり、残したりしない。** キーは利用者がアプリか自分の端末で入れる(節5)
- モデルを取る前に聞く。大きさも伝える
- システム設定(プライバシーの権限・ログイン項目)はエージェントが変えない。どこを押すかを伝える
- `sudo` は使わない。要る手順は、コマンドを示して利用者に実行してもらう
- 節に書いていないものは変えない

## 2. 前提

doctor は、macOS 26 以上・Apple シリコン・Swift 6.2 以上の Xcode を確かめる。

- **macOS が 26 より古い、または Intel の Mac:** 止める。Tsuzuri は Apple シリコンの macOS 26 にしか無い仕組みを使う。利用者にそう伝える
- **Xcode が無い、または `xcode-select` が Command Line Tools を指している:** App Store から Xcode 26 以上を入れ、一度開いて部品の取り込みを済ませてから、利用者の端末で次を実行してもらう

  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```

- **Swift はあるが古い、または Xcode の利用規約にまだ同意していない:** Xcode を更新してもらうか、`sudo xcodebuild -license accept` を実行してもらう

## 3. 署名の証明書

doctor は、キーチェーンに *Apple Development* の署名の証明書があるか(または `TSUZURI_SIGNING_IDENTITY` で指定したか)を確かめる。macOS はマイクとアクセシビリティの許可をアプリの署名に結び付けるので、決まった証明書が無いと、ビルドし直すたびに許可が外れる。

無ければ、利用者に作ってもらう(無料の Apple ID でよい):

1. Xcode を開き、**Xcode > Settings… > Accounts** で、Apple ID が無ければ足す
2. そのアカウントを選んで **Manage Certificates…** を押し、**+** から **Apple Development** を選ぶ

そのあと doctor をもう一度実行する。キーチェーンに証明書がいくつかあり、利用者が使うものを決めたいときは、節4のコマンドを動かすときに `TSUZURI_SIGNING_IDENTITY` にその名前(`security find-identity -v -p codesigning` が出す名前そのまま)を入れる。

## 4. アプリのビルドと配置

doctor は、`/Applications/Tsuzuri.app` があり、署名が正しく、リポジトリの今のコミットから作ったものかを確かめる(`git pull` のあとは `outdated`)。

```bash
scripts/build-app-bundle.sh --install
```

- 初めてのビルドは Swift のパッケージ(WhisperKit・KeyboardShortcuts・swift-argument-parser)を取るので、数分かかる。2回目からは早い
- スクリプトは、動いている Tsuzuri を終了し、`/Applications/Tsuzuri.app` を置き換えて署名し、起動する
- `codesign` がキーチェーンの署名の鍵を使ってよいか macOS が聞いてきたら、利用者に **常に許可** を押してもらう
- Tsuzuri は Dock ではなくメニューバー(マイクのアイコン)に常駐する。初めて起動すると設定の窓が開いて権限を求めるが、それは節7で扱うので、開いたままでよいと伝える

## 5. 認識の選択

doctor は、Soniox の API キーがキーチェーン(サービス名 `Tsuzuri.Soniox`)にあるか、利用者が Mac 内だけで使うと決めたかを確かめる(doctor は項目があるかだけを見て、キーの中身は読まない)。

どちらにするかを、違いを添えて利用者に聞く。

| | Soniox(精度を求めるなら推奨) | Mac 内だけ |
| --- | --- | --- |
| 技術用語の精度 | 一番高い | 低め |
| 話している途中の文字 | 出る | 出る(Apple のモデルを入れたとき。節6) |
| 止めてから貼るまで | 約0.2秒 | 約2秒 |
| 通信と費用 | 音声とヒントの語を Soniox へ送る。有料(音声1時間あたり約0.12ドル) | 何も外へ出ない。無料 |
| 要るもの | Soniox のアカウントと API キー | WhisperKit のモデル(節6) |

あとからメニューの **認識** でいつでも切り替えられる。

- **Soniox:** 利用者が Soniox の画面(https://soniox.com)で API キーを作り、自分で入れる。入れ方は2つ
  - Tsuzuri で: メニューバーのアイコン > **設定…** > **Soniox と辞書** のタブで、**新しいキーを貼り付け** に貼って **保存** を押す(推奨: アプリがキーチェーンの項目を作るので、読むときに許可を聞かれない)
  - または利用者の端末で、リポジトリの直下から `swift run tsuzuri-eval set-key`(打った文字は画面に出ない)。この方法で入れたキーをアプリが初めて読むとき、macOS がキーチェーンの許可を聞くので **常に許可** を押す

  利用者が入れたと言うまで待ってから、doctor をもう一度実行する。`set-key` をエージェントが実行したり、キーを聞いたりしない
- **Mac 内だけ:** 選んだことを残し、読み直すようアプリを起動し直す

  ```bash
  defaults write work.ameku.Tsuzuri localOnly -bool true
  pkill -x TsuzuriApp; sleep 1; open -a Tsuzuri
  ```

## 6. Mac 内のモデル

doctor は2つのモデルを確かめる。大きさを添えて、2つまとめて聞く。

- **WhisperKit**(Whisper large-v3、約600MB。`~/Library/Caches/Tsuzuri/models` に置く): Mac 内のときに文字にし、Soniox が失敗したときの予備にもなる。Mac 内だけなら欠かせない。Soniox でも入れるのを勧める
- **Apple の日本語の認識モデル**(macOS が入れる。大きさはシステムが決める): Mac 内のときに、話している途中の文字を出す。任意

2つとも入れてよいと言われたら:

```bash
swift run -c release tsuzuri-eval fetch-model --apple
```

WhisperKit だけなら `--apple` を外す。数分かかる。終わったら、モデルを読み込むようアプリを起動し直す: `pkill -x TsuzuriApp; sleep 1; open -a Tsuzuri`

断られたものは残し、doctor が聞き直さないようにする(WhisperKit を断れるのは Soniox のときだけ):

```bash
defaults write work.ameku.Tsuzuri setupWhisperModel declined
defaults write work.ameku.Tsuzuri setupAppleModel declined
```

あとでまた聞いてほしいときは、その項目を消す: `defaults delete work.ameku.Tsuzuri setupWhisperModel`

## 7. 権限

doctor は `~/Library/Application Support/Tsuzuri/setup-status.json` を読む。アプリは権限が変わると数秒のうちにこのファイルを書き直す。doctor は、アプリが動いているか、マイクが許可されているか、アクセシビリティが許可されて録音キーの検知が動いているかを確かめる。

- **動いていない:** `open -a Tsuzuri`
- **マイク:** Tsuzuri の設定の窓(権限が足りない間は自分で開く。またはメニューバーのアイコン > **設定…** > **一般**)で、利用者が **マイク** の横の **許可する** を押し、macOS の確認で許可する。前に断っていたときは、ボタンで **システム設定 > プライバシーとセキュリティ > マイク** が開くので、Tsuzuri を入にしてもらう
- **アクセシビリティ:** 利用者が **アクセシビリティ** の横の **許可する** を押す。**システム設定 > プライバシーとセキュリティ > アクセシビリティ** が開くので、Tsuzuri を入にしてもらう(パスワードを聞かれることがある)

アクセシビリティは、録音キーの検知・録音中の Esc と Return・⌘V の貼り付けに使う。キーの番号だけを見て、打った文字は読まず、残さない([SECURITY.md](SECURITY.md))。許可してもらう前に、利用者にこれを伝える。

それぞれ許可してもらったら数秒待って、doctor をもう一度実行する。システム設定ではアクセシビリティが入なのに doctor が許可されていないと言うときは、その項目が古い署名のもの。利用者に、一覧で Tsuzuri を選んで **−** で外し、**+** から `/Applications/Tsuzuri.app` を選んで入れ直してもらう。

## 8. ログイン時の起動

任意。ログインしたときに Tsuzuri を起動するかを聞く。

- **する:** 利用者が設定 > **一般** の **ログイン時に起動する** を入にする。macOS が承認を求めたら、**システム設定 > 一般 > ログイン項目** にある
- **しない:** 残しておく

  ```bash
  defaults write work.ameku.Tsuzuri setupLoginItem declined
  ```

## 9. 試す

doctor は、履歴に音声入力が1件以上あるかを確かめる。

利用者に試してもらう。

1. どこかの入力欄をクリックする(メモ・チャットの欄・エージェントへの指示の欄など)
2. 右⌘を短く押す。画面の下に、赤い停止ボタンの小さなピルが出る
3. 文を話す。例: 「Claude Code で TanStack Query のキャッシュを無効にして」
4. もう一度右⌘を押す。入力していた所に文字が貼られる

そのあと doctor をもう一度実行する。`ok` になったら、次に試せることを伝える: 右⌘を長く押して話す、録音中に Return で貼って送る、⌃⌥⌘V で直前の文字をもう一度貼る、**辞書を編集…** で自分の語を足す、メニューの **辞書の候補** で Tsuzuri が挙げた語を入れる。

## 付録A. 更新

```bash
git pull
```

そのあとセットアップを流し直す: Claude Code は `/tsuzuri-setup`、Codex CLI は `$tsuzuri-setup`、ほかのエージェントには「SETUP.md のとおりに入れて」。チェックリストから始まり、節4がアプリを `outdated` と言ってビルドし直す。ほかの節は済んだまま。

## 付録B. 外す

1つずつ利用者に確かめてから進める。2つ目は利用者の辞書と履歴を消す。

1. Tsuzuri を終了し(メニューバーのアイコン > **Tsuzuri を終了**)、`/Applications/Tsuzuri.app` を消す
2. データとモデルを消す: `~/Library/Application Support/Tsuzuri` と `~/Library/Caches/Tsuzuri`
3. Soniox の API キーを消す: `security delete-generic-password -s Tsuzuri.Soniox`
4. 設定を消す: `defaults delete work.ameku.Tsuzuri`
5. **システム設定 > プライバシーとセキュリティ** の **マイク** と **アクセシビリティ**、入れていたなら **ログイン項目** から、利用者に Tsuzuri を外してもらう

Apple の日本語の認識モデルは macOS のものなので残る。

## 付録C. うまくいかないとき

- **右⌘を押しても何も起きない:** 節7をもう一度見る。設定 > **キー** で録音キーを fn にしているなら、システム設定の **キーボード > 🌐キーを押して** を **何もしない** にする
- **ビルドが署名のエラーで止まる:** `security find-identity -v -p codesigning` で、有効な Apple Development の証明書が出るかを見る(節3)
- **Soniox が失敗する:** Tsuzuri は録音を Mac の中で文字にし(WhisperKit のモデルがあるとき)、その後5分は Mac 内で認識する。API キーと Soniox の残高を確かめる
