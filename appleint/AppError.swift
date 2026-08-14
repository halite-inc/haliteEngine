import Foundation

public enum AppError: LocalizedError, Sendable {
    case networkUnavailable(provider: Provider)
    case invalidCredential(provider: Provider)
    case quotaExceeded(provider: Provider)
    case localServerUnavailable
    case cancelled
    case malformedResponse(provider: Provider)
    case persistenceFailure(operation: String)

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable(let provider): return "\(provider.shortDisplayName) is unavailable. Check your connection and try again."
        case .invalidCredential(let provider): return "\(provider.shortDisplayName) rejected its API key. Update it in Configure APIs."
        case .quotaExceeded(let provider): return "\(provider.shortDisplayName) has no available quota. Check billing or choose another provider."
        case .localServerUnavailable: return "LM Studio is not responding. Start its local server, then refresh the connection."
        case .cancelled: return "The request was cancelled."
        case .malformedResponse(let provider): return "\(provider.shortDisplayName) returned an unreadable response. Please retry."
        case .persistenceFailure(let operation): return "AppleInt could not \(operation). Your in-memory work is still available; retry or export it before quitting."
        }
    }
}
