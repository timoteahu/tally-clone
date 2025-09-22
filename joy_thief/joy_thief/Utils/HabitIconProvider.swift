import SwiftUI

/// Provides the correct image name for each habit type and icon variant (filled vs. outline).
///
/// All images are stored in the `joy_thief/joy_thief/Images` folder and are added to the
/// Xcode project as resources.  The file names follow this convention:
///   • Filled icons: "<habit>.png"  (e.g. "gym.png")
///   • Outline icons: "<habit> outline.png"  (e.g. "gym outline.png")
///
/// When referencing images in SwiftUI, omit the file extension so that Swift can load the
/// resource regardless of scale (1×/2×/3×) and compression format.  Therefore the provider
/// returns the base name without the `.png` suffix.
enum HabitIconVariant {
    case filled
    case outline
}

struct HabitIconProvider {
    /// Returns the appropriate image asset name for the given habit type.
    ///
    /// - Parameters:
    ///   - habitType: The canonical habit type string (e.g. "gym", "alarm").  If the string
    ///     starts with the `custom_` prefix, the custom placeholder icon will be returned.
    ///   - variant:  Whether to return the filled or outline version of the icon.
    /// - Returns:    The image asset name without file extension.
    static func iconName(for habitType: String, variant: HabitIconVariant = .filled) -> String {
        // Strip the `custom_` prefix for custom habits so that both variants map to "custom".
        let normalizedType: String
        if habitType.hasPrefix("custom_") {
            normalizedType = "custom"
        } else {
            normalizedType = habitType
        }

        let base: String
        switch normalizedType {
        case "gym":       base = "gym"
        case "alarm":     base = "alarm"
        case "yoga":      base = "yoga"
        case "outdoors":  base = "outdoors"
        case "cycling":   base = "cycling"
        case "cooking":   base = "cooking"
        case "league_of_legends": base = "gaming"
        case "valorant":  base = "gaming"
        // Apple Health habit types - use SF Symbols for health data
        case "health_steps": base = "figure.walk"
        case "health_walking_running_distance": base = "figure.run"
        case "health_flights_climbed": base = "figure.stairs"
        case "health_exercise_minutes": base = "heart.circle"
        case "health_cycling_distance": base = "bicycle"
        case "health_sleep_hours": base = "bed.double"
        case "health_calories_burned": base = "flame"
        case "health_mindful_minutes": base = "brain.head.profile"
        case "github_commits": base = "github"
        case "leetcode": base = "github"  // LeetCode uses GitHub icon
        default:           base = "custom"  // fallback image
        }

        // For SF Symbols (health types and some others), return the base name directly
        if isSystemIcon(base) {
            return base
        }

        switch variant {
        case .filled:   return base
        case .outline:  return "\(base) outline"
        }
    }
    
    /// Check if the icon is a system SF Symbol rather than a custom asset
    static func isSystemIcon(_ iconName: String) -> Bool {
        let systemIcons = [
            "figure.walk", "figure.run", "figure.stairs", "heart.circle", "bicycle",
            "bed.double", "flame", "brain.head.profile", 
            "chevron.left.slash.chevron.right"
        ]
        return systemIcons.contains(iconName)
    }
} 