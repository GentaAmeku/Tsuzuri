import AppKit
import Observation
import SwiftUI
import TsuzuriCore

/// 候補の窓の中身。表記の案と入れ方は、本人が窓で直せる
@Observable
final class CandidateWindowModel {
    struct Draft: Equatable {
        var surface: String
        var mode: InsertionMode
        var checked: Bool
    }

    var drafts: [DiscardedPair: Draft] = [:]
    var showsDiscarded = false
    private(set) var message: String?

    @ObservationIgnored let store: CandidateStore

    init(store: CandidateStore) {
        self.store = store
    }

    /// 窓で直していない候補は、1つ目の表記の案と入れ方の初期値で始める。
    /// 初めは選んでいない状態にし、入れたいものだけを選ぶ(ふつうの語までまとめて入るのを防ぐため)
    func draft(for item: StoredCandidate) -> Draft {
        drafts[item.id] ?? Draft(surface: item.surfaces[0], mode: InsertionMode.initial(heard: item.heard, surface: item.surfaces[0]), checked: false)
    }

    func binding<Value>(_ item: StoredCandidate, _ keyPath: WritableKeyPath<Draft, Value>) -> Binding<Value> {
        Binding(
            get: { [weak self] in self?.draft(for: item)[keyPath: keyPath] ?? Draft(surface: "", mode: .hintOnly, checked: false)[keyPath: keyPath] },
            set: { [weak self] value in
                guard let self else { return }
                var draft = self.draft(for: item)
                let surfaceBefore = draft.surface
                draft[keyPath: keyPath] = value
                // 表記を直したら、入れ方の初期値を決め直す
                if draft.surface != surfaceBefore {
                    draft.mode = InsertionMode.initial(heard: item.heard, surface: draft.surface)
                }
                self.drafts[item.id] = draft
            }
        )
    }

    /// 2つ目の表記の案と入れ替える
    func swapSurface(_ item: StoredCandidate, to surface: String) {
        binding(item, \.surface).wrappedValue = surface
    }

    func canReplace(_ item: StoredCandidate) -> Bool {
        TermReplacer.kind(of: item.heard) != .unsupported
    }

    @discardableResult
    func insert(_ item: StoredCandidate) -> Bool {
        let draft = draft(for: item)
        do {
            try store.insert(item, surface: draft.surface, mode: draft.mode)
            drafts[item.id] = nil
            message = "「\(draft.surface)」を辞書に入れました。次の音声入力から効きます"
            return true
        } catch {
            message = "\(error)"
            return false
        }
    }

    func discard(_ item: StoredCandidate) {
        store.discard(item.id)
        drafts[item.id] = nil
    }

    var checkedItems: [StoredCandidate] {
        store.items.filter { draft(for: $0).checked && !draft(for: $0).surface.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func insertChecked() {
        let items = checkedItems
        for item in items {
            guard insert(item) else { return }
        }
        if items.count > 1 {
            message = "\(items.count)件を辞書に入れました。次の音声入力から効きます"
        }
    }

    func discardAll() {
        for item in store.items { discard(item) }
    }
}

final class CandidateWindow {
    private let store: CandidateStore
    private var window: NSWindow?

    init(store: CandidateStore) {
        self.store = store
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let model = CandidateWindowModel(store: store)
        let window = NSWindow(contentViewController: NSHostingController(rootView: CandidateWindowView(model: model)))
        window.title = "辞書の候補"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 860, height: 520))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct CandidateWindowView: View {
    @Bindable var model: CandidateWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $model.showsDiscarded) {
                Text("候補 \(model.store.file.items.count)").tag(false)
                Text("捨てたもの \(model.store.file.discarded.count)").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)

            if model.showsDiscarded {
                discardedList
            } else {
                Text("音声入力の文から、誤って認識したらしい語を挙げました。表記の案は直してから入れられます。調べたのはこの Mac の中です。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.store.isUnavailable {
                    Text("Apple Intelligence が無効なので、辞書の候補を出していません").foregroundStyle(.orange)
                }
                candidateList
            }

            HStack {
                if let message = model.message ?? model.store.lastError {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("入れた語は「辞書を編集…」でいつでも直せます").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.showsDiscarded {
                    Button("すべて捨てる") { model.discardAll() }
                        .disabled(model.store.file.items.isEmpty)
                    Button("選んだ\(model.checkedItems.count)件を入れる") { model.insertChecked() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.checkedItems.isEmpty)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 360)
    }

    @ViewBuilder private var candidateList: some View {
        let items = model.store.items
        if items.isEmpty {
            Spacer()
            Text("候補はありません").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Spacer()
        } else {
            List(items) { item in
                row(item)
            }
        }
    }

    private func row(_ item: StoredCandidate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: model.binding(item, \.checked)).labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.heard).strikethrough().foregroundStyle(.red)
                    Text("→").foregroundStyle(.secondary)
                    TextField("正しい表記", text: model.binding(item, \.surface))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    ForEach(item.surfaces.dropFirst(), id: \.self) { other in
                        Button(other) { model.swapSurface(item, to: other) }
                            .buttonStyle(.bordered)
                            .help("この表記の案と入れ替えます")
                    }
                }
                Text("…\(item.before)【\(item.heard)】\(item.after)…" + (item.app.map { "(\(Self.appName($0)))" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("", selection: model.binding(item, \.mode)) {
                Text("置き換える").tag(InsertionMode.replace)
                Text("ヒントだけ").tag(InsertionMode.hintOnly)
            }
            .labelsHidden()
            .frame(width: 120)
            .disabled(!model.canReplace(item))
            .help(model.canReplace(item) ? "置き換える: 次から認識した語を表記に直す。ヒントだけ: 認識に渡すだけで、置き換えない" : "漢字・かなの語は置き換えに使いません(ヒントだけ)")
            Text("\(item.count)回").monospacedDigit().frame(width: 40, alignment: .trailing)
            Button("捨てる") { model.discard(item) }
            Button("入れる") { model.insert(item) }
                .buttonStyle(.borderedProminent)
                .disabled(model.draft(for: item).surface.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var discardedList: some View {
        let discarded = model.store.file.discarded
        if discarded.isEmpty {
            Spacer()
            Text("捨てたものはありません").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Spacer()
        } else {
            Text("捨てた組は二度出しません。戻すと、次に出たときにまた候補になります。").font(.callout).foregroundStyle(.secondary)
            List(discarded.reversed(), id: \.self) { pair in
                HStack {
                    Text("\(pair.heard) → \(pair.surface)")
                    Spacer()
                    Button("戻す") { model.store.restore(pair) }
                }
            }
        }
    }

    /// バンドル ID からアプリの名前を引く。見つからなければ ID のまま
    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
