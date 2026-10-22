<p align="center"><img src="docs/images/icon.png" width="128" alt="Tsuzuri のアイコン。綴じ糸が声の波形になっている和綴じの冊子"></p>

# Tsuzuri

Mac のメニューバーに常駐する、日本語の音声入力アプリ。キーを押して話すと、いま使っているアプリの入力欄に文字を打ち込む。話している間は途中の文字が出て、技術用語は自分の辞書で表記をそろえ、辞書に足すべき語は Mac の中の LLM が教えてくれる。

[![CI](https://github.com/GentaAmeku/Tsuzuri/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/GentaAmeku/Tsuzuri/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 26](https://img.shields.io/badge/macOS-26-black.svg)](#入れ方)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138.svg)](Package.swift)

[English](README.md) | 日本語

日本語の音声入力は、日本語は得意でも、開発者が口にする語は苦手だ。*Claude Code* はクロードコードに、*TanStack Query* はタンスタッククエリに、*Vitest* は B テストになり、コーディングエージェントへの指示は送る前に毎回直すことになる。Tsuzuri は、Claude Code や Codex への指示・Slack・文書を一日中声で書く人のためのアプリ。自分が使う語は自分の書く表記で出て、使うほど自分の語に強くなる。

<img src="docs/images/hud-demo.gif" alt="録音中の表示。赤い停止ボタンの小さなピルが、途中の文字が届くと上に伸びるカードになり、新しい字はぼかしから浮かび上がる。止めると回る輪になり、貼り終えるとチェックを描く" width="864">

*押して話せば、打ち込まれていく。新しい字は話すそばから浮かび上がり、貼り終えるとチェックが出る。*

## 2 行で始める

```bash
git clone https://github.com/GentaAmeku/Tsuzuri.git && cd Tsuzuri
claude   # 起動したら /tsuzuri-setup と打つ(Codex CLI は codex を起動して $tsuzuri-setup)
```

ほかのエージェントなら、これを貼る: *「https://github.com/GentaAmeku/Tsuzuri を clone して、SETUP.md のとおりに入れて」*

セットアップはゲームブックの形で進む。最初にチェックリストが出て、エージェントが `doctor` を実行し、指された節を読み、済むまで繰り返す(Xcode・署名の証明書・アプリのビルド・モデル・権限)。聞かれるのは、Soniox を使うか Mac の中だけで使うか、Mac 内のモデルを取るか、ログイン時に起動するかだけ。API キーと権限の許可は自分で入れるので、エージェントがキーを見ることはない。終わったら、右⌘を押して話す。

## できること

### 押して話すと、いま使っているアプリに打ち込む

右⌘を軽く押すと録音を始め、もう一度押すと止める。押したまま話してもよい。表示は押した瞬間に出て、話している間は途中の文字が流れ、止めると入力していたアプリ(チャットの欄・エージェントへの指示・文書)に文字が入る。録音中に Return を押せば、貼ってそのまま送信する。

![録音中の表示の、青と白のテーマと黒のテーマ。技術用語を含む文を話している途中](docs/images/hud-themes.png)

*テーマは青と白か黒。まだ変わりうる文字は薄く出る。*

### 技術用語を、自分が書く表記で出す

語を一度足せば、Tsuzuri はその語を聞き取ろうとする。認識にその語が来ると伝え、それでもカタカナで出たら、貼る前に直す(クロードコード → Claude Code)。話している途中の文字も直って出る。えーと・あのーのようなつなぎ言葉は消え、日本語と英字のあいだには半角スペースが入る。

![辞書の窓。上に Return で語を足す1行の欄と、任意の聞き違いの欄。下に語と聞き違いの表](docs/images/dictionary.png)

語を足すのは1行。打って Return を押すだけ。「読みを提案」を押すと、化けそうなカタカナの読みを挙げてくれる。

### 辞書に足すべき語を教えてくれる

貼るたびに、Tsuzuri は裏で聞き違えたらしい語を探し、Mac の中の Apple のモデルに本来の表記を考えさせる。候補は窓にたまるので、入れたいものを選び、必要なら表記を直す。次に話したときから正しく出る。勝手には入らず、捨てた組は二度出ない。

![候補の窓。赤い取り消し線の聞き違いから、直せる欄の表記の案へ矢印。出た文の前後と、捨てる・入れるのボタン](docs/images/candidates.png)

### クラウドで速く、Mac の中で安心に

[Soniox](https://soniox.com) なら、止めてから約0.2秒で文字ができる。メニューで「Mac 内」に切り替えれば、何も Mac の外へ出ない(Whisper が文字にし、Apple の認識が途中の文字を出す)。Soniox が失敗したときは、録音を Mac の中で文字にし直すので(Mac 内のモデルを入れてあるとき)、話した文が消えない。

## 使い方

| キー | すること |
| --- | --- |
| 右⌘を軽く押す | 録音を始める。もう一度押すと止めて貼る |
| 右⌘を押したまま | 押している間だけ録り、離すと貼る |
| 録音中に Esc | 取り消す |
| 録音中に Return | 止めて貼り、送信する |
| ⌃⌥⌘V | 直前の文字をもう一度貼る |

メニューバーのアイコンから:

| メニュー | すること |
| --- | --- |
| 認識 | Soniox か Mac 内かを選ぶ |
| 直前の録音を認識し直す | 直前の録音を、Soniox か Mac 内でもう一度文字にする |
| 履歴 | 直近の文字。選ぶとコピーする |
| 辞書の候補(N件)… | Tsuzuri が足すよう勧める語 |
| 辞書を編集… | 自分の語を足す・直す |
| 設定… | 録音キー(右⌘・右⌥・fn)・押し方・テーマ・ログイン時の起動・Soniox の API キー |

メニューには、今月の Soniox の使用時間と推定の代金も出る。

## 入れ方

Apple シリコンの Mac(macOS 26)、Xcode 26、Apple Development の証明書(無料の Apple ID でよい。作り方はセットアップが案内する)が要る。Soniox のアカウントは任意で、無ければ Mac の中だけで動く。アプリの画面は日本語。

上のセットアップを Claude Code か Codex で動かす。手で入れたいときは、すべての手順が [SETUP.ja.md](SETUP.ja.md)(英語は [SETUP.md](SETUP.md))にある。更新は `git pull` のあとセットアップを流し直すだけで、アプリをビルドし直し、ほかはそのまま残る。外し方は SETUP.ja.md の付録B。

アプリが触れるもの(マイク・アクセシビリティ・通信)と、脆弱性の報告の仕方は [SECURITY.md](SECURITY.md) にある。

## ライセンス

[MIT](LICENSE)。[WhisperKit](https://github.com/argmaxinc/WhisperKit)(MIT)・[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)(MIT)・[swift-argument-parser](https://github.com/apple/swift-argument-parser)(Apache 2.0)を使っている。
