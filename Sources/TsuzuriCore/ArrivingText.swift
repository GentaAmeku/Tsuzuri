import Foundation

/// 話している途中の文字を、届いた時刻ごとの切れ端で持つ。録音中の表示で、新しく出た字だけを浮かび上がらせるのに使う。
/// 前の文字と同じ頭はそのまま残し、変わった後ろだけを新しい切れ端にする(認識が後ろを言い直したときも、その分だけ動かす)
public struct ArrivingText: Equatable, Sendable {
    public struct Piece: Equatable, Sendable {
        public var text: String
        /// 届いた時刻(秒)。動き終えて落ち着いた字は nil
        public var arrival: Double?

        public init(text: String, arrival: Double?) {
            self.text = text
            self.arrival = arrival
        }
    }

    /// 表示の色を分けるための区切り。確定した字かどうかも持つ
    public struct Segment: Equatable, Sendable {
        public var text: String
        public var arrival: Double?
        public var isFinal: Bool

        public init(text: String, arrival: Double?, isFinal: Bool) {
            self.text = text
            self.arrival = arrival
            self.isFinal = isFinal
        }
    }

    public private(set) var pieces: [Piece] = []

    public init() {}

    public var text: String { pieces.map(\.text).joined() }

    /// 新しい全体の文字を受け取る。settleAfter 秒より前に届いた切れ端は、落ち着いたものとしてまとめる
    public mutating func update(to newText: String, at time: Double, settleAfter: Double) {
        let old = Array(text)
        let new = Array(newText)
        var common = 0
        while common < old.count, common < new.count, old[common] == new[common] {
            common += 1
        }
        var kept: [Piece] = []
        var remaining = common
        for piece in pieces where remaining > 0 {
            let count = piece.text.count
            if count <= remaining {
                kept.append(piece)
                remaining -= count
            } else {
                kept.append(Piece(text: String(piece.text.prefix(remaining)), arrival: piece.arrival))
                remaining = 0
            }
        }
        if common < new.count {
            kept.append(Piece(text: String(new[common...]), arrival: time))
        }
        pieces = Self.settle(kept, at: time, after: settleAfter)
    }

    /// 動いている字があるか
    public func isAnimating(at time: Double, duration: Double) -> Bool {
        pieces.contains { $0.arrival.map { time - $0 < duration } ?? false }
    }

    /// 先頭から finalLength 字を確定した字として、色を分ける区切りに切る
    public func segments(finalLength: Int) -> [Segment] {
        var result: [Segment] = []
        var offset = 0
        for piece in pieces {
            let count = piece.text.count
            let split = finalLength - offset
            if split <= 0 {
                result.append(Segment(text: piece.text, arrival: piece.arrival, isFinal: false))
            } else if split >= count {
                result.append(Segment(text: piece.text, arrival: piece.arrival, isFinal: true))
            } else {
                result.append(Segment(text: String(piece.text.prefix(split)), arrival: piece.arrival, isFinal: true))
                result.append(Segment(text: String(piece.text.dropFirst(split)), arrival: piece.arrival, isFinal: false))
            }
            offset += count
        }
        return result
    }

    /// 落ち着いた切れ端の時刻を消し、同じ時刻の切れ端どうしをつなぐ
    private static func settle(_ pieces: [Piece], at time: Double, after: Double) -> [Piece] {
        var merged: [Piece] = []
        for var piece in pieces where !piece.text.isEmpty {
            if let arrival = piece.arrival, time - arrival >= after {
                piece.arrival = nil
            }
            if let last = merged.last, last.arrival == piece.arrival {
                merged[merged.count - 1].text += piece.text
            } else {
                merged.append(piece)
            }
        }
        return merged
    }
}
