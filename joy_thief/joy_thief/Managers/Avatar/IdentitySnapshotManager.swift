import Foundation
import SwiftUI

// This response model must match the backend response from `upload-identity-snapshot`
struct IdentitySnapshotUploadResponse: Codable {
    let message: String
    let identity_snapshot_url: String
}

@MainActor
final class IdentitySnapshotManager: ObservableObject {
    static let shared = IdentitySnapshotManager()
    
    enum UploadState: Equatable {
        case idle
        case loading
        case success(String) // Success message
        case failure(String)
    }
    
    @Published var uploadState: UploadState = .idle
    
    private init() {}
    
    func upload(image: UIImage) async {
        uploadState = .loading
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            uploadState = .failure("User not authenticated.")
            return
        }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/users/upload-identity-snapshot") else {
            uploadState = .failure("Invalid endpoint URL.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            uploadState = .failure("Could not convert image to JPEG data.")
            return
        }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"snapshot.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                uploadState = .failure("Invalid response from server.")
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                let decodedResponse = try JSONDecoder().decode(IdentitySnapshotUploadResponse.self, from: data)
                uploadState = .success(decodedResponse.message)
            } else {
                let errorDetail = String(data: data, encoding: .utf8) ?? "Unknown server error."
                uploadState = .failure("Server returned status \(httpResponse.statusCode): \(errorDetail)")
            }
        } catch {
            uploadState = .failure("Upload failed: \(error.localizedDescription)")
        }
    }
}
