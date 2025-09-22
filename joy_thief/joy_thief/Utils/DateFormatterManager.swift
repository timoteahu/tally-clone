import Foundation

/// Singleton manager for efficient date formatting throughout the app
final class DateFormatterManager {
    static let shared = DateFormatterManager()
    
    // MARK: - Cached Formatters
    
    /// ISO8601 formatter for API dates
    private(set) lazy var iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// Fallback ISO8601 formatter without fractional seconds
    private(set) lazy var iso8601FormatterNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    /// Comment date formatter (MMM d, h:mm a)
    private(set) lazy var commentDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// Day of week formatter
    private(set) lazy var dayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// Header date formatter (MMMM d)
    private(set) lazy var headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// Time formatter (h:mm a)
    private(set) lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// Short date formatter (M/d)
    private(set) lazy var shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// Relative date formatter for user-friendly dates
    private(set) lazy var relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter
    }()
    
    // MARK: - Date Parsing Cache
    
    private let dateCache = NSCache<NSString, NSDate>()
    
    private init() {
        // Configure cache
        dateCache.countLimit = 1000 // Limit to 1000 cached dates
    }
    
    // MARK: - Parsing Methods
    
    /// Parse ISO8601 date string with caching
    func parseISO8601Date(_ string: String) -> Date? {
        // Check cache first
        if let cachedDate = dateCache.object(forKey: string as NSString) {
            return cachedDate as Date
        }
        
        // Try primary formatter with fractional seconds
        if let date = iso8601Formatter.date(from: string) {
            dateCache.setObject(date as NSDate, forKey: string as NSString)
            return date
        }
        
        // Try without fractional seconds
        if let date = iso8601FormatterNoFractional.date(from: string) {
            dateCache.setObject(date as NSDate, forKey: string as NSString)
            return date
        }
        
        // Try converting +00:00 to Z format and parse again
        let normalizedString = string.replacingOccurrences(of: "+00:00", with: "Z")
        if normalizedString != string {
            if let date = iso8601Formatter.date(from: normalizedString) {
                dateCache.setObject(date as NSDate, forKey: string as NSString)
                return date
            }
            
            if let date = iso8601FormatterNoFractional.date(from: normalizedString) {
                dateCache.setObject(date as NSDate, forKey: string as NSString)
                return date
            }
        }
        
        return nil
    }
    
    /// Clear the date cache (useful for memory pressure situations)
    func clearDateCache() {
        dateCache.removeAllObjects()
    }
}

// MARK: - Convenience Extensions

extension Date {
    /// Format for comments
    var formattedForComment: String {
        DateFormatterManager.shared.commentDateFormatter.string(from: self)
    }
    
    /// Format day of week
    var dayOfWeek: String {
        DateFormatterManager.shared.dayOfWeekFormatter.string(from: self)
    }
    
    /// Format for headers
    var formattedHeader: String {
        DateFormatterManager.shared.headerDateFormatter.string(from: self)
    }
    
    /// Format time only
    var formattedTime: String {
        DateFormatterManager.shared.timeFormatter.string(from: self)
    }
    
    /// Format short date
    var formattedShort: String {
        DateFormatterManager.shared.shortDateFormatter.string(from: self)
    }
    
    /// Format relative to now
    var formattedRelative: String {
        DateFormatterManager.shared.relativeDateFormatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - JSON Decoding Strategy

extension JSONDecoder {
    /// Configure decoder with optimized date decoding
    static func configuredForAPI() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = DateFormatterManager.shared.parseISO8601Date(dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateString)"
            )
        }
        return decoder
    }
}