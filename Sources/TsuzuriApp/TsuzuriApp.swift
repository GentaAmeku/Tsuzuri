import AppKit
import KeyboardShortcuts
import SwiftUI
import TsuzuriCore
import TsuzuriEngines

extension KeyboardShortcuts.Name {
    /// 直前の文字をもう一度貼る。設定の窓で変えられる
    static let pasteLast = Self("pasteLast", default: .init(.v, modifiers: [.control, .option, .command]))
}

@main
struct TsuzuriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: appDelegate.controller)
        } label: {
            MenuBarIcon(controller: appDelegate.controller)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 録音中の表示を画像に描き出して終わる(--render-hud <フォルダ>。画面の録画の権限が無くても見た目を確かめられる)。
        // キーの検知やキーチェーンの読み出しより前に終える
        if let index = CommandLine.arguments.firstIndex(of: "--render-hud"), index + 1 < CommandLine.arguments.count {
            RecordingHUD.renderSamples(to: URL(filePath: CommandLine.arguments[index + 1], directoryHint: .isDirectory))
            exit(0)
        }
        // アプリの中で、途中の文字の認識に録音を実際の速さで渡し、途中の文字を書き出して終わる(--simulate-live <録音の WAV>)
        if let index = CommandLine.arguments.firstIndex(of: "--simulate-live"), index + 1 < CommandLine.arguments.count {
            let url = URL(filePath: CommandLine.arguments[index + 1])
            Task { [controller] in
                do {
                    let samples = try AudioFile.readSamples(from: url)
                    print(await AppleSpeechLive.assetReport())
                    // アプリの録音と同じく、辞書の語をヒントに渡す
                    let terms = Array(controller.dictionary.hintTerms().prefix(WhisperKitEngine.hintLimit))
                    print("語のヒント: \(terms.count)語")
                    let live = try await AppleSpeechLive.start(terms: terms)
                    let started = Date()
                    // 表示に出すのと同じく、辞書などで整えた文字を書く(| の左が確定した字)
                    let shaper = controller.dictionary.shaper(waObunSpacing: controller.store.waObunSpacing)
                    live.onUpdate = { final, volatile in
                        let shaped = shaper.shapePartial(final: final, tentative: volatile)
                        let shown = String(shaped.text.prefix(shaped.finalLength)) + "|" + String(shaped.text.dropFirst(shaped.finalLength))
                        print(String(format: "%.1f秒: %@", Date().timeIntervalSince(started), shown))
                    }
                    var fed = 0
                    while fed < samples.count {
                        let next = min(samples.count, fed + 1_600)
                        live.feed(Array(samples[fed..<next]))
                        fed = next
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    print("最後: " + (await live.finish()))
                } catch {
                    print("失敗: \(error)")
                }
                exit(0)
            }
            return
        }
        // 試し: 途中の文字の認識を3回続けて始め、2回目の前に認識の常駐プロセスが終わっても使えるかを見る(--live-repeat <録音の WAV>)
        if let index = CommandLine.arguments.firstIndex(of: "--live-repeat"), index + 1 < CommandLine.arguments.count {
            let url = URL(filePath: CommandLine.arguments[index + 1])
            Task {
                let samples = (try? AudioFile.readSamples(from: url)) ?? []
                for round in 1...3 {
                    do {
                        let live = try await AppleSpeechLive.start(terms: [])
                        var fed = 0
                        while fed < min(samples.count, 48_000) {
                            let next = min(samples.count, fed + 1_600)
                            live.feed(Array(samples[fed..<next]))
                            fed = next
                            try await Task.sleep(for: .milliseconds(100))
                        }
                        print("\(round)回目: " + (await live.finish()))
                    } catch {
                        print("\(round)回目: 失敗 \(error)")
                    }
                    try? await Task.sleep(for: .seconds(10))
                }
                exit(0)
            }
            return
        }
        // 辞書の窓を写し取って終わる(--render-dictionary <フォルダ>)
        if let index = CommandLine.arguments.firstIndex(of: "--render-dictionary"), index + 1 < CommandLine.arguments.count {
            let directory = URL(filePath: CommandLine.arguments[index + 1], directoryHint: .isDirectory)
            Task {
                await DictionaryWindow.render(store: controller.dictionary, to: directory)
                exit(0)
            }
            return
        }
        // 候補の窓を写し取って終わる(--render-candidates <フォルダ>)
        if let index = CommandLine.arguments.firstIndex(of: "--render-candidates"), index + 1 < CommandLine.arguments.count {
            let directory = URL(filePath: CommandLine.arguments[index + 1], directoryHint: .isDirectory)
            Task {
                await CandidateWindow.render(store: controller.candidates, to: directory)
                exit(0)
            }
            return
        }
        // 設定の窓をタブごとに写し取って終わる(--render-settings <フォルダ>)
        if let index = CommandLine.arguments.firstIndex(of: "--render-settings"), index + 1 < CommandLine.arguments.count {
            let directory = URL(filePath: CommandLine.arguments[index + 1], directoryHint: .isDirectory)
            Task {
                await SettingsWindow.renderTabs(controller: controller, to: directory)
                exit(0)
            }
            return
        }
        // 本物の窓で、音量と文字を流しながら表示を写し取って終わる(--simulate-hud <フォルダ> [dark] [frames])。
        // frames を付けると、動きを確かめるために 1/30 秒ごとの絵も残す
        if let index = CommandLine.arguments.firstIndex(of: "--simulate-hud"), index + 1 < CommandLine.arguments.count {
            let directory = URL(filePath: CommandLine.arguments[index + 1], directoryHint: .isDirectory)
            let theme: HUDTheme = CommandLine.arguments.contains("dark") ? .dark : .blueWhite
            Task {
                await RecordingHUD.simulate(to: directory, theme: theme, frames: CommandLine.arguments.contains("frames"))
                exit(0)
            }
            return
        }
        NSApp.setActivationPolicy(.accessory)
        KeyboardShortcuts.onKeyUp(for: .pasteLast) { [controller] in
            controller.pasteLast()
        }
        controller.start()
        // 動作の確かめ用: 起動時に窓を開く(open -a Tsuzuri --args --show-dictionary)
        if CommandLine.arguments.contains("--show-dictionary") { controller.showDictionary() }
        if CommandLine.arguments.contains("--show-settings") { controller.showSettings() }
        if CommandLine.arguments.contains("--show-candidates") { controller.showCandidates() }
        // 録音中の表示を見本の文字で出す(--preview-hud、黒は --preview-hud-dark)
        if let theme = [("--preview-hud", HUDTheme.blueWhite), ("--preview-hud-dark", .dark)].first(where: { CommandLine.arguments.contains($0.0) })?.1 {
            controller.previewHUD(theme: theme)
        }
    }
}
