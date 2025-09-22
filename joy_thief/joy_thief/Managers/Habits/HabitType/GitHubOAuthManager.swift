import Foundation
import SwiftUI

@MainActor
final class GitHubOAuthManager: ObservableObject {
    static let shared = GitHubOAuthManager()
    private init() {}

    @Published var isProcessing = false
    @Published var lastError: String? = nil

    /// Exchange the temporary GitHub `code` for an access-token via the backend.
    func exchange(code: String) async {
        guard !code.isEmpty else { return }
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            lastError = "User not authenticated"
            return
        }

        isProcessing = true; defer { isProcessing = false }
        do {
            guard let url = URL(string: "\(AppConfig.baseURL)/github/exchange-token") else {
                throw URLError(.badURL)
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONEncoder().encode(["code": code])

            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "GitHubOAuth", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
            }
            // Success – you could parse response if needed
            print("✅ GitHub OAuth exchange succeeded")
            lastError = nil
            NotificationCenter.default.post(name: NSNotification.Name("RefreshGitHubStatus"), object: nil)
        } catch {
            print("❌ GitHub OAuth exchange failed: \(error)")
            lastError = error.localizedDescription
            NotificationCenter.default.post(name: NSNotification.Name("RefreshGitHubStatus"), object: nil)
        }
    }
} 