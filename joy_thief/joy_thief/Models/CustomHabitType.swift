import Foundation

// MARK: - Custom Habit Type Models

struct CustomHabitType: Identifiable, Codable, Equatable {
    let id: String
    let typeIdentifier: String
    let description: String
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case typeIdentifier = "type_identifier"
        case description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    var displayName: String {
        typeIdentifier.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    var habitTypeValue: String {
        "custom_\(typeIdentifier)"
    }
    
    static func == (lhs: CustomHabitType, rhs: CustomHabitType) -> Bool {
        return lhs.id == rhs.id
    }
}

struct CustomHabitTypeCreate: Codable {
    let typeIdentifier: String
    let description: String
    
    enum CodingKeys: String, CodingKey {
        case typeIdentifier = "type_identifier"
        case description
    }
}

struct AvailableHabitTypes: Codable {
    let builtInTypes: [BuiltInHabitType]
    let customTypes: [AvailableCustomHabitType]
    let totalAvailable: Int
    
    enum CodingKeys: String, CodingKey {
        case builtInTypes = "built_in_types"
        case customTypes = "custom_types"
        case totalAvailable = "total_available"
    }
}

struct BuiltInHabitType: Codable, Identifiable {
    let type: String
    let displayName: String
    let description: String
    let isCustom: Bool
    
    var id: String { type }
    
    enum CodingKeys: String, CodingKey {
        case type
        case displayName = "display_name"
        case description
        case isCustom = "is_custom"
    }
}

struct AvailableCustomHabitType: Codable, Identifiable {
    let type: String
    let displayName: String
    let description: String
    let isCustom: Bool
    
    var id: String { type }
    
    enum CodingKeys: String, CodingKey {
        case type
        case displayName = "display_name"
        case description
        case isCustom = "is_custom"
    }
}

enum CustomHabitError: Error, LocalizedError {
    case networkError
    case serverError(String)
    case validationError(String)
    case premiumRequired(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection error"
        case .serverError(let message):
            return message
        case .validationError(let message):
            return message
        case .premiumRequired(let message):
            return message
        }
    }
} 