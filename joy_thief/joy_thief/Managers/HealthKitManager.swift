import HealthKit
import Foundation

// Helper extension for better debugging
extension HKAuthorizationStatus: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .sharingDenied:
            return "sharingDenied"
        case .sharingAuthorized:
            return "sharingAuthorized"
        @unknown default:
            return "unknown(\(rawValue))"
        }
    }
}

@MainActor
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var isAuthorized = false
    
    static let shared = HealthKitManager()
    
    private init() {}
    
    // MARK: - Permission Management
    
    /// Request permission for specific health data type when creating a habit
    func requestPermission(for habitType: String) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            #if targetEnvironment(simulator)
            throw HealthKitError.notAvailable // iOS Simulator doesn't support HealthKit
            #else
            throw HealthKitError.notAvailable
            #endif
        }
        
        let dataTypes = getHealthDataTypes(for: habitType)
        guard !dataTypes.isEmpty else {
            throw HealthKitError.unsupportedHabitType
        }
        
        // Request permission only for the specific data types needed
        let readTypes = Set(dataTypes)
        let shareTypes: Set<HKSampleType> = [] // Empty set for sharing
        
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                print("HealthKit auth success:", success)
                if let err = error {
                    print("HealthKit auth error:", err.localizedDescription)
                }
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // If the authorization completed without error, consider it successful
                // Don't immediately check status as it can be unreliable due to HealthKit caching
                if success {
                    Task { @MainActor in
                        self.isAuthorized = true
                        self.authorizationStatus = .sharingAuthorized
                    }
                    continuation.resume(returning: ())
                } else {
                    // Only fail if the authorization request itself failed
                    continuation.resume(throwing: HealthKitError.permissionDenied)
                }
            }
        }
    }
    
    /// Check if we already have permission for a specific habit type
    func hasPermission(for habitType: String) -> Bool {
        let dataTypes = getHealthDataTypes(for: habitType)
        // Check that none are explicitly denied (more lenient approach)
        return !dataTypes.contains { type in
            healthStore.authorizationStatus(for: type) == .sharingDenied
        }
    }
    
    /// Test if we can actually read health data (more reliable than status check)
    func canReadHealthData(for habitType: String) async -> Bool {
        do {
            switch habitType {
            case "health_steps":
                _ = try await getTodaySteps()
                return true
            case "health_walking_running_distance":
                _ = try await getTodayWalkingRunningDistance()
                return true
            case "health_flights_climbed":
                _ = try await getTodayFlightsClimbed()
                return true
            case "health_exercise_minutes":
                _ = try await getTodayExerciseMinutes()
                return true
            case "health_cycling_distance":
                _ = try await getTodayCyclingDistance()
                return true
            case "health_sleep_hours":
                _ = try await getLastNightSleepHours()
                return true
            case "health_calories_burned":
                _ = try await getTodayCaloriesBurned()
                return true
            case "health_mindful_minutes":
                _ = try await getTodayMindfulMinutes()
                return true
            default:
                return false
            }
        } catch {
            print("❌ Cannot read health data for \(habitType): \(error)")
            return false
        }
    }
    
    /// Get required HealthKit data types for a habit type
    private func getHealthDataTypes(for habitType: String) -> [HKObjectType] {
        switch habitType {
        case "health_steps":
            return [HKObjectType.quantityType(forIdentifier: .stepCount)!]
        case "health_walking_running_distance":
            return [HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!]
        case "health_flights_climbed":
            return [HKObjectType.quantityType(forIdentifier: .flightsClimbed)!]
        case "health_exercise_minutes":
            return [HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!]
        case "health_cycling_distance":
            return [HKObjectType.quantityType(forIdentifier: .distanceCycling)!]
        case "health_sleep_hours":
            return [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!]
        case "health_calories_burned":
            return [HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!]
        case "health_mindful_minutes":
            return [HKObjectType.categoryType(forIdentifier: .mindfulSession)!]
        default:
            return []
        }
    }
    
    // MARK: - Data Fetching
    
    func getTodaySteps() async throws -> Double {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        return try await getTodayQuantity(for: stepType, unit: .count())
    }
    
    func getTodayWalkingRunningDistance() async throws -> Double {
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        return try await getTodayQuantity(for: distanceType, unit: .mile())
    }
    
    func getTodayFlightsClimbed() async throws -> Double {
        let flightsType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed)!
        return try await getTodayQuantity(for: flightsType, unit: .count())
    }
    
    func getTodayExerciseMinutes() async throws -> Double {
        let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
        return try await getTodayQuantity(for: exerciseType, unit: .minute())
    }
    
    func getTodayCyclingDistance() async throws -> Double {
        let cyclingType = HKQuantityType.quantityType(forIdentifier: .distanceCycling)!
        return try await getTodayQuantity(for: cyclingType, unit: .mile())
    }
    
    func getLastNightSleepHours() async throws -> Double {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        
        let startOfYesterday = calendar.startOfDay(for: yesterday)
        let endOfToday = calendar.startOfDay(for: now).addingTimeInterval(24*60*60)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfYesterday, end: endOfToday, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0.0)
                    return
                }
                
                let sleepTime = sleepSamples
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
                    .reduce(0.0) { total, sample in
                        total + sample.endDate.timeIntervalSince(sample.startDate) / 3600.0 // Convert to hours
                    }
                
                continuation.resume(returning: sleepTime)
            }
            
            healthStore.execute(query)
        }
    }
    
    func getTodayCaloriesBurned() async throws -> Double {
        let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        return try await getTodayQuantity(for: caloriesType, unit: .kilocalorie())
    }
    
    func getTodayMindfulMinutes() async throws -> Double {
        let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession)!
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: mindfulType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let mindfulSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0.0)
                    return
                }
                
                let totalMinutes = mindfulSamples.reduce(0.0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate) / 60.0 // Convert to minutes
                }
                
                continuation.resume(returning: totalMinutes)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Helper Methods
    
    private func getTodayQuantity(for quantityType: HKQuantityType, unit: HKUnit) async throws -> Double {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    print("❌ HealthKit query error for \(quantityType.identifier): \(error.localizedDescription)")
                    // Return 0 instead of throwing error for better UX
                    // This handles cases where permission is granted but data isn't available yet
                    continuation.resume(returning: 0.0)
                    return
                }
                
                guard let result = result, let sum = result.sumQuantity() else {
                    print("ℹ️ No health data available for \(quantityType.identifier), returning 0 (this is normal if no data exists yet)")
                    continuation.resume(returning: 0.0)
                    return
                }
                
                let value = sum.doubleValue(for: unit)
                print("✅ HealthKit data for \(quantityType.identifier): \(value) \(unit.unitString)")
                continuation.resume(returning: value)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Data Sync Methods
    
    func syncHealthData(for habitType: String) async throws -> HealthDataPoint? {
        let dataPoint: HealthDataPoint?
        
        switch habitType {
        case "health_steps":
            let steps = try await getTodaySteps()
            dataPoint = HealthDataPoint(
                dataType: "stepCount",
                value: steps,
                unit: "steps",
                date: Date().formatted(.dateTime.year().month().day()),
                startTime: Calendar.current.startOfDay(for: Date()).ISO8601Format(),
                endTime: Date().ISO8601Format(),
                sourceName: "iPhone/Apple Watch"
            )
        case "health_walking_running_distance":
            let distance = try await getTodayWalkingRunningDistance()
            dataPoint = HealthDataPoint(
                dataType: "distanceWalkingRunning",
                value: distance,
                unit: "miles",
                date: Date().formatted(.dateTime.year().month().day()),
                startTime: Calendar.current.startOfDay(for: Date()).ISO8601Format(),
                endTime: Date().ISO8601Format(),
                sourceName: "iPhone/Apple Watch"
            )
        case "health_flights_climbed":
            let flights = try await getTodayFlightsClimbed()
            dataPoint = HealthDataPoint(
                dataType: "flightsClimbed",
                value: flights,
                unit: "flights",
                date: Date().formatted(.dateTime.year().month().day()),
                startTime: Calendar.current.startOfDay(for: Date()).ISO8601Format(),
                endTime: Date().ISO8601Format(),
                sourceName: "iPhone/Apple Watch"
            )
        case "health_exercise_minutes":
            let exercise = try await getTodayExerciseMinutes()
            dataPoint = HealthDataPoint(
                dataType: "appleExerciseTime",
                value: exercise,
                unit: "minutes",
                date: Date().formatted(.dateTime.year().month().day()),
                startTime: Calendar.current.startOfDay(for: Date()).ISO8601Format(),
                endTime: Date().ISO8601Format(),
                sourceName: "iPhone/Apple Watch"
            )
        case "health_cycling_distance":
            let cycling = try await getTodayCyclingDistance()
            dataPoint = HealthDataPoint(
                dataType: "distanceCycling",
                value: cycling,
                unit: "miles",
                date: Date().formatted(.dateTime.year().month().day()),
                startTime: Calendar.current.startOfDay(for: Date()).ISO8601Format(),
                endTime: Date().ISO8601Format(),
                sourceName: "iPhone/Apple Watch"
            )
        case "health_sleep_hours":
            let sleep = try await getLastNightSleepHours()
            dataPoint = HealthDataPoint(
                dataType: "sleepAnalysis",
                value: sleep,
                unit: "hours",
                date: Date().formatted(.dateTime.year().month().day()),
                startTime: Calendar.current.startOfDay(for: Date()).ISO8601Format(),
                endTime: Date().ISO8601Format(),
                sourceName: "iPhone/Apple Watch"
            )
        case "health_calories_burned":
            let calories = try await getTodayCaloriesBurned()
            dataPoint = HealthDataPoint(
                dataType: "activeEnergyBurned",
                value: calories,
                unit: "kcal",
                date: Date().formatted(.dateTime.year().month().day()),
                startTime: Calendar.current.startOfDay(for: Date()).ISO8601Format(),
                endTime: Date().ISO8601Format(),
                sourceName: "iPhone/Apple Watch"
            )
        case "health_mindful_minutes":
            let mindful = try await getTodayMindfulMinutes()
            dataPoint = HealthDataPoint(
                dataType: "mindfulSession",
                value: mindful,
                unit: "minutes",
                date: Date().formatted(.dateTime.year().month().day()),
                startTime: Calendar.current.startOfDay(for: Date()).ISO8601Format(),
                endTime: Date().ISO8601Format(),
                sourceName: "iPhone/Apple Watch"
            )
        default:
            dataPoint = nil
        }
        
        return dataPoint
    }
}

// MARK: - Error Types

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case permissionDenied
    case unsupportedHabitType
    case dataUnavailable
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .permissionDenied:
            return "Permission denied for health data access"
        case .unsupportedHabitType:
            return "This habit type is not supported for health tracking"
        case .dataUnavailable:
            return "Health data is currently unavailable"
        }
    }
}

// MARK: - Data Models

struct HealthDataPoint: Codable {
    let dataType: String
    let value: Double
    let unit: String
    let date: String
    let startTime: String?
    let endTime: String?
    let sourceName: String?
    
    init(dataType: String, value: Double, unit: String, date: String, startTime: String? = nil, endTime: String? = nil, sourceName: String? = nil) {
        self.dataType = dataType
        self.value = value
        self.unit = unit
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.sourceName = sourceName
    }
} 