@preconcurrency import AVFoundation
import Foundation

/// マイクの音を 16kHz・モノラルに変換しながらためる。止めると、たまった標本列を返す。
/// `onSamples` を渡すと、変換したそばから音声の処理の糸で受け取れる(話しながら送るため)
public final class MicrophoneRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private let onSamples: (@Sendable ([Float]) -> Void)?

    public init(onSamples: (@Sendable ([Float]) -> Void)? = nil) {
        self.onSamples = onSamples
    }

    /// いまの既定の入力の機器の名前
    public static var currentInputName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "不明"
    }

    public static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: AudioFile.processingFormat) else {
            throw RecorderError.unsupportedFormat
        }
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, converter: converter)
        }
        engine.prepare()
        try engine.start()
    }

    public func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        let recorded = samples
        samples = []
        return recorded
    }

    /// 音量の目安(0〜1)。標本の二乗平均の平方根を、話し声が棒の中ほどに来るよう広げる
    public static func level(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        return min(1, rms * 8)
    }

    /// 音声の処理の糸で呼ばれる。変換器の内部の状態を保つため、渡し終えたら noDataNow を返す
    private func append(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        let format = AudioFile.processingFormat
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        let input = StreamingInput(buffer)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            input.next(status)
        }
        guard error == nil, let data = output.floatChannelData else { return }
        let chunk = Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
        onSamples?(chunk)
    }

    public enum RecorderError: Error, CustomStringConvertible {
        case unsupportedFormat

        public var description: String { "マイクの形式を 16kHz・モノラルに変換できません" }
    }
}

/// 1つのバッファを1回だけ渡し、続きは「まだ無い」と答える(録音は続くため終わりにしない)
private final class StreamingInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var delivered = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if delivered {
            status.pointee = .noDataNow
            return nil
        }
        delivered = true
        status.pointee = .haveData
        return buffer
    }
}
