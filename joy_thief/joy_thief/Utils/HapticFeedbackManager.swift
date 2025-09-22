import UIKit
import CoreHaptics

/// Manages haptic feedback throughout the app with custom patterns for different scenarios
class HapticFeedbackManager {
    static let shared = HapticFeedbackManager()
    
    private var hapticEngine: CHHapticEngine?
    private var supportsHaptics: Bool = false
    
    private init() {
        setupHapticEngine()
    }
    
    private func setupHapticEngine() {
        // Check if device supports haptics
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("🔇 [HapticFeedbackManager] Device does not support haptics")
            return
        }
        
        supportsHaptics = true
        
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
            
            // Handle engine stopped
            hapticEngine?.stoppedHandler = { reason in
                print("🔇 [HapticFeedbackManager] Haptic engine stopped: \(reason)")
            }
            
            // Handle engine reset
            hapticEngine?.resetHandler = { [weak self] in
                print("🔄 [HapticFeedbackManager] Haptic engine reset, restarting...")
                do {
                    try self?.hapticEngine?.start()
                } catch {
                    print("❌ [HapticFeedbackManager] Failed to restart haptic engine: \(error)")
                }
            }
            
            print("✅ [HapticFeedbackManager] Haptic engine initialized successfully")
        } catch {
            print("❌ [HapticFeedbackManager] Failed to initialize haptic engine: \(error)")
        }
    }
    
    // MARK: - Simple Haptic Feedback
    
    /// Light impact feedback for basic interactions
    func lightImpact() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    /// Medium impact feedback for moderate interactions
    func mediumImpact() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    /// Heavy impact feedback for significant interactions
    func heavyImpact() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    // MARK: - Custom Haptic Patterns
    
    /// Special celebration haptic pattern for habit verification success
    /// Creates a multi-stage experience: primer -> build-up -> climax -> resolution
    func playVerificationSuccess() {
        guard supportsHaptics, let engine = hapticEngine else {
            // Fallback to simple haptic if Core Haptics unavailable
            heavyImpact()
            return
        }
        
        do {
            // Create the verification success pattern
            let pattern = try createVerificationSuccessPattern()
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            
            print("🎉 [HapticFeedbackManager] Playing verification success haptic")
        } catch {
            print("❌ [HapticFeedbackManager] Failed to play verification success haptic: \(error)")
            // Fallback to simple haptic
            heavyImpact()
        }
    }
    
    /// Creates a custom haptic pattern for habit verification success
    private func createVerificationSuccessPattern() throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        
        // 1. Primer - subtle wake-up tap
        let primerIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3)
        let primerSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
        let primerEvent = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [primerIntensity, primerSharpness],
            relativeTime: 0
        )
        events.append(primerEvent)
        
        // 2. Build-up - three increasing taps
        let buildUpTimes: [TimeInterval] = [0.15, 0.25, 0.35]
        let buildUpIntensities: [Float] = [0.5, 0.7, 0.9]
        
        for (index, time) in buildUpTimes.enumerated() {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: buildUpIntensities[index])
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: time
            )
            events.append(event)
        }
        
        // 3. Climax - satisfying continuous haptic
        let climaxIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let climaxSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6) // Less sharp for warmth
        let climaxEvent = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [climaxIntensity, climaxSharpness],
            relativeTime: 0.5,
            duration: 0.4
        )
        events.append(climaxEvent)
        
        // 4. Resolution - final confirmatory tap
        let resolutionIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
        let resolutionSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        let resolutionEvent = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [resolutionIntensity, resolutionSharpness],
            relativeTime: 1.0
        )
        events.append(resolutionEvent)
        
        return try CHHapticPattern(events: events, parameters: [])
    }
    
    /// Quick double-tap haptic for minor confirmations
    func playQuickConfirmation() {
        guard supportsHaptics, let engine = hapticEngine else {
            lightImpact()
            return
        }
        
        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            
            let firstTap = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: 0
            )
            
            let secondTap = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: 0.1
            )
            
            let pattern = try CHHapticPattern(events: [firstTap, secondTap], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("❌ [HapticFeedbackManager] Failed to play quick confirmation: \(error)")
            lightImpact()
        }
    }
    
    /// Error haptic pattern for verification failures
    /// Creates a pattern: warning tap -> pause -> double strong tap
    func playVerificationError() {
        guard supportsHaptics, let engine = hapticEngine else {
            // Fallback to simple haptic if Core Haptics unavailable
            heavyImpact()
            return
        }
        
        do {
            var events: [CHHapticEvent] = []
            
            // 1. Warning tap - medium intensity
            let warningIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6)
            let warningSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
            let warningEvent = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [warningIntensity, warningSharpness],
                relativeTime: 0
            )
            events.append(warningEvent)
            
            // 2. Pause for effect
            
            // 3. Double strong tap - error feedback
            let errorIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
            let errorSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            
            let firstErrorTap = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [errorIntensity, errorSharpness],
                relativeTime: 0.3
            )
            events.append(firstErrorTap)
            
            let secondErrorTap = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [errorIntensity, errorSharpness],
                relativeTime: 0.45
            )
            events.append(secondErrorTap)
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            
            print("🔴 [HapticFeedbackManager] Playing verification error haptic")
        } catch {
            print("❌ [HapticFeedbackManager] Failed to play verification error haptic: \(error)")
            // Fallback to simple haptic
            heavyImpact()
        }
    }
} 