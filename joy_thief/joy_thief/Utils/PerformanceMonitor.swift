import Foundation
import UIKit
import os.log

/// Lightweight performance monitoring utility for tracking slow operations
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private let performanceLog = OSLog(subsystem: "com.tally.performance", category: "Performance")
    
    // Threshold for operations considered slow (in seconds)
    private let slowOperationThreshold: TimeInterval = 0.5
    
    // Memory pressure monitoring
    private var lastMemoryWarning: Date?
    
    private init() {
        setupMemoryPressureMonitoring()
    }
    
    // MARK: - Operation Timing
    
    /// Track the performance of an operation
    @discardableResult
    func track<T>(_ operationName: String, operation: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logOperation(operationName, duration: duration)
        }
        
        return try operation()
    }
    
    /// Track the performance of an async operation
    @discardableResult
    func track<T>(_ operationName: String, operation: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logOperation(operationName, duration: duration)
        }
        
        return try await operation()
    }
    
    /// Start timing an operation manually
    func startTiming(_ operationName: String) -> TimingToken {
        return TimingToken(operationName: operationName, startTime: CFAbsoluteTimeGetCurrent())
    }
    
    /// Timing token for manual timing control
    struct TimingToken {
        let operationName: String
        let startTime: CFAbsoluteTime
        
        /// End timing and log the result
        func end() {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            PerformanceMonitor.shared.logOperation(operationName, duration: duration)
        }
    }
    
    // MARK: - Logging
    
    private func logOperation(_ operationName: String, duration: TimeInterval) {
        let durationMs = Int(duration * 1000)
        
        if duration >= slowOperationThreshold {
            // Log slow operations as warnings
            os_log(.fault, log: performanceLog, "⚠️ SLOW: %{public}@ took %d ms", operationName, durationMs)
            
            // Also print to console for immediate visibility during development
            print("⚠️ [Performance] SLOW: \(operationName) took \(durationMs)ms")
        } else {
            // Log normal operations at debug level
            os_log(.debug, log: performanceLog, "✅ %{public}@ completed in %d ms", operationName, durationMs)
            
            // Only print fast operations in debug builds
            #if DEBUG
            if duration > 0.1 { // Only log operations over 100ms in debug
                print("✅ [Performance] \(operationName) completed in \(durationMs)ms")
            }
            #endif
        }
    }
    
    // MARK: - Memory Monitoring
    
    private func setupMemoryPressureMonitoring() {
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        lastMemoryWarning = Date()
        os_log(.error, log: performanceLog, "⚠️ Memory warning received!")
        print("⚠️ [Performance] Memory warning received!")
        
        // Clear date parsing cache to free memory
        DateFormatterManager.shared.clearDateCache()
    }
    
    /// Check if we're under memory pressure
    var isUnderMemoryPressure: Bool {
        guard let lastWarning = lastMemoryWarning else { return false }
        // Consider under pressure for 30 seconds after a warning
        return Date().timeIntervalSince(lastWarning) < 30
    }
    
    // MARK: - Critical Section Monitoring
    
    /// Monitor a critical section that should not hang
    func monitorCriticalSection(_ sectionName: String, timeout: TimeInterval = 5.0, operation: () async throws -> Void) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create a timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            os_log(.fault, log: performanceLog, "⚠️ TIMEOUT: %{public}@ exceeded %0.1fs (ran for %0.1fs)", sectionName, timeout, duration)
            print("⚠️ [Performance] TIMEOUT: \(sectionName) exceeded \(timeout)s")
        }
        
        defer {
            timeoutTask.cancel()
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logOperation(sectionName, duration: duration)
        }
        
        try await operation()
    }
}

// MARK: - Convenience Extensions

extension PerformanceMonitor {
    /// Common operation names
    enum Operation {
        static let startup = "App Startup"
        static let cacheLoad = "Cache Load"
        static let networkFetch = "Network Fetch"
        static let imageLoad = "Image Load"
        static let dateParcing = "Date Parsing"
        static let commentOrganization = "Comment Organization"
        static let habitVerification = "Habit Verification"
        static let feedRefresh = "Feed Refresh"
    }
}