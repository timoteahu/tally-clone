//
//  PaymentsManager.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/4/25.
//

import Foundation
import Combine

struct OwedRecipient: Identifiable, Decodable {
    var id: String { recipient_id }
    let recipient_id: String
    let recipient_name: String
    let amount_owed: Double
}

class OwedAmountManager: ObservableObject {
    @Published var owedRecipients: [OwedRecipient] = []
    @Published var isLoadingOwed = false
    @Published var owedError: String?

    func fetchOwedRecipients(token: String? = nil) {
        guard let url = URL(string: "\(AppConfig.baseURL)/payments/owed-per-recipient") else { return }
        isLoadingOwed = true
        owedError = nil
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingOwed = false
                if let error = error {
                    self.owedError = error.localizedDescription
                    return
                }
                guard let data = data else {
                    self.owedError = "No data"
                    return
                }
                do {
                    let decoded = try JSONDecoder().decode([OwedRecipient].self, from: data)
                    self.owedRecipients = decoded
                } catch {
                    self.owedError = "Failed to decode: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}

