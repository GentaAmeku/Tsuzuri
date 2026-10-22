#!/bin/zsh
# Tsuzuri の doctor。セットアップの状態を調べ、SETUP.md の次に読む節を返す。何も書き換えない(直すのはエージェントと本人)。
# Xcode を入れる前にも動くよう、macOS に最初からある zsh と道具だけで書く。
#
# 使い方: scripts/doctor.sh [--json | --checklist] [--lang ja|en]
#   --json       結果を JSON で出す(ok・next・checks)。セットアップが済むまで終了コードは 1
#   --checklist  節ごとの進み具合を Markdown のチェックリストで出す(既定)
#   --lang       チェックリストの言葉。省くとシステムの言語(日本語なら ja)
emulate -L zsh
setopt pipe_fail

ROOT=${0:A:h:h}
APP=/Applications/Tsuzuri.app
DOMAIN=work.ameku.Tsuzuri
SUPPORT="$HOME/Library/Application Support/Tsuzuri"
MODELS="$HOME/Library/Caches/Tsuzuri/models"
WHISPER_MODEL=large-v3-v20240930_626MB

mode=checklist
lang=""
while (( $# > 0 )); do
  case $1 in
    --json) mode=json ;;
    --checklist) mode=checklist ;;
    --lang) shift; lang=${1:-} ;;
  esac
  shift
done
if [[ -z $lang ]]; then
  first=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')
  [[ $first == ja* ]] && lang=ja || lang=en
fi

typeset -a ids statuses sections details
add() { ids+=("$1"); statuses+=("$2"); sections+=("$3"); details+=("$4") }
pref() { defaults read "$DOMAIN" "$1" 2>/dev/null }

# 2. 前提: macOS 26 以上・Apple シリコン・Xcode(Swift 6.2 以上)
os=$(sw_vers -productVersion)
if (( ${os%%.*} >= 26 )); then add macos ok 2 "$os"; else add macos missing 2 "macOS $os (26 or later is needed)"; fi
arch=$(uname -m)
if [[ $arch == arm64 ]]; then add apple-silicon ok 2 arm64; else add apple-silicon missing 2 "$arch (Apple silicon is needed)"; fi
devdir=$(xcode-select -p 2>/dev/null)
if [[ $devdir != *.app/Contents/Developer ]]; then
  add xcode missing 2 "xcode-select points to '${devdir:-nothing}', not Xcode"
else
  swift_version=$(xcrun swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9][0-9.]*\).*/\1/p' | head -1)
  major=${swift_version%%.*}; rest=${swift_version#*.}; minor=${rest%%.*}
  if [[ -n $swift_version ]] && (( major > 6 || (major == 6 && minor >= 2) )); then
    add xcode ok 2 "Swift $swift_version ($devdir)"
  else
    add xcode missing 2 "Swift ${swift_version:-not found} (6.2 or later is needed; open Xcode once and accept its license)"
  fi
fi

# 3. 署名の証明書(権限の許可は署名に結び付くので、Apple Development で署名する)
if [[ -n ${TSUZURI_SIGNING_IDENTITY:-} ]]; then
  add signing-identity ok 3 "TSUZURI_SIGNING_IDENTITY"
else
  identities=$(security find-identity -v -p codesigning 2>/dev/null | grep -c '"Apple Development:')
  if (( identities > 0 )); then add signing-identity ok 3 "$identities Apple Development identity"; else add signing-identity missing 3 "no Apple Development certificate in the keychain"; fi
fi

# 4. アプリのビルドと配置。このリポジトリの今のコミットから作ったものか
head=$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null)
if [[ ! -d $APP ]]; then
  add app missing 4 "$APP is not there"
else
  built=$(/usr/libexec/PlistBuddy -c "Print :TsuzuriSourceRevision" "$APP/Contents/Info.plist" 2>/dev/null)
  if ! codesign --verify "$APP" 2>/dev/null; then
    add app outdated 4 "the signature of $APP does not verify"
  elif [[ ${built%-dirty} != "$head" ]]; then
    add app outdated 4 "built from ${built:-unknown}, the repository is at $head"
  else
    add app ok 4 "built from $built"
  fi
fi

# 5. 認識: Soniox の API キーがキーチェーンにあるか、Mac 内だけで使うと決めたか(キーの中身は読まない)
if security find-generic-password -s Tsuzuri.Soniox >/dev/null 2>&1; then
  add recognizer ok 5 "Soniox (API key in the Keychain)"
elif [[ $(pref localOnly) == 1 ]]; then
  add recognizer ok 5 "on-device only"
else
  add recognizer missing 5 "choose Soniox or on-device only"
fi

# 6. Mac 内のモデル。Mac 内だけで使うなら WhisperKit は欠かせない
whisper_dir=$(find "$MODELS" -maxdepth 5 -type d -name "*$WHISPER_MODEL" -print -quit 2>/dev/null)
if [[ -n $whisper_dir ]] && ls -d "$whisper_dir"/*.mlmodelc >/dev/null 2>&1 && [[ -d $MODELS/models/openai/whisper-large-v3 ]]; then
  add whisperkit-model ok 6 "$WHISPER_MODEL"
elif [[ $(pref setupWhisperModel) == declined && $(pref localOnly) != 1 ]]; then
  add whisperkit-model skipped 6 "declined (no on-device fallback)"
else
  add whisperkit-model missing 6 "WhisperKit $WHISPER_MODEL is not downloaded"
fi
if [[ -f $MODELS/apple-japanese.json ]]; then
  add apple-model ok 6 "installed"
elif [[ $(pref setupAppleModel) == declined ]]; then
  add apple-model skipped 6 "declined (no live captions on-device)"
else
  add apple-model missing 6 "Apple's Japanese model is not installed"
fi

# 7. 権限。アプリが setup-status.json に書いた状態を読む
status_file="$SUPPORT/setup-status.json"
if ! pgrep -x TsuzuriApp >/dev/null; then
  add app-running missing 7 "Tsuzuri is not running (open -a Tsuzuri)"
elif [[ ! -f $status_file ]]; then
  add app-running missing 7 "Tsuzuri has not reported its status yet; wait a few seconds"
else
  add app-running ok 7 "running"
  mic=$(plutil -extract microphone raw -o - "$status_file" 2>/dev/null)
  if [[ $mic == authorized ]]; then add microphone ok 7 authorized; else add microphone missing 7 "${mic:-unknown}"; fi
  ax=$(plutil -extract accessibility raw -o - "$status_file" 2>/dev/null)
  listening=$(plutil -extract listening raw -o - "$status_file" 2>/dev/null)
  if [[ $ax == true && $listening == true ]]; then
    add accessibility ok 7 "granted, the recording key is watched"
  elif [[ $ax == true ]]; then
    add accessibility missing 7 "granted, but the key monitor has not started yet"
  else
    add accessibility missing 7 "not granted"
  fi
fi

# 8. ログイン時の起動(任意)
login=""
[[ -f $status_file ]] && login=$(plutil -extract loginItem raw -o - "$status_file" 2>/dev/null)
if [[ $login == enabled ]]; then
  add login-item ok 8 enabled
elif [[ $(pref setupLoginItem) == declined ]]; then
  add login-item skipped 8 declined
elif [[ $login == requiresApproval ]]; then
  add login-item missing 8 "waiting for approval in System Settings > General > Login Items"
else
  add login-item missing 8 "not decided"
fi

# 9. 試す: 1回でも音声入力したか
history_file="$SUPPORT/history.jsonl"
count=0
[[ -f $history_file ]] && count=$(grep -c '"text"' "$history_file" 2>/dev/null)
if (( count > 0 )); then add first-dictation ok 9 "$count in the history"; else add first-dictation missing 9 "no dictation yet"; fi

# 次に読む節: 番号の小さい節から、ok でも skipped でもない最初の項目
next_index=0
for i in {1..${#ids}}; do
  if [[ ${statuses[$i]} != ok && ${statuses[$i]} != skipped ]]; then next_index=$i; break; fi
done

json_escape() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; print -rn -- "$s" }

if [[ $mode == json ]]; then
  print -n '{"ok": '
  (( next_index == 0 )) && print -n true || print -n false
  print -n ', "next": '
  if (( next_index == 0 )); then
    print -n null
  else
    print -n "{\"section\": ${sections[$next_index]}, \"reason\": \"$(json_escape "${ids[$next_index]}: ${details[$next_index]}")\"}"
  fi
  print -n ', "checks": ['
  for i in {1..${#ids}}; do
    (( i > 1 )) && print -n ', '
    print -n "{\"id\": \"${ids[$i]}\", \"status\": \"${statuses[$i]}\", \"section\": ${sections[$i]}, \"detail\": \"$(json_escape "${details[$i]}")\"}"
  done
  print ']}'
else
  typeset -A names
  if [[ $lang == ja ]]; then
    names=(2 "前提" 3 "署名の証明書" 4 "アプリのビルドと配置" 5 "認識の選択" 6 "Mac 内のモデル" 7 "権限" 8 "ログイン時の起動" 9 "試す")
  else
    names=(2 "Prerequisites" 3 "Signing certificate" 4 "Build and install the app" 5 "Recognizer" 6 "On-device models" 7 "Permissions" 8 "Launch at login" 9 "Try it")
  fi
  done_count=0
  lines=()
  for section in {2..9}; do
    complete=1; skipped=0
    for i in {1..${#ids}}; do
      [[ ${sections[$i]} == $section ]] || continue
      [[ ${statuses[$i]} == skipped ]] && skipped=1
      [[ ${statuses[$i]} != ok && ${statuses[$i]} != skipped ]] && complete=0
    done
    mark=" "; note=""
    if (( complete )); then
      mark=x; (( done_count++ ))
      (( skipped )) && { [[ $lang == ja ]] && note="(一部を飛ばした)" || note=" (partly skipped)"; }
    elif (( next_index > 0 )) && [[ ${sections[$next_index]} == $section ]]; then
      [[ $lang == ja ]] && note=" ← 次" || note=" ← next"
    fi
    lines+=("- [$mark] $section. ${names[$section]}$note")
  done
  if [[ $lang == ja ]]; then
    if (( next_index == 0 )); then print "セットアップの進み具合: $done_count/8 節(済んでいる)"; else print "セットアップの進み具合: $done_count/8 節(次は節 ${sections[$next_index]})"; fi
  else
    if (( next_index == 0 )); then print "Setup progress: $done_count/8 sections (done)"; else print "Setup progress: $done_count/8 sections (next: section ${sections[$next_index]})"; fi
  fi
  print
  print -l -- $lines
fi

(( next_index == 0 ))
