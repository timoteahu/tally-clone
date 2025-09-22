//
//  AvatarManager.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//


import Foundation
import UIKit
import Kingfisher

@Observable
class AvatarManager {
    var isUploading = false
    var errorMessage: String?
    
    // Kingfisher image cache configuration
    private let imageCache = ImageCache.default
    
    struct AvatarUploadResponse: Codable {
        let message: String
        let avatarVersion: Int
        let avatarUrl80: String
        let avatarUrl200: String
        let avatarUrlOriginal: String
        
        enum CodingKeys: String, CodingKey {
            case message
            case avatarVersion = "avatar_version"
            case avatarUrl80 = "avatar_url_80"
            case avatarUrl200 = "avatar_url_200"
            case avatarUrlOriginal = "avatar_url_original"
        }
    }
    
    struct AvatarResponse: Codable {
        let avatarUrl80: String?
        let avatarUrl200: String?
        let avatarUrlOriginal: String?
        
        enum CodingKeys: String, CodingKey {
            case avatarUrl80 = "avatar_url_80"
            case avatarUrl200 = "avatar_url_200"
            case avatarUrlOriginal = "avatar_url_original"
        }
    }
    
    init() {
        configureKingfisher()
    }
    
    private func configureKingfisher() {
        // Configure Kingfisher for aggressive caching
        imageCache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024 // 100MB memory cache
        imageCache.diskStorage.config.sizeLimit = 500 * 1024 * 1024 // 500MB disk cache
        imageCache.diskStorage.config.expiration = .days(30) // 30 days disk cache
        
        // Preserve the global Kingfisher defaults set in `TallyApp` so we don't
        // accidentally shorten the in-memory lifetime of cached images. (That was
        // causing post images to disappear and reload when revisiting the feed.)
        KingfisherManager.shared.defaultOptions = [
            .cacheOriginalImage,
            .backgroundDecode,
            .callbackQueue(.mainAsync),
            .scaleFactor(UIScreen.main.scale),
            .diskCacheExpiration(.days(30))
            // ⬆️ No per-call memory expiration override here; we inherit the 2-hour
            //     setting from the app-wide configuration.
        ]
    }
    
    func uploadAvatar(image: UIImage, token: String) async throws -> AvatarUploadResponse {
        await MainActor.run { isUploading = true }
        defer { Task { @MainActor in isUploading = false } }
        
        let url = URL(string: "\(AppConfig.baseURL)/users/upload-avatar")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add image data
        if let imageData = image.jpegData(compressionQuality: 0.9) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        } else {
            throw AvatarError.invalidImage
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AvatarError.networkError
        }
        
        print("AvatarManager: Response status code: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            let uploadResponse = try JSONDecoder().decode(AvatarUploadResponse.self, from: data)
            
            // Clear old cached avatars (they have different URLs now due to versioning)
            await clearAvatarCache()
            
            // Prefetch new avatar sizes for instant loading
            await prefetchAvatars(response: uploadResponse)

            // Immediately cache the uploaded image in AvatarImageStore
            await MainActor.run {
                let avatarURLs = [uploadResponse.avatarUrl80, uploadResponse.avatarUrl200, uploadResponse.avatarUrlOriginal]
                for urlString in avatarURLs {
                    // Use the original uploaded image for immediate display
                    AvatarImageStore.shared.set(image, for: urlString)
                    // Also cache in Kingfisher memory for backup
                    ImageCache.default.store(image, forKey: urlString, toDisk: false)
                    print("🖼️ [AvatarManager] Immediately cached uploaded avatar: \(urlString)")
                }
                print("✅ [AvatarManager] Avatar upload cached in AvatarImageStore and Kingfisher")
            }

            // Update auth state so UI reflects the new avatar everywhere
            await MainActor.run {
                AuthenticationManager.shared.updateUserAvatar(
                    avatarVersion: uploadResponse.avatarVersion,
                    avatarUrl80: uploadResponse.avatarUrl80,
                    avatarUrl200: uploadResponse.avatarUrl200,
                    avatarUrlOriginal: uploadResponse.avatarUrlOriginal
                )
            }

            return uploadResponse
        } else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("AvatarManager: Error response body: \(errorString)")
            }
            
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let errorMessage = errorResponse?.detail ?? "Failed to upload avatar (HTTP \(httpResponse.statusCode))"
            throw AvatarError.serverError(errorMessage)
        }
    }
    
    func getAvatar(token: String) async throws -> AvatarResponse? {
        let url = URL(string: "\(AppConfig.baseURL)/users/avatar")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AvatarError.networkError
        }
        
        if httpResponse.statusCode == 200 {
            let avatarResponse = try JSONDecoder().decode(AvatarResponse.self, from: data)
            
            // Prefetch avatar if URLs exist
            if let response80 = avatarResponse.avatarUrl80 {
                let mockResponse = AvatarUploadResponse(
                    message: "",
                    avatarVersion: 0,
                    avatarUrl80: response80,
                    avatarUrl200: avatarResponse.avatarUrl200 ?? "",
                    avatarUrlOriginal: avatarResponse.avatarUrlOriginal ?? ""
                )
                await prefetchAvatars(response: mockResponse)
            }
            
            return avatarResponse
        } else {
            throw AvatarError.networkError
        }
    }
    
    /// Prefetch all avatar sizes for instant display
    private func prefetchAvatars(response: AvatarUploadResponse) async {
        let urls = [
            URL(string: response.avatarUrl80),
            URL(string: response.avatarUrl200),
            URL(string: response.avatarUrlOriginal)
        ].compactMap { $0 }
        
        
        let prefetcher = ImagePrefetcher(
            urls: urls,
            options: [
                .cacheOriginalImage,
                .backgroundDecode,
                .diskCacheExpiration(.days(30))
            ],
            progressBlock: nil,                     // you don't need a progress callback
            completionHandler: { skippedResources, failedResources, completedResources in

                // Verify images are cached
                for resource in completedResources {
                    let cached = ImageCache.default.isCached(forKey: resource.cacheKey)
                    print("AvatarManager: Image \(resource.cacheKey) cached: \(cached)")
                }
            }
        )

        
        prefetcher.start()
    }
    
    /// Clear cached avatars when new version is uploaded
    private func clearAvatarCache() async {
        await MainActor.run {
            // Clear memory cache
            imageCache.clearMemoryCache()
            
        }
    }
    
    func deleteAvatar(token: String) async throws {
        await MainActor.run { isUploading = true }
        defer { Task { @MainActor in isUploading = false } }
        
        let url = URL(string: "\(AppConfig.baseURL)/users/avatar")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AvatarError.networkError
        }
        
        if httpResponse.statusCode == 200 {
            // Clear cached avatars
            await clearAvatarCache()
        } else {
            throw AvatarError.serverError("Failed to delete avatar")
        }
    }
}

enum AvatarError: Error {
    case networkError
    case serverError(String)
    case invalidImage
}

// MARK: - Kingfisher Extensions for Avatar Display

extension UIImageView {
    /// Load avatar with automatic size selection and caching
    func setAvatar(
        url80: String?,
        url200: String?,
        urlOriginal: String?,
        size: AvatarSize = .medium,
        placeholder: UIImage? = UIImage(systemName: "person.crop.circle.fill")
    ) {
        let targetURL: String?
        
        switch size {
        case .small:
            targetURL = url80
        case .medium:
            targetURL = url200
        case .large:
            targetURL = urlOriginal ?? url200
        }
        
        guard let urlString = targetURL, let url = URL(string: urlString) else {
            self.image = placeholder
            return
        }
        
        let processor = DownsamplingImageProcessor(size: self.bounds.size)
        
        self.kf.setImage(
            with: url,
            placeholder: placeholder,
            options: [
                .processor(processor),
                .cacheOriginalImage,
                .transition(.fade(0.15)),
                .keepCurrentImageWhileLoading
            ]
        )
    }
}

enum AvatarSize {
    case small  // 80px
    case medium // 200px
    case large  // Original
} 
