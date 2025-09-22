import UIKit
import Foundation

@MainActor
final class HabitVerificationManager: ObservableObject {

    @Published var isVerifying = false
    @Published var errorMessage: String?
    
    // MARK: - Configuration
    private let requestTimeout: TimeInterval = 30.0
    private let imageCompressionQuality: CGFloat = 0.8
    
    // MARK: - Shared URLSession with optimized configuration
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil // Disable caching for verification requests
        return URLSession(configuration: config)
    }()

    // MARK: – Gym photo verification -----------------------------------------

    func verifyGymHabit(habitId: String,
                        image: UIImage,
                        token: String) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithImage(
            habitId: habitId,
            image: image,
            token: token,
            endpoint: "gym"
        )
    }
    
    // MARK: – Alarm verification helpers ----------------------------------
    
    func verifyAlarmHabit(habitId: String,
                          image: UIImage,
                          token: String) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithImage(
            habitId: habitId,
            image: image,
            token: token,
            endpoint: "alarm"
        )
    }

    // MARK: – Yoga verification helpers ----------------------------------
    
    func verifyYogaHabit(habitId: String,
                         image: UIImage,
                         token: String) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithImage(
            habitId: habitId,
            image: image,
            token: token,
            endpoint: "yoga"
        )
    }
    
    // MARK: – Outdoors verification helpers ----------------------------------
    
    func verifyOutdoorsHabit(habitId: String,
                             image: UIImage,
                             token: String) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithImage(
            habitId: habitId,
            image: image,
            token: token,
            endpoint: "outdoors"
        )
    }
    
    // MARK: – Cycling verification helpers ----------------------------------
    
    func verifyCyclingHabit(habitId: String,
                            image: UIImage,
                            token: String) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithImage(
            habitId: habitId,
            image: image,
            token: token,
            endpoint: "cycling"
        )
    }
    
    // MARK: – Cooking verification helpers ----------------------------------
    
    func verifyCookingHabit(habitId: String,
                            image: UIImage,
                            token: String) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithImage(
            habitId: habitId,
            image: image,
            token: token,
            endpoint: "cooking"
        )
    }

    // MARK: – Health verification helpers ----------------------------------
    
    func verifyHealthHabit(habitId: String,
                           token: String) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        let url = URL(string: "\(AppConfig.baseURL)/habit-verification/health/\(habitId)/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VerificationError.networkError
        }
        
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        if httpResponse.statusCode == 200 {
            // Check if verification was successful
            let isVerified = jsonResponse["is_verified"] as? Bool ?? false
            
            if isVerified {
                let verification = try parseVerificationFromResponse(jsonResponse)
                return (isVerified: true, verification: verification)
            } else {
                // Failed verification but not an error - return the message
                let message = jsonResponse["message"] as? String ?? "Health target not reached yet"
                throw VerificationError.serverError(message)
            }
        } else {
            // For failed verifications, throw an error with the specific message from the backend
            let message = jsonResponse["message"] as? String ?? "Health verification failed"
            throw VerificationError.serverError(message)
        }
    }
    
    func verifyHealthHabitWithBothImages(habitId: String,
                                         selfieImage: UIImage,
                                         contentImage: UIImage,
                                         token: String) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithBothImages(
            habitId: habitId,
            selfieImage: selfieImage,
            contentImage: contentImage,
            token: token,
            endpoint: "health"
        )
    }

    // MARK: – Study session helpers ------------------------------------------

    func startStudySession(habitId: String,
                           token: String) async throws -> String {

        guard let url = URL(string: "\(AppConfig.baseURL)/habit-verification/study/\(habitId)/start") else {
            throw VerificationError.networkError
        }
        
        let req = createBaseRequest(url: url, method: "POST", token: token)

        let (data, resp) = try await urlSession.data(for: req)
        try validateResponse(resp)

        return try JSONDecoder().decode(StudySessionResponse.self, from: data).sessionID
    }

    func completeStudySession(habitId: String,
                              sessionId: String,
                              token: String) async throws {

        guard let url = URL(string: "\(AppConfig.baseURL)/habit-verification/study/\(habitId)/complete") else {
            throw VerificationError.networkError
        }
        
        var req = createBaseRequest(url: url, method: "POST", token: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["session_id": sessionId])

        let (_, resp) = try await urlSession.data(for: req)
        try validateResponse(resp)
    }
    
    // MARK: - Private Helper Methods
    
    private func verifyHabitWithImage(habitId: String,
                                      image: UIImage,
                                      token: String,
                                      endpoint: String) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        guard let url = URL(string: "\(AppConfig.baseURL)/habit-verification/\(endpoint)/\(habitId)/verify") else {
            throw VerificationError.networkError
        }
        
        let req = try createMultipartRequest(url: url, image: image, token: token)
        
        let (data, resp) = try await urlSession.data(for: req)
        try validateResponse(resp)

        let response: VerificationResponse
        do {
            response = try JSONDecoder().decode(VerificationResponse.self, from: data)
        } catch {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("❌ [HabitVerificationManager] Failed to decode VerificationResponse. JSON: \(jsonString)")
                print("❌ [HabitVerificationManager] Error: \(error)")
            }
            throw error
        }
        
        // If verification was successful, fetch the verification record
        var verification: HabitVerification? = nil
        if response.isVerified {
            verification = try await fetchLatestVerification(habitId: habitId, token: token)
            
            // Update the verification record with the streak from the response
            if let _ = response.streak,
               let updatedVerification = verification {
                // Create a new verification with the streak from the response
                verification = HabitVerification(
                    id: updatedVerification.id,
                    habitId: updatedVerification.habitId,
                    userId: updatedVerification.userId,
                    verificationType: updatedVerification.verificationType,
                    verifiedAt: updatedVerification.verifiedAt,
                    status: updatedVerification.status,
                    verificationResult: updatedVerification.verificationResult,
                    imageUrl: updatedVerification.imageUrl,
                    selfieImageUrl: updatedVerification.selfieImageUrl,
                    imageVerificationId: updatedVerification.imageVerificationId,
                    imageFilename: updatedVerification.imageFilename,
                    selfieImageFilename: updatedVerification.selfieImageFilename
                )
            }
        } else {
            // For failed verifications, throw an error with the specific message from the backend
            print("❌ [HabitVerificationManager] Verification failed with message: \(response.message)")
            throw VerificationError.serverError(response.message)
        }
        
        return (isVerified: response.isVerified, verification: verification)
    }
    
    private func verifyHabitWithBothImages(habitId: String,
                                           selfieImage: UIImage,
                                           contentImage: UIImage,
                                           token: String,
                                           endpoint: String,
                                           caption: String? = nil) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        guard let url = URL(string: "\(AppConfig.baseURL)/habit-verification/\(endpoint)/\(habitId)/verify") else {
            throw VerificationError.networkError
        }
        
        let req = try createMultipartRequestWithBothImages(url: url, selfieImage: selfieImage, contentImage: contentImage, token: token, caption: caption)
        
        let (data, resp) = try await urlSession.data(for: req)
        
        // For 400 errors, try to extract the error message from the response
        if let httpResponse = resp as? HTTPURLResponse, httpResponse.statusCode == 400 {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("❌ [HabitVerificationManager] 400 Error Response: \(jsonString)")
                
                // Try to parse the error detail from the backend
                if let errorData = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    // Remove the "400: " prefix if present
                    let cleanedMessage = detail.replacingOccurrences(of: "400: ", with: "")
                    throw VerificationError.serverError(cleanedMessage)
                }
            }
        }
        
        try validateResponse(resp)

        let response = try JSONDecoder().decode(VerificationResponse.self, from: data)
        
        // If verification was successful, fetch the verification record
        var verification: HabitVerification? = nil
        if response.isVerified {
            verification = try await fetchLatestVerification(habitId: habitId, token: token)
            
            // Update the verification record with the streak from the response
            if let _ = response.streak,
               let updatedVerification = verification {
                // Create a new verification with the streak from the response
                verification = HabitVerification(
                    id: updatedVerification.id,
                    habitId: updatedVerification.habitId,
                    userId: updatedVerification.userId,
                    verificationType: updatedVerification.verificationType,
                    verifiedAt: updatedVerification.verifiedAt,
                    status: updatedVerification.status,
                    verificationResult: updatedVerification.verificationResult,
                    imageUrl: updatedVerification.imageUrl,
                    selfieImageUrl: updatedVerification.selfieImageUrl,
                    imageVerificationId: updatedVerification.imageVerificationId,
                    imageFilename: updatedVerification.imageFilename,
                    selfieImageFilename: updatedVerification.selfieImageFilename
                )
            }
        } else {
            // For failed verifications, throw an error with the specific message from the backend
            print("❌ [HabitVerificationManager] Verification failed with message: \(response.message)")
            throw VerificationError.serverError(response.message)
        }
        
        return (isVerified: response.isVerified, verification: verification)
    }
    
    private func createBaseRequest(url: URL, method: String, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }
    
    private func createMultipartRequest(url: URL, image: UIImage, token: String) throws -> URLRequest {
        var req = createBaseRequest(url: url, method: "POST", token: token)
        
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let imageData = image.jpegData(compressionQuality: imageCompressionQuality) else {
            throw VerificationError.invalidImage
        }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        req.httpBody = body
        return req
    }
    
    private func createSingleImageRequest(url: URL, image: UIImage, token: String, fieldName: String) throws -> URLRequest {
        var req = createBaseRequest(url: url, method: "POST", token: token)
        
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let imageData = image.jpegData(compressionQuality: imageCompressionQuality) else {
            throw VerificationError.invalidImage
        }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fieldName).jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        req.httpBody = body
        return req
    }
    
    private func createMultipartRequestWithBothImages(url: URL, selfieImage: UIImage, contentImage: UIImage, token: String, caption: String? = nil) throws -> URLRequest {
        var req = createBaseRequest(url: url, method: "POST", token: token)
        
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let selfieImageData = selfieImage.jpegData(compressionQuality: imageCompressionQuality),
              let contentImageData = contentImage.jpegData(compressionQuality: imageCompressionQuality) else {
            throw VerificationError.invalidImage
        }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"selfie_image\"; filename=\"selfie_image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(selfieImageData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"content_image\"; filename=\"content_image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(contentImageData)
        
        // Add caption if provided
        if let caption = caption, !caption.isEmpty {
            body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
            body.append(caption.data(using: .utf8)!)
        }
        
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        req.httpBody = body
        return req
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VerificationError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            // Check for specific error status codes
            switch httpResponse.statusCode {
            case 400:
                throw VerificationError.serverError("Invalid verification data. Please check your image and try again.")
            case 401:
                throw VerificationError.serverError("Authentication required. Please log in again.")
            case 403:
                throw VerificationError.serverError("You don't have permission to verify this habit.")
            case 404:
                throw VerificationError.serverError("Habit not found. Please refresh and try again.")
            case 429:
                throw VerificationError.serverError("Too many verification attempts. Please wait a moment and try again.")
            case 500...599:
                throw VerificationError.serverError("Server error. Please try again later.")
            default:
                throw VerificationError.serverError("Verification failed (HTTP \(httpResponse.statusCode))")
            }
        }
    }
    
    private func fetchLatestVerification(habitId: String, token: String) async throws -> HabitVerification? {
        guard let url = URL(string: "\(AppConfig.baseURL)/habit-verification/get-latest/\(habitId)") else {
            throw VerificationError.networkError
        }
        
        let req = createBaseRequest(url: url, method: "GET", token: token)
        
        let (data, resp) = try await urlSession.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(HabitVerification.self, from: data)
        } catch {
            // Log the actual JSON response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("❌ [HabitVerificationManager] Failed to decode HabitVerification. JSON response: \(jsonString)")
                print("❌ [HabitVerificationManager] Decoding error: \(error)")
            }
            throw error
        }
    }
    
    private func parseVerificationFromResponse(_ jsonResponse: [String: Any]) throws -> HabitVerification? {
        // Try to extract verification data from the response
        if let verificationId = jsonResponse["verification_id"] as? String,
           let habitId = jsonResponse["habit_id"] as? String ?? jsonResponse["id"] as? String {
            
            // Create a basic verification object - will be updated with full data later
            return HabitVerification(
                id: verificationId,
                habitId: habitId,
                userId: "", // Will be filled by fetchLatestVerification
                verificationType: "health",
                verifiedAt: ISO8601DateFormatter().string(from: Date()),
                status: "completed",
                verificationResult: true,
                imageUrl: nil,
                selfieImageUrl: nil,
                imageVerificationId: nil,
                imageFilename: nil,
                selfieImageFilename: nil
            )
        }
        return nil
    }
    
    // Add method to clear verification cache
    func clearVerificationCache() {
        // Clear URLSession cache
        urlSession.configuration.urlCache?.removeAllCachedResponses()
        
        // Force new URLSession with cleared cache
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        urlSession = URLSession(configuration: config)
    }

    // MARK: – Two-Image Verification Methods ----------------------------------
    
    func verifyGymHabitWithBothImages(habitId: String,
                                      selfieImage: UIImage,
                                      contentImage: UIImage,
                                      token: String,
                                      caption: String? = nil) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithBothImages(
            habitId: habitId,
            selfieImage: selfieImage,
            contentImage: contentImage,
            token: token,
            endpoint: "gym",
            caption: caption
        )
    }
    
    func verifyAlarmHabitWithBothImages(habitId: String,
                                        selfieImage: UIImage,
                                        contentImage: UIImage,
                                        token: String,
                                        caption: String? = nil) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithBothImages(
            habitId: habitId,
            selfieImage: selfieImage,
            contentImage: contentImage,
            token: token,
            endpoint: "alarm",
            caption: caption
        )
    }
    
    func verifyYogaHabitWithBothImages(habitId: String,
                                       selfieImage: UIImage,
                                       contentImage: UIImage,
                                       token: String,
                                       caption: String? = nil) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithBothImages(
            habitId: habitId,
            selfieImage: selfieImage,
            contentImage: contentImage,
            token: token,
            endpoint: "yoga",
            caption: caption
        )
    }
    
    func verifyOutdoorsHabitWithBothImages(habitId: String,
                                           selfieImage: UIImage,
                                           contentImage: UIImage,
                                           token: String,
                                           caption: String? = nil) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithBothImages(
            habitId: habitId,
            selfieImage: selfieImage,
            contentImage: contentImage,
            token: token,
            endpoint: "outdoors",
            caption: caption
        )
    }
    
    func verifyCyclingHabitWithBothImages(habitId: String,
                                          selfieImage: UIImage,
                                          contentImage: UIImage,
                                          token: String,
                                          caption: String? = nil) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithBothImages(
            habitId: habitId,
            selfieImage: selfieImage,
            contentImage: contentImage,
            token: token,
            endpoint: "cycling",
            caption: caption
        )
    }
    
    func verifyCookingHabitWithBothImages(habitId: String,
                                          selfieImage: UIImage,
                                          contentImage: UIImage,
                                          token: String,
                                          caption: String? = nil) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithBothImages(
            habitId: habitId,
            selfieImage: selfieImage,
            contentImage: contentImage,
            token: token,
            endpoint: "cooking",
            caption: caption
        )
    }
    
    func verifyCustomHabitWithBothImages(habitId: String,
                                         selfieImage: UIImage,
                                         contentImage: UIImage,
                                         token: String) async throws -> (isVerified: Bool, verification: HabitVerification?) {
        
        return try await verifyHabitWithBothImages(
            habitId: habitId,
            selfieImage: selfieImage,
            contentImage: contentImage,
            token: token,
            endpoint: "custom"
        )
    }
}

// MARK: - Error Extensions

extension VerificationError {
    static let invalidImage = VerificationError.serverError("Failed to process image")
}
