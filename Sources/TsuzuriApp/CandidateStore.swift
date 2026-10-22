import Foundation
import Observation
import TsuzuriCore
import TsuzuriEngines

/// 辞書の候補(`candidates.json`)。貼り付けのあとに裏で洗い出し、本人が候補の窓で入れるか捨てるかを選ぶ
/// (設計書「辞書の候補の洗い出し」)。洗い出しは Mac の中で終わり、外へは何も送らない
@Observable
final class CandidateStore {
    private(set) var file = CandidatesFile()
    /// Apple Intelligence が無効などで、洗い出しを止めているか
    private(set) var isUnavailable = !SuspectScanner.isAvailable
    /// 最後の失敗(候補の窓に出す)
    private(set) var lastError: String?

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let dictionary: DictionaryStore
    /// 洗い出しを1つずつ順に行うための、前の洗い出し
    @ObservationIgnored private var queue: Task<Void, Never>?

    init(directory: URL, dictionary: DictionaryStore) {
        url = directory.appending(path: "candidates.json")
        self.dictionary = dictionary
        if let data = try? Data(contentsOf: url), let loaded = try? Self.decoder.decode(CandidatesFile.self, from: data) {
            file = loaded
        }
    }

    var items: [StoredCandidate] { CandidateBook.ordered(file.items) }

    /// 貼った文を裏で洗い出し、候補に貯める。貼り付けは待たせない
    func scan(_ text: String, app: String?) {
        isUnavailable = !SuspectScanner.isAvailable
        guard !isUnavailable else { return }
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            await self?.runScan(text, app: app)
        }
    }

    private func runScan(_ text: String, app: String?) async {
        let entries = dictionary.dictionary.entries
        do {
            let candidates = try await SuspectScanner.candidates(for: text, dictionary: entries, settled: file.settled).candidates
            guard !candidates.isEmpty else { return }
            update(CandidateBook.merging(candidates, app: app, at: Date(), into: file))
        } catch {
            // 安全のための拒否などで答えないことがある。候補が出ないだけなので、知らせるだけにする
            lastError = "辞書の候補を調べられませんでした(\(error.localizedDescription))"
            NSLog("Tsuzuri: 洗い出しに失敗: \(error)")
        }
    }

    /// 捨てる。同じ組は二度出さない
    func discard(_ id: DiscardedPair) {
        update(CandidateBook.discarding(id, from: file))
    }

    /// 捨てた組を戻す
    func restore(_ id: DiscardedPair) {
        update(CandidateBook.restoring(id, from: file))
    }

    /// 辞書に入れる。辞書のファイルは書く直前に読み直し、手で直した中身を消さない
    func insert(_ item: StoredCandidate, surface: String, mode: InsertionMode) throws {
        dictionary.reloadIfChanged()
        let current = dictionary.dictionary
        if let entries = DictionaryInsertion.insert(heard: item.heard, surface: surface, mode: mode, into: current.entries) {
            try dictionary.save(entries: entries, fillers: current.fillers, base: dictionary.modificationDate)
        }
        update(CandidateBook.inserting(item.id, surface: surface, from: file))
    }

    private func update(_ next: CandidatesFile) {
        file = next
        lastError = nil
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(file).write(to: url, options: .atomic)
        } catch {
            NSLog("Tsuzuri: 辞書の候補を書けません: \(error)")
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
