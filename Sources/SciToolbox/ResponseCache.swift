import Foundation
import CryptoKit

// MARK: - Response Cache (disk-based, TTL, no user data)

/// Simple disk cache for API responses. Keyed by URL string.
/// Never stores any user/device identifiers — only "request URL → response data".
/// All reads are async to avoid blocking cooperative threads (C12 fix).
final class ResponseCache: @unchecked Sendable {
    static let shared = ResponseCache()

    private let directory: URL
    private let defaultTTL: TimeInterval = 2 * 60 * 60 // 2 hours
    private let queue = DispatchQueue(label: "com.scitoolbox.cache", qos: .utility)

    init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = cachesDir.appendingPathComponent("SciToolboxCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Async read — offloads disk IO to background queue (C12 fix).
    func get(_ key: String) async -> Data? {
        let file = path(for: key)
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                      let modified = attrs[.modificationDate] as? Date else {
                    continuation.resume(returning: nil)
                    return
                }
                let ttl = self.ttlFor(key)
                if Date().timeIntervalSince(modified) > ttl {
                    try? FileManager.default.removeItem(at: file)
                    continuation.resume(returning: nil)
                    return
                }
                let data = try? Data(contentsOf: file)
                continuation.resume(returning: data)
            }
        }
    }

    /// Async write — offloads disk IO to background queue.
    func set(_ key: String, data: Data) async {
        let file = path(for: key)
        await withCheckedContinuation { continuation in
            queue.async {
                try? data.write(to: file)
                continuation.resume()
            }
        }
    }

    func clear() {
        let dir = directory
        queue.async {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func path(for key: String) -> URL {
        // P3-5：改用 SHA256 十六进制摘要作文件名（base64 膨胀 4/3，长 URL 有接近 255 字节文件名的理论风险）
        let digest = SHA256.hash(data: Data(key.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".cache")
    }

    private func ttlFor(_ key: String) -> TimeInterval {
        // Longer TTL for stable data (GO, taxonomy), shorter for volatile
        if key.contains("search") { return 30 * 60 } // 30 min for search results
        return defaultTTL
    }
}
