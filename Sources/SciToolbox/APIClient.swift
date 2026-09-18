import Foundation

// MARK: - APIClient

/// Unified HTTP client with timeout, retry (exponential backoff for timeout/429), and error mapping.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let session: URLSession
    private let defaultTimeout: TimeInterval = 15
    private let maxRetries = 2

    /// Per-host rate limiter (e.g. NCBI requires ≤1 req / 3s)
    private let throttle = RequestThrottle()

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15   // 15s per-request timeout
        config.timeoutIntervalForResource = 20   // 20s total resource timeout
        // P3-8：User-Agent 从 bundle 读版本号，不再写死 1.0
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        config.httpAdditionalHeaders = [
            "User-Agent": "SciToolbox/\(version) (macOS)"
        ]
        config.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: config)
    }

    /// Whether disk caching is enabled (user-configurable via Settings).
    private var cacheEnabled: Bool {
        UserDefaults.standard.object(forKey: "cacheEnabled") as? Bool ?? true
    }

    // MARK: - JSON GET

    func getJSON(_ urlString: String, accept: String = "application/json,*/*") async throws -> JSON {
        let data = try await getRaw(urlString, accept: accept)
        guard let json = JSON(data) else { throw APIError.parse("invalid JSON") }
        return json
    }

    // MARK: - JSON POST

    func postJSON(_ urlString: String, body: [String: Any], accept: String = "application/json") async throws -> JSON {
        let url = try makeURL(urlString)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(req)
        guard let json = JSON(data) else { throw APIError.parse("invalid JSON") }
        return json
    }

    // MARK: - Text GET (for APIs like KEGG that return plain text)

    func getText(_ urlString: String) async throws -> String {
        let data = try await getRaw(urlString, accept: "text/plain,*/*")
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Raw GET

    func getRaw(_ urlString: String, accept: String = "*/*") async throws -> Data {
        let url = try makeURL(urlString)
        var req = URLRequest(url: url)
        req.setValue(accept, forHTTPHeaderField: "Accept")
        return try await perform(req)
    }

    // MARK: - Core request with retry

    private func perform(_ request: URLRequest, attempt: Int = 0) async throws -> Data {
        // 磁盘缓存键：URL + 方法 + Accept（P3-4：同 URL 不同表示不再互相污染）
        let cacheKey = cacheKeyFor(request)
        // Disk cache: check for GET requests when caching is enabled (async read — C12 fix)
        if request.httpMethod == "GET", cacheEnabled,
           let urlString = request.url?.absoluteString,
           let cached = await ResponseCache.shared.get(cacheKey) {
            // F20：通知 UI「来自缓存」，让用户感知数据新鲜度
            NotificationCenter.default.post(name: .cacheHit, object: nil, userInfo: ["url": urlString])
            return cached
        }

        // NCBI rate limiting: enforce 3s minimum interval between requests
        if let host = request.url?.host, host.contains("eutils.ncbi.nlm.nih.gov") {
            // F19：等待期间通知 UI 显示「遵守 NCBI 限速」提示，避免误判卡死
            NotificationCenter.default.post(name: .throttleWaiting, object: nil, userInfo: ["host": host])
            await throttle.waitIfNeeded(host: host, minInterval: 3.0)
            NotificationCenter.default.post(name: .throttleResumed, object: nil, userInfo: ["host": host])
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.network("invalid response")
            }
            if http.statusCode == 429 || http.statusCode >= 500 {
                if attempt < maxRetries {
                    let delay = retryDelay(for: http, attempt: attempt)
                    try? await Task.sleep(nanoseconds: delay)
                    return try await perform(request, attempt: attempt + 1)
                }
                throw APIError.http(http.statusCode)
            }
            if !(200...299).contains(http.statusCode) {
                throw APIError.http(http.statusCode)
            }
            // Write successful GET responses to disk cache (async write)
            if request.httpMethod == "GET", cacheEnabled {
                await ResponseCache.shared.set(cacheKey, data: data)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            // Timeout or network error - retry
            let isTimeout = (error as NSError).code == NSURLErrorTimedOut
            if isTimeout && attempt < maxRetries {
                let delay = UInt64(pow(2.0, Double(attempt))) * 500_000_000 // 0.5s, 1s, 2s
                try? await Task.sleep(nanoseconds: delay)
                return try await perform(request, attempt: attempt + 1)
            }
            if isTimeout { throw APIError.timeout }
            throw APIError.network(error.localizedDescription)
        }
    }

    /// 缓存键 = 方法 + URL + Accept（P3-4）。
    private func cacheKeyFor(_ request: URLRequest) -> String {
        let url = request.url?.absoluteString ?? ""
        let accept = request.value(forHTTPHeaderField: "Accept") ?? ""
        return "\(request.httpMethod ?? "GET") \(url) \(accept)"
    }

    /// Computes retry delay based on HTTP status code and attempt number.
    /// - 429: respects `Retry-After` header (seconds or HTTP date) if present
    /// - 5xx: 1s, 2s, 4s (less aggressive than timeout)
    /// - 429 without Retry-After: 0.5s, 1s, 2s
    private func retryDelay(for response: HTTPURLResponse, attempt: Int) -> UInt64 {
        // 429: respect Retry-After header if present
        if response.statusCode == 429,
           let retryAfter = response.value(forHTTPHeaderField: "Retry-After") {
            // Numeric seconds
            if let seconds = Double(retryAfter) {
                return UInt64(seconds * 1_000_000_000)
            }
            // HTTP date format
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: retryAfter) {
                return UInt64(max(0, date.timeIntervalSinceNow) * 1_000_000_000)
            }
        }
        // 5xx: start at 1s, double each retry (1s, 2s, 4s)
        if response.statusCode >= 500 {
            return UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
        }
        // 429 without Retry-After: 0.5s, 1s, 2s
        return UInt64(pow(2.0, Double(attempt))) * 500_000_000
    }

    private func makeURL(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString) else { throw APIError.invalidInput("invalid URL") }
        return url
    }
}

// MARK: - URL Builder helper

func buildQueryURL(_ base: String, params: [String: String]) -> String {
    var components = URLComponents(string: base)!
    components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
    return components.url?.absoluteString ?? base
}

/// Percent-encodes a string for use in a URL path component.
/// Shared helper — replaces the duplicate `encoded()` methods scattered across providers.
func urlEncodePath(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
}

// MARK: - 全局通知（网络层 → UI）

extension Notification.Name {
    /// 磁盘缓存命中（F20）：userInfo["url"]。
    static let cacheHit = Notification.Name("scitoolbox.cacheHit")
    /// NCBI 节流开始等待（F19）：userInfo["host"]。
    static let throttleWaiting = Notification.Name("scitoolbox.throttleWaiting")
    /// NCBI 节流等待结束。
    static let throttleResumed = Notification.Name("scitoolbox.throttleResumed")
}

// MARK: - Request Throttle (per-host rate limiter)

/// Thread-safe per-host rate limiter using Swift actor.
/// Ensures NCBI E-utilities (and other rate-limited APIs) respect
/// minimum intervals between consecutive requests.
actor RequestThrottle {
    /// Last request timestamp per host
    private var lastRequestTime: [String: Date] = [:]

    /// Waits if the minimum interval hasn't elapsed since the last request to this host.
    func waitIfNeeded(host: String, minInterval: TimeInterval) async {
        let now = Date()
        if let last = lastRequestTime[host] {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < minInterval {
                let wait = minInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        lastRequestTime[host] = Date()
    }
}
