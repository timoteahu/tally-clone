import SwiftUI

extension View {
    /// Add pull-to-refresh functionality that forces cache refresh
    func cacheRefreshable(action: @escaping () async -> Void) -> some View {
        self.refreshable {
            await action()
        }
    }
    
    /// Add pull-to-refresh that specifically refreshes the data cache
    func dataCacheRefreshable() -> some View {
        self.refreshable {
            await refreshDataCache()
        }
    }
    
    private func refreshDataCache() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            return
        }
        
        // Force refresh all cached data
        _ = await DataCacheManager.shared.forceRefresh(token: token)
    }
}

// MARK: - Cache Status View
struct CacheStatusView: View {
    @ObservedObject private var cacheManager = DataCacheManager.shared
    
    var body: some View {
        VStack(spacing: 4) {
            if cacheManager.isSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Syncing...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if cacheManager.cacheHitRate > 0 {
                Text("Cache: \(String(format: "%.0f", cacheManager.cacheHitRate * 100))% hit rate")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
            
            if let lastSync = cacheManager.lastSyncTime {
                Text("Last sync: \(timeAgoString(from: lastSync))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Cache Control View
struct CacheControlView: View {
    @ObservedObject private var cacheManager = DataCacheManager.shared
    @State private var isRefreshing = false
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Data Cache")
                .font(.headline)
            
            CacheStatusView()
            
            HStack(spacing: 16) {
                Button("Force Refresh") {
                    Task {
                        await forceRefresh()
                    }
                }
                .disabled(isRefreshing)
                
                Button("Clear Cache") {
                    cacheManager.clearCache()
                }
                .foregroundColor(.red)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func forceRefresh() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            return
        }
        
        isRefreshing = true
        _ = await cacheManager.forceRefresh(token: token)
        isRefreshing = false
    }
} 
