import Foundation

/// Intelligent error classification for different handling strategies
enum NetworkErrorType {
    case transient(retryAfter: TimeInterval?)
    case authentication(requiresReauth: Bool)
    case permanent(reason: String)
    case rateLimit(retryAfter: TimeInterval)
    case maintenance(estimatedDuration: TimeInterval?)
    
    var shouldRetry: Bool {
        switch self {
        case .transient, .rateLimit, .maintenance:
            return true
        case .authentication, .permanent:
            return false
        }
    }
    
    var retryDelay: TimeInterval {
        switch self {
        case .transient(let retryAfter):
            return retryAfter ?? 30.0 // Default 30 seconds
        case .rateLimit(let retryAfter):
            return retryAfter
        case .maintenance(let estimatedDuration):
            return estimatedDuration ?? 300.0 // Default 5 minutes
        case .authentication, .permanent:
            return 0
        }
    }
    
    var userMessage: String {
        switch self {
        case .transient:
            return "Connection issue. We'll try again automatically."
        case .authentication:
            return "Please log in again to continue."
        case .permanent(let reason):
            return "Unable to load friends: \(reason)"
        case .rateLimit:
            return "Too many requests. Please wait a moment."
        case .maintenance:
            return "Service temporarily unavailable. We'll try again soon."
        }
    }
}

/// Classifies network errors for intelligent handling
class NetworkErrorClassifier {
    
    /// Classify an error into appropriate handling category
    static func classify(_ error: Error) -> NetworkErrorType {
        // Handle URLSession errors
        if let urlError = error as? URLError {
            return classifyURLError(urlError)
        }
        
        // Handle HTTP response errors
        if let httpError = error as? HTTPError {
            return classifyHTTPError(httpError)
        }
        
        // Handle custom app errors
        if let friendError = error as? FriendDataError {
            return classifyFriendDataError(friendError)
        }
        
        // Default to transient for unknown errors
        return .transient(retryAfter: 60.0)
    }
    
    // MARK: - Private Classification Methods
    
    private static func classifyURLError(_ error: URLError) -> NetworkErrorType {
        switch error.code {
        // Network connectivity issues - transient
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
            return .transient(retryAfter: 30.0)
            
        // Timeout issues - transient with longer retry
        case .timedOut:
            return .transient(retryAfter: 60.0)
            
        // DNS/host issues - transient
        case .cannotFindHost, .dnsLookupFailed:
            return .transient(retryAfter: 120.0)
            
        // Certificate/security issues - permanent
        case .serverCertificateUntrusted, .clientCertificateRejected:
            return .permanent(reason: "Security certificate error")
            
        // Bad URL - permanent
        case .badURL, .unsupportedURL:
            return .permanent(reason: "Invalid request")
            
        // Resource unavailable - could be maintenance
        case .resourceUnavailable:
            return .maintenance(estimatedDuration: 300.0)
            
        default:
            return .transient(retryAfter: 60.0)
        }
    }
    
    private static func classifyHTTPError(_ error: HTTPError) -> NetworkErrorType {
        switch error.statusCode {
        // Authentication errors
        case 401:
            return .authentication(requiresReauth: true)
        case 403:
            return .authentication(requiresReauth: false)
            
        // Rate limiting
        case 429:
            let retryAfter = error.retryAfter ?? 60.0
            return .rateLimit(retryAfter: retryAfter)
            
        // Server errors - transient
        case 500...599:
            return .transient(retryAfter: 120.0)
            
        // Service unavailable - maintenance
        case 503:
            let retryAfter = error.retryAfter ?? 300.0
            return .maintenance(estimatedDuration: retryAfter)
            
        // Client errors - permanent
        case 400...499:
            return .permanent(reason: "Request error (\(error.statusCode))")
            
        default:
            return .transient(retryAfter: 60.0)
        }
    }
    
    private static func classifyFriendDataError(_ error: FriendDataError) -> NetworkErrorType {
        switch error {
        case .invalidURL:
            return .permanent(reason: "Configuration error")
        case .networkError:
            return .transient(retryAfter: 30.0)
        case .serverError(_):
            return .transient(retryAfter: 60.0)
        }
    }
}

/// HTTP error with additional metadata
struct HTTPError: Error {
    let statusCode: Int
    let retryAfter: TimeInterval?
    let message: String?
    
    init(statusCode: Int, retryAfter: TimeInterval? = nil, message: String? = nil) {
        self.statusCode = statusCode
        self.retryAfter = retryAfter
        self.message = message
    }
} 