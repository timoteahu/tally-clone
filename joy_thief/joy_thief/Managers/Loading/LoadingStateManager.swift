import Foundation
import SwiftUI

class LoadingStateManager: ObservableObject {
    static let shared = LoadingStateManager()
    
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    
    private var targetProgress: Double = 0
    private var loadingTasks: [String: Bool] = [:]
    private let minimumLoadingTime: TimeInterval = 1.5
    private var animationTimer: Timer?
    
    // Thread-safe access to loadingTasks
    private let loadingQueue = DispatchQueue(label: "loadingstate.queue", qos: .utility)
    
    private init() {}
    
    func startLoading() {
        isLoading = true
        loadingProgress = 0
        targetProgress = 0
        loadingQueue.async {
            self.loadingTasks.removeAll()
        }
        startProgressAnimation()
    }
    
    func addLoadingTask(_ task: String) {
        loadingQueue.async {
            self.loadingTasks[task] = false
            self.updateTargetProgress()
        }
    }
    
    func completeLoadingTask(_ task: String) {
        loadingQueue.async {
            self.loadingTasks[task] = true
            self.updateTargetProgress()
        }
    }
    
    private func updateTargetProgress() {
        let completed = loadingTasks.values.filter { $0 }.count
        let total = loadingTasks.count
        let newProgress = total > 0 ? Double(completed) / Double(total) : 0
        
        DispatchQueue.main.async {
            self.targetProgress = newProgress
        }
    }
    
    private func startProgressAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.animateProgress()
        }
    }
    
    private func animateProgress() {
        guard isLoading else {
            animationTimer?.invalidate()
            return
        }
        
        let difference = targetProgress - loadingProgress
        
        // Different animation speeds based on progress state
        let animationSpeed: Double
        if targetProgress == 0 {
            // Initial loading - slow start
            animationSpeed = 0.02
        } else if targetProgress < 0.3 {
            // Early progress - moderate speed
            animationSpeed = 0.03
        } else if targetProgress < 0.7 {
            // Mid progress - faster speed
            animationSpeed = 0.05
        } else if targetProgress < 1.0 {
            // Near completion - slower for anticipation
            animationSpeed = 0.025
        } else {
            // Final completion - quick finish
            animationSpeed = 0.08
        }
        
        // Smooth easing towards target
        if abs(difference) > 0.001 {
            loadingProgress += difference * animationSpeed
        } else {
            loadingProgress = targetProgress
        }
        
        // Ensure we don't exceed bounds
        loadingProgress = max(0, min(1, loadingProgress))
    }
    
    func finishLoading() async {
        // Set target to completion and animate to it
        targetProgress = 1.0
        
        // Wait for animation to reach near completion
        while loadingProgress < 0.98 {
            try? await Task.sleep(nanoseconds: 16_000_000) // ~60fps
        }
        
        // Ensure minimum loading time
        let startTime = Date()
        let elapsedTime = Date().timeIntervalSince(startTime)
        if elapsedTime < minimumLoadingTime {
            try? await Task.sleep(nanoseconds: UInt64((minimumLoadingTime - elapsedTime) * 1_000_000_000))
        }
        
        await MainActor.run {
            self.animationTimer?.invalidate()
            self.isLoading = false
            self.loadingProgress = 1.0
        }
    }
    
    deinit {
        animationTimer?.invalidate()
    }
} 
