import Foundation

struct LMStudioModelSnapshot: Sendable {
    let models: [String]
    let contextLengths: [String: Int]
}

/// Owns model discovery independently of SwiftUI rendering. Requests for the
/// same endpoint share one network task, and successful results are cached for
/// a short period so context badges cannot cause request storms.
actor ModelDiscoveryService {
    private struct CachedSnapshot {
        let value: LMStudioModelSnapshot
        let expiry: Date
    }

    private var cache: [String: CachedSnapshot] = [:]
    private var inFlight: [String: Task<LMStudioModelSnapshot?, Never>] = [:]
    private let cacheLifetime: TimeInterval = 30
    private let networkSession: URLSession

    init(networkSession: URLSession? = nil) {
        if let networkSession {
            self.networkSession = networkSession
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4.0
            config.timeoutIntervalForResource = 6.0
            self.networkSession = URLSession(configuration: config)
        }
    }

    func discover(baseURL: String, force: Bool = false) async -> LMStudioModelSnapshot? {
        let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty else { return nil }
        if !force, let cached = cache[normalized], cached.expiry > Date() {
            return cached.value
        }
        if let task = inFlight[normalized] { return await task.value }

        let networkSession = self.networkSession
        let task = Task { await Self.fetch(baseURL: normalized, networkSession: networkSession) }
        inFlight[normalized] = task
        let result = await task.value
        inFlight[normalized] = nil
        if let result {
            cache[normalized] = CachedSnapshot(value: result, expiry: Date().addingTimeInterval(cacheLifetime))
        }
        return result
    }

    private static func fetch(baseURL: String, networkSession: URLSession) async -> LMStudioModelSnapshot? {
        guard let url = URL(string: "\(baseURL)/models") else { return nil }
        do {
            let (data, response) = try await networkSession.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["data"] as? [[String: Any]] else { return nil }

            let models = items.compactMap { $0["id"] as? String }
            var contexts: [String: Int] = [:]
            for item in items {
                guard let id = item["id"] as? String else { continue }
                if let length = contextLength(in: item) { contexts[id] = length }
            }
            for id in models where contexts[id] == nil {
                guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let detailURL = URL(string: "\(baseURL)/models/\(encoded)"),
                      let (detailData, detailResponse) = try? await networkSession.data(from: detailURL),
                      let http = detailResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let detail = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                      let length = contextLength(in: detail) else { continue }
                contexts[id] = length
            }
            return LMStudioModelSnapshot(models: models, contextLengths: contexts)
        } catch {
            return nil
        }
    }

    private static func contextLength(in item: [String: Any]) -> Int? {
        let keys = ["context_length", "contextLength", "max_context_length", "maxContextLength"]
        for key in keys {
            if let value = item[key] as? Int { return value }
            if let value = item[key] as? Double { return Int(value) }
        }
        return nil
    }
}
