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

    var rows: [Row] = []
    var fillersText = ""
    var filter = ""
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
        guard !keyword.isEmpty else { return rows }
        return rows.filter { $0.surface.lowercased().contains(keyword) || $0.fromText.lowercased().contains(keyword) }
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

    func addRow() {
        let row = Row(surface: "", fromText: "", hint: true, pinned: false, source: .manual)
        rows.insert(row, at: 0)
        filter = ""
        selection = [row.id]
        isDirty = true
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
            HStack {
                TextField("表記・置き換え元で絞り込む", text: $model.filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Button("語を足す") { model.addRow() }
                Button("選んだ語を消す") { model.deleteSelected() }
                    .disabled(model.selection.isEmpty)
            }
            Table(model.visibleRows, selection: $model.selection) {
                TableColumn("表記") { row in
                    TextField("表記", text: model.binding(row.id, \.surface))
                }
                .width(min: 140, ideal: 180)
                TableColumn("置き換え元(「、」で区切る)") { row in
                    TextField("聞き違いを足す", text: model.binding(row.id, \.fromText))
                }
                .width(min: 240, ideal: 360)
                TableColumn("ヒント") { row in
                    Toggle("", isOn: model.binding(row.id, \.hint)).labelsHidden()
                }
                .width(50)
                TableColumn("固定") { row in
                    Toggle("", isOn: model.binding(row.id, \.pinned)).labelsHidden()
                }
                .width(50)
                TableColumn("足し方") { row in
                    Text(row.source == .auto ? "自動" : "手で").foregroundStyle(.secondary)
                }
                .width(50)
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

    /// 選んだ語の読みの提案。候補を押すと置き換え元に足す
    @ViewBuilder private var suggestionBar: some View {
        if let row = model.selectedRow {
            HStack(spacing: 8) {
                Button(model.suggesting == row.id ? "提案を待っています…" : "読みを提案") {
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
