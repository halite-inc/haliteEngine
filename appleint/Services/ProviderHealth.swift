import Foundation

public enum ProviderHealth: String, Sendable {
    case unconfigured = "Not configured"
    case checking = "Checking"
    case ready = "Ready"
    case unreachable = "Unreachable"
}

actor ProviderHealthService {
    private let networkSession: URLSession

    init(networkSession: URLSession = .shared) {
        self.networkSession = networkSession
    }

    func lmStudioHealth(baseURL: String) async -> ProviderHealth {
        let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(normalized)/models") else { return .unreachable }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await networkSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            return (200..<300).contains(http.statusCode) ? .ready : .unreachable
        } catch { return .unreachable }
    }

    func mlxHealth(baseURL: String) async -> ProviderHealth {
        let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(normalized)/models") else { return .unreachable }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await networkSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            return (200..<300).contains(http.statusCode) ? .ready : .unreachable
        } catch { return .unreachable }
    }
}
