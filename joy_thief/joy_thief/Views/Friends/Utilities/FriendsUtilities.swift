import Foundation

// MARK: - Activity Helper
extension FriendsView {
    static func getActivityDisplayText(from lastActive: String?) -> (text: String?, isActiveNow: Bool) {
        guard let lastActive = lastActive else {
            return (nil, false)
        }
        
        // Parse PostgreSQL timestamp format (e.g., "2025-07-17 07:57:01.416871+00")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        var parsedDate = dateFormatter.date(from: lastActive)
        
        // If that fails, try ISO 8601 format
        if parsedDate == nil {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            parsedDate = formatter.date(from: lastActive)
        }
        
        // If that fails, try without fractional seconds
        if parsedDate == nil {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            parsedDate = formatter.date(from: lastActive)
        }
        
        guard let date = parsedDate else {
            print("❌ Failed to parse date: \(lastActive)")
            return (nil, false)
        }
        
        let now = Date()
        let diff = now.timeIntervalSince(date)
        
        // Active now (within 5 minutes)
        if diff < 300 {
            return ("Active now", true)
        }
        
        // Calculate time units
        let minutes = Int(diff / 60)
        let hours = Int(diff / 3600)
        let days = Int(diff / 86400)
        
        // Format activity text
        if minutes < 60 {
            return ("Active \(minutes)m ago", false)
        } else if hours < 24 {
            return ("Active \(hours)h ago", false)
        } else if days == 1 {
            return ("Active yesterday", false)
        } else if days < 7 {
            return ("Active \(days)d ago", false)
        } else if days < 14 {
            return ("Active 1w ago", false)
        } else if days < 30 {
            let weeks = days / 7
            return ("Active \(weeks)w ago", false)
        } else {
            return ("Active 2+ weeks ago", false)
        }
    }
}

// MARK: - Common utility functions for Friends views
extension String {
    /// Generate initials from a name string (used across multiple Friend views)
    func initials() -> String {
        let components = self.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map { String($0) }
        return initials.joined().uppercased()
    }
} 