import Foundation

/// Manages atomic file operations for cache persistence
class CacheFileManager {
    private let fileManager = FileManager.default
    
    /// Get the cache directory URL
    private var cacheDirectory: URL {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("FriendCache")
    }
    
    /// Ensure cache directory exists
    private func ensureCacheDirectoryExists() throws {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Write a Codable object to disk atomically
    func writeAtomically<T: Codable>(_ object: T, to filename: String) async throws {
        try await Task.detached { [weak self] in
            guard let self = self else { return }
            
            try self.ensureCacheDirectoryExists()
            
            let finalURL = self.cacheDirectory.appendingPathComponent(filename)
            let tempURL = finalURL.appendingPathExtension("tmp")
            
            // Encode to JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(object)
            
            // Write to temporary file first
            try data.write(to: tempURL)
            
            // Atomically move to final location
            _ = try self.fileManager.replaceItem(at: finalURL, withItemAt: tempURL, backupItemName: nil, options: [], resultingItemURL: nil)
            
        }.value
    }
    
    /// Read a Codable object from disk
    func read<T: Codable>(_ type: T.Type, from filename: String) async throws -> T? {
        return try await Task.detached { [weak self] in
            guard let self = self else { return nil }
            
            let fileURL = self.cacheDirectory.appendingPathComponent(filename)
            
            guard self.fileManager.fileExists(atPath: fileURL.path) else {
                return nil
            }
            
            let data = try Data(contentsOf: fileURL)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let object = try decoder.decode(type, from: data)
            
            return object
        }.value
    }
    
    /// Delete a cache file
    func delete(filename: String) async throws {
        try await Task.detached { [weak self] in
            guard let self = self else { return }
            
            let fileURL = self.cacheDirectory.appendingPathComponent(filename)
            
            if self.fileManager.fileExists(atPath: fileURL.path) {
                try self.fileManager.removeItem(at: fileURL)
            }
        }.value
    }
    
    /// Get file size in bytes
    func getFileSize(filename: String) async -> Int64 {
        return await Task.detached { [weak self] in
            guard let self = self else { return 0 }
            
            let fileURL = self.cacheDirectory.appendingPathComponent(filename)
            
            do {
                let attributes = try self.fileManager.attributesOfItem(atPath: fileURL.path)
                return attributes[.size] as? Int64 ?? 0
            } catch {
                return 0
            }
        }.value
    }
    
    /// Clear all cache files
    func clearAllCache() async throws {
        try await Task.detached { [weak self] in
            guard let self = self else { return }
            
            if self.fileManager.fileExists(atPath: self.cacheDirectory.path) {
                let contents = try self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)
                
                for fileURL in contents {
                    try self.fileManager.removeItem(at: fileURL)
                }
                
            }
        }.value
    }
} 
