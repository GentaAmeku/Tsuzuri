import AppKit
import Observation
import SwiftUI
import TsuzuriCore
import TsuzuriEngines

/// 辞書の編集画面の中身。開いた時点の辞書を写して直し、保存で丸ごと書き換える
@Observable
final class DictionaryEditorModel {
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var surface: String
        var fromText: String
        var hint: Bool
        var pinned: Bool
        var source: DictionaryEntry.Source

        var entry: DictionaryEntry {
            DictionaryEntry(
                surface: surface.trimmingCharacters(in: .whitespaces),
                from: DictionaryEditing.parseList(fromText),
                hint: hint,
                pinned: pinned,
                source: source
            )
        }
    }

    /// 並べ方
    enum Order: Hashable {
        /// 足した順(新しい順)
        case recent
        /// ファイルの順
        case file
    }

    var rows: [Row] = []
    var fillersText = ""
    var filter = ""
    var order: Order = .recent
    /// 「認識に渡す」「いつも渡す」の列を出すか
    var showsDetails = false
    /// 窓の上の1行の欄(語と、任意の聞き違い・読み)
    var quickSurface = ""
    var quickMisheard = ""
    /// 1行の欄の語の読みの提案
    private(set) var quickSuggestions: [String] = []
    private(set) var quickSuggesting = false
    var selection: Set<Row.ID> = []
    private(set) var message: String?
    /// 読みの提案。行ごとの候補
    private(set) var suggestions: [Row.ID: [String]] = [:]
    private(set) var suggesting: Row.ID?
    private(set) var isDirty = false

    @ObservationIgnored private let store: DictionaryStore
    @ObservationIgnored private var base: Date?

    init(store: DictionaryStore) {
        self.store = store
        reload()
    }

    var entries: [DictionaryEntry] { rows.map(\.entry) }
    var issues: [DictionaryEditing.Issue] { DictionaryEditing.issues(entries) }
    var canSave: Bool { isDirty && !issues.contains { $0.blocksSaving } }

    var visibleRows: [Row] {
        let keyword = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = keyword.isEmpty ? rows : rows.filter { $0.surface.lowercased().contains(keyword) || $0.fromText.lowercased().contains(keyword) }
        guard order == .recent else { return filtered }
        // 足した日時の新しい順。日時の無い語(最初の辞書の語)はファイルの順で後ろに並べる
        let dated = filtered.enumerated().map { (offset: $0.offset, row: $0.element, date: store.addedAt($0.element.surface)) }
        return dated.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?): l > r
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.offset < rhs.offset
            }
        }.map(\.row)
    }

    /// 1行の欄から語を足し、その場で保存する。表に直しかけの所があれば、それも一緒に保存する
    func quickAdd() {
        let surface = quickSurface.trimmingCharacters(in: .whitespaces)
        let (entries, result) = DictionaryEditing.quickAdd(surface: surface, misheard: quickMisheard, to: entries)
        switch result {
        case .empty:
            return
        case .unchanged:
            message = "「\(surface)」はもう辞書にあります"
            return
        case .added, .extended:
            break
        }
        if let index = rows.firstIndex(where: { $0.surface == surface }), let entry = entries.first(where: { $0.surface == surface }) {
            rows[index].fromText = DictionaryEditing.joinList(entry.from)
        } else if let entry = entries.last {
            rows.insert(Row(surface: entry.surface, fromText: DictionaryEditing.joinList(entry.from), hint: entry.hint, pinned: entry.pinned, source: entry.source), at: 0)
        }
        isDirty = true
        save()
        guard !isDirty else { return }
        filter = ""
        quickSurface = ""
        quickMisheard = ""
        quickSuggestions = []
        message = "「\(surface)」を\(result == .added ? "足しました" : "直しました")。その語を含む文を話して、正しく出るか確かめてください。まだ誤るなら、出た字を聞き違い・読みに足してください"
    }

    /// 1行の欄の語の読みを、Apple Foundation Models に出させる
    func suggestQuickReadings() {
        let surface = quickSurface.trimmingCharacters(in: .whitespaces)
        guard !surface.isEmpty, !quickSuggesting else { return }
        quickSuggesting = true
        let existing = DictionaryEditing.parseList(quickMisheard)
        Task {
            defer { quickSuggesting = false }
            do {
                quickSuggestions = try await ReadingSuggester.suggest(for: surface, excluding: existing)
                if quickSuggestions.isEmpty { message = "「\(surface)」の読みの候補は出ませんでした" }
            } catch {
                message = "読みを提案できませんでした(\(error.localizedDescription))"
            }
        }
    }

    /// 読みの候補を押したら、聞き違い・読みの欄に足す
    func acceptQuick(_ reading: String) {
        quickMisheard = DictionaryEditing.joinList(DictionaryEditing.parseList(quickMisheard) + [reading])
        quickSuggestions.removeAll { $0 == reading }
    }

    var selectedRow: Row? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return rows.first { $0.id == id }
    }

    func reload() {
        store.reloadIfChanged()
        base = store.modificationDate
        rows = store.dictionary.entries.map {
            Row(surface: $0.surface, fromText: DictionaryEditing.joinList($0.from), hint: $0.hint, pinned: $0.pinned, source: $0.source)
        }
        fillersText = DictionaryEditing.joinList(store.dictionary.fillers)
        suggestions = [:]
        isDirty = false
        message = store.loadError
    }

    func binding<Value>(_ id: Row.ID, _ keyPath: WritableKeyPath<Row, Value>) -> Binding<Value> {
        Binding(
            get: { [weak self] in
                guard let self, let row = self.rows.first(where: { $0.id == id }) else {
                    return Row(surface: "", fromText: "", hint: true, pinned: false, source: .manual)[keyPath: keyPath]
                }
                return row[keyPath: keyPath]
            },
            set: { [weak self] value in
                guard let self, let index = self.rows.firstIndex(where: { $0.id == id }) else { return }
                self.rows[index][keyPath: keyPath] = value
                self.isDirty = true
            }
        )
    }

    var fillersBinding: Binding<String> {
        Binding(get: { [weak self] in self?.fillersText ?? "" }, set: { [weak self] in
            self?.fillersText = $0
            self?.isDirty = true
        })
    }

    func deleteSelected() {
        rows.removeAll { selection.contains($0.id) }
        selection = []
        isDirty = true
    }

    func save() {
        do {
            try store.save(entries: entries, fillers: DictionaryEditing.parseList(fillersText), base: base)
            base = store.modificationDate
            isDirty = false
            message = "保存しました。次の音声入力から効きます"
        } catch {
            message = "\(error)"
        }
    }

    /// 選んだ語の読みを Apple Foundation Models に出させる(候補を並べるだけで、足すのは本人が選んだもの)
    func suggestReadings(for row: Row) {
        let surface = row.surface.trimmingCharacters(in: .whitespaces)
        guard !surface.isEmpty, suggesting == nil else { return }
        suggesting = row.id
        let existing = DictionaryEditing.parseList(row.fromText)
        Task {
            defer { suggesting = nil }
            do {
                let readings = try await ReadingSuggester.suggest(for: surface, excluding: existing)
                suggestions[row.id] = readings
                if readings.isEmpty { message = "「\(surface)」の読みの候補は出ませんでした" }
            } catch {
                message = "読みを提案できませんでした(\(error.localizedDescription))"
            }
        }
    }

    func accept(_ reading: String, for id: Row.ID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let list = DictionaryEditing.parseList(rows[index].fromText) + [reading]
        rows[index].fromText = DictionaryEditing.joinList(DictionaryEditing.parseList(DictionaryEditing.joinList(list)))
        suggestions[id]?.removeAll { $0 == reading }
        isDirty = true
    }
}

/// 辞書の編集の窓
final class DictionaryWindow {
    private let store: DictionaryStore
    private var window: NSWindow?

    init(store: DictionaryStore) {
        self.store = store
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let model = DictionaryEditorModel(store: store)
        let window = NSWindow(contentViewController: NSHostingController(rootView: DictionaryEditorView(model: model)))
        window.title = "Tsuzuri の辞書"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 860, height: 620))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct DictionaryEditorView: View {
    @Bindable var model: DictionaryEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            quickAddBar
            Divider()
            HStack {
                TextField("語・聞き違いで絞り込む", text: $model.filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Picker("並べ方", selection: $model.order) {
                    Text("足した順").tag(DictionaryEditorModel.Order.recent)
                    Text("ファイルの順").tag(DictionaryEditorModel.Order.file)
                }
                .fixedSize()
                Toggle("詳しい設定を表示", isOn: $model.showsDetails)
                Spacer()
                Button("選んだ語を消す") { model.deleteSelected() }
                    .disabled(model.selection.isEmpty)
            }
            Table(model.visibleRows, selection: $model.selection) {
                TableColumn("語(正しい表記)") { row in
                    HStack(spacing: 6) {
                        TextField("語", text: model.binding(row.id, \.surface))
                        if row.source == .auto {
                            Text("候補から")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .background(Capsule().strokeBorder(.secondary.opacity(0.5)))
                                .fixedSize()
                        }
                    }
                }
                .width(min: 160, ideal: 220)
                TableColumn("聞き違い・読み(この字で出たら直す。「、」で区切る)") { row in
                    TextField("", text: model.binding(row.id, \.fromText))
                }
                .width(min: 260, ideal: 400)
                TableColumn(model.showsDetails ? "認識に渡す" : "") { row in
                    if model.showsDetails {
                        Toggle("", isOn: model.binding(row.id, \.hint)).labelsHidden()
                            .help("Soniox と Mac 内の認識に、この語をヒントとして渡す")
                    }
                }
                .width(model.showsDetails ? 70 : 0)
                TableColumn(model.showsDetails ? "いつも渡す" : "") { row in
                    if model.showsDetails {
                        Toggle("", isOn: model.binding(row.id, \.pinned)).labelsHidden()
                            .help("使われた回数に関係なく、毎回ヒントに入れる")
                    }
                }
                .width(model.showsDetails ? 70 : 0)
            }
            suggestionBar
            HStack {
                Text("つなぎ言葉")
                TextField("えー、えーと、あのー", text: model.fillersBinding)
                    .textFieldStyle(.roundedBorder)
            }
            issueList
            HStack {
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("読み直す") { model.reload() }
                Button("保存") { model.save() }
                    .keyboardShortcut("s")
                    .disabled(!model.canSave)
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 480)
    }

    /// 窓の上の1行の欄。語を打って Return で足し、その場で保存する。聞き違い・読みは任意
    private var quickAddBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("語を足す(正しい表記。例: Claude Code)", text: $model.quickSurface)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                    .onSubmit { model.quickAdd() }
                TextField("聞き違い・読み(任意。例: クロードコード)", text: $model.quickMisheard)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                    .onSubmit { model.quickAdd() }
                Button("足す") { model.quickAdd() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.quickSurface.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                Button(model.quickSuggesting ? "提案を待っています…" : "読みを提案") { model.suggestQuickReadings() }
                    .disabled(!ReadingSuggester.isAvailable || model.quickSuggesting || model.quickSurface.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Apple Intelligence に、カタカナの読みの候補を出させます。誤った読みも出るので、合うものだけ押してください")
                ForEach(model.quickSuggestions, id: \.self) { reading in
                    Button("+ \(reading)") { model.acceptQuick(reading) }
                        .buttonStyle(.bordered)
                }
                if model.quickSuggestions.isEmpty {
                    Text("語だけで足せます。カタカナなどに化けて出る語は、聞き違い・読みも足すと、その字で出たときに直して貼ります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 表で選んだ語の読みの提案。候補を押すと聞き違い・読みに足す
    @ViewBuilder private var suggestionBar: some View {
        if let row = model.selectedRow {
            HStack(spacing: 8) {
                Button(model.suggesting == row.id ? "提案を待っています…" : "選んだ語「\(row.surface)」の読みを提案") {
                    model.suggestReadings(for: row)
                }
                .disabled(!ReadingSuggester.isAvailable || model.suggesting != nil || row.surface.isEmpty)
                .help("Apple Intelligence に、カタカナの読みの候補を出させます。誤った読みも出るので、合うものだけ選んでください")
                ForEach(model.suggestions[row.id] ?? [], id: \.self) { reading in
                    Button("+ \(reading)") { model.accept(reading, for: row.id) }
                        .buttonStyle(.bordered)
                }
                if !ReadingSuggester.isAvailable {
                    Text("Apple Intelligence が無効なので、読みの提案は使えません").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var issueList: some View {
        let issues = model.issues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(issues.prefix(5).enumerated()), id: \.offset) { _, issue in
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(issue.blocksSaving ? .red : .orange)
                }
                if issues.count > 5 {
                    Text("ほか \(issues.count - 5) 件").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension DictionaryWindow {
    /// 動作の確かめ用。辞書の窓を本物の窓に出し、中身を PNG に写し取る(詳しい設定を出さない形と出す形)
    static func render(store: DictionaryStore, to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for details in [false, true] {
            let model = DictionaryEditorModel(store: store)
            model.showsDetails = details
            let window = NSWindow(contentViewController: NSHostingController(rootView: DictionaryEditorView(model: model)))
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 860, height: 620))
            window.center()
            window.orderFront(nil)
            try? await Task.sleep(for: .milliseconds(900))
            if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "dictionary-\(details ? "details" : "simple").png"))
            }
            window.close()
        }
    }
}
