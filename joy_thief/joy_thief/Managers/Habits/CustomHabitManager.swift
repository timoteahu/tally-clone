import Foundation

class CustomHabitManager: ObservableObject {
    static let shared = CustomHabitManager()
    
    @Published var customHabitTypes: [CustomHabitType] = []
    @Published var availableHabitTypes: AvailableHabitTypes?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Configuration
    private let requestTimeout: TimeInterval = 30.0
    
    private init() {} // Make init private for singleton pattern
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()
    
    // MARK: - Network Request Helpers
    
    private func createRequest(url: URL, method: String = "GET", token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    
    private func handleNetworkResponse<T: Codable>(_ data: Data, _ response: URLResponse, expecting: T.Type) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CustomHabitError.networkError
        }
        
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            return try JSONDecoder().decode(T.self, from: data)
        } else {
            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
            
            // Handle 403 Forbidden as premium limitation
            if httpResponse.statusCode == 403 {
                throw CustomHabitError.premiumRequired(errorResponse.detail)
            }
            
            // Check if this is a validation error
            let validationKeywords = [
                "must be at least", "must be less than", "is required",
                "too simple", "repetitive", "must contain at least",
                "provide more details", "more detailed description",
                "description is not detailed enough", "too short",
                "reserved word", "invalid", "already have"
            ]
            
            let isValidationError = validationKeywords.contains { keyword in
                errorResponse.detail.lowercased().contains(keyword.lowercased())
            }
            
            if isValidationError {
                throw CustomHabitError.validationError(errorResponse.detail)
            } else {
                throw CustomHabitError.serverError(errorResponse.detail)
            }
        }
    }
    
    private func updateLoadingState(_ loading: Bool, error: String? = nil) {
        Task { @MainActor in
            self.isLoading = loading
            self.errorMessage = error
        }
    }
    
    // MARK: - Custom Habit Type Management
    
    func createCustomHabitType(typeIdentifier: String, description: String, token: String) async throws -> CustomHabitType {
        updateLoadingState(true)
        
        guard let url = URL(string: "\(AppConfig.baseURL)/custom-habits/") else {
            updateLoadingState(false, error: "Invalid URL")
            throw CustomHabitError.networkError
        }
        
        do {
            var request = createRequest(url: url, method: "POST", token: token)
            
            let customHabitData = CustomHabitTypeCreate(
                typeIdentifier: typeIdentifier,
                description: description
            )
            
            request.httpBody = try JSONEncoder().encode(customHabitData)
            
            let (data, response) = try await urlSession.data(for: request)
            let newCustomHabitType = try handleNetworkResponse(data, response, expecting: CustomHabitType.self)
            
            await MainActor.run {
                self.customHabitTypes.append(newCustomHabitType)
                // Also update available types if loaded
                if let availableTypes = self.availableHabitTypes {
                    let newAvailableType = AvailableCustomHabitType(
                        type: newCustomHabitType.habitTypeValue,
                        displayName: newCustomHabitType.displayName,
                        description: newCustomHabitType.description,
                        isCustom: true
                    )
                    var updatedCustomTypes = availableTypes.customTypes
                    updatedCustomTypes.append(newAvailableType)
                    
                    self.availableHabitTypes = AvailableHabitTypes(
                        builtInTypes: availableTypes.builtInTypes,
                        customTypes: updatedCustomTypes,
                        totalAvailable: availableTypes.totalAvailable + 1
                    )
                }
            }
            
            updateLoadingState(false)
            return newCustomHabitType
        } catch {
            updateLoadingState(false, error: error.localizedDescription)
            throw error
        }
    }
    
    func fetchCustomHabitTypes(token: String) async throws {
        updateLoadingState(true)
        
        guard let url = URL(string: "\(AppConfig.baseURL)/custom-habits/") else {
            updateLoadingState(false, error: "Invalid URL")
            throw CustomHabitError.networkError
        }
        
        do {
            let request = createRequest(url: url, token: token)
            let (data, response) = try await urlSession.data(for: request)
            let customTypes = try handleNetworkResponse(data, response, expecting: [CustomHabitType].self)
            
            await MainActor.run {
                self.customHabitTypes = customTypes
            }
            
            updateLoadingState(false)
        } catch {
            updateLoadingState(false, error: "Failed to fetch custom habit types: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchAvailableHabitTypes(token: String) async throws {
        updateLoadingState(true)
        
        guard let url = URL(string: "\(AppConfig.baseURL)/custom-habits/available-types/list") else {
            updateLoadingState(false, error: "Invalid URL")
            throw CustomHabitError.networkError
        }
        
        do {
            let request = createRequest(url: url, token: token)
            let (data, response) = try await urlSession.data(for: request)
            let availableTypes = try handleNetworkResponse(data, response, expecting: AvailableHabitTypes.self)
            
            await MainActor.run {
                self.availableHabitTypes = availableTypes
            }
            
            updateLoadingState(false)
        } catch {
            updateLoadingState(false, error: "Failed to fetch available habit types: \(error.localizedDescription)")
            throw error
        }
    }
    
    func deleteCustomHabitType(typeId: String, token: String) async throws {
        updateLoadingState(true)
        
        guard let url = URL(string: "\(AppConfig.baseURL)/custom-habits/\(typeId)") else {
            updateLoadingState(false, error: "Invalid URL")
            throw CustomHabitError.networkError
        }
        
        do {
            let request = createRequest(url: url, method: "DELETE", token: token)
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CustomHabitError.networkError
            }
            
            if httpResponse.statusCode == 200 {
                await MainActor.run {
                    // Find the custom type before removing it
                    let customTypeToRemove = self.customHabitTypes.first(where: { $0.id == typeId })
                    
                    // Remove from customHabitTypes array
                    self.customHabitTypes.removeAll { $0.id == typeId }
                    
                    // Also remove from available types if loaded
                    if let availableTypes = self.availableHabitTypes,
                       let customType = customTypeToRemove {
                        let updatedCustomTypes = availableTypes.customTypes.filter { $0.type != customType.habitTypeValue }
                        
                        self.availableHabitTypes = AvailableHabitTypes(
                            builtInTypes: availableTypes.builtInTypes,
                            customTypes: updatedCustomTypes,
                            totalAvailable: availableTypes.totalAvailable - 1
                        )
                    }
                }
            } else {
                let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
                throw CustomHabitError.serverError(errorResponse.detail)
            }
            
            updateLoadingState(false)
        } catch {
            updateLoadingState(false, error: "Failed to delete custom habit type: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    func getCustomHabitType(by typeIdentifier: String) -> CustomHabitType? {
        return customHabitTypes.first { $0.typeIdentifier == typeIdentifier }
    }
    
    func isCustomHabitType(_ habitType: String) -> Bool {
        return habitType.hasPrefix("custom_")
    }
    
    func extractTypeIdentifier(from habitType: String) -> String? {
        if habitType.hasPrefix("custom_") {
            return String(habitType.dropFirst(7)) // Remove "custom_" prefix
        }
        return nil
    }
    
    // MARK: - Preloading
    
    func preloadAll(token: String) async {
        do {
            async let customTypes: Void = fetchCustomHabitTypes(token: token)
            async let availableTypes: Void = fetchAvailableHabitTypes(token: token)
            
            _ = try await (customTypes, availableTypes)
        } catch {
            print("Error preloading custom habits: \(error)")
        }
    }
    
    // MARK: - Refresh after creation
    
    func refreshAfterCreation(token: String) async {
        // Refresh available types after creating a new custom habit
        do {
            try await fetchAvailableHabitTypes(token: token)
        } catch {
            print("Failed to refresh available habit types after creation: \(error)")
        }
    }
} 