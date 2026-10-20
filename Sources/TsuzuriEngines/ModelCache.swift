import Foundation

/// Mac 内の認識のモデルの置き場所。iCloud で同期されない ~/Library/Caches/Tsuzuri/models に置く
public enum ModelCache {
    public static func directory() throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = caches.appending(path: "Tsuzuri/models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
