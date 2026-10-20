@preconcurrency import AVFoundation
import Foundation

public enum AudioFileError: Error, CustomStringConvertible {
    case unreadable(URL, underlying: any Error)
    case conversionFailed(URL)
    case unwritable(URL, underlying: any Error)

    public var description: String {
        switch self {
        case let .unreadable(url, underlying): "音声を読めません: \(url.path) (\(underlying.localizedDescription))"
        case let .conversionFailed(url): "16kHz・モノラルに変換できません: \(url.path)"
        case let .unwritable(url, underlying): "音声を書けません: \(url.path) (\(underlying.localizedDescription))"
        }
    }
}

/// 音声ファイルの読み書き。中では 16kHz・モノラル・Float32 の標本列で扱う
public enum AudioFile {
    public static let sampleRate: Double = 16_000

    public static let processingFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    public static func readSamples(from url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioFileError.unreadable(url, underlying: error)
        }
        guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioFileError.conversionFailed(url)
        }
        do {
            try file.read(into: source)
        } catch {
            throw AudioFileError.unreadable(url, underlying: error)
        }
        guard let converted = convert(source, to: processingFormat) else {
            throw AudioFileError.conversionFailed(url)
        }
        return samples(of: converted)
    }

    /// 音声の長さ(秒)
    public static func duration(of url: URL) throws -> Double {
        do {
            let file = try AVAudioFile(forReading: url)
            return Double(file.length) / file.fileFormat.sampleRate
        } catch {
            throw AudioFileError.unreadable(url, underlying: error)
        }
    }

    /// 16kHz・モノラルの標本列を、16bit の WAV として書く
    public static func writeWAV(samples: [Float], to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer(of: samples))
        } catch {
            throw AudioFileError.unwritable(url, underlying: error)
        }
    }

    /// Soniox に送る、16bit リトルエンディアンの PCM
    public static func pcm16LittleEndian(_ samples: [Float]) -> Data {
        let values = samples.map { Int16((max(-1, min(1, $0)) * Float(Int16.max)).rounded()).littleEndian }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// 1つのバッファを、まとめて別の形式に変換する(ファイルを読むとき用)
    static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format {
            return buffer
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        let state = ConversionInput(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            state.next(inputStatus)
        }
        return status == .error || error != nil ? nil : output
    }

    static func samples(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }

    static func buffer(of samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                buffer.floatChannelData![0].update(from: base, count: samples.count)
            }
        }
        return buffer
    }
}

/// AVAudioConverter に、1つのバッファを1回だけ渡す
final class ConversionInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var delivered = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if delivered {
            status.pointee = .endOfStream
            return nil
        }
        delivered = true
        status.pointee = .haveData
        return buffer
    }
}
