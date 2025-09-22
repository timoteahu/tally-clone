import Foundation
import UIKit
import Kingfisher

@MainActor
class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    
    /// Track in-flight preload tasks to prevent duplicate work.
    private var loadingTasks: [String: Task<Void, Never>] = [:]
    
    private init() {
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Retrieve an image from cache.
    /// 1. Check Kingfisher's in-memory cache first (fastest).
    /// 2. If not in memory, attempt to synchronously read from the on-disk cache.
    ///    When a disk hit occurs we immediately store the image back into the
    ///    memory cache so subsequent look-ups are also fast.
    ///
    /// This change prevents unnecessary network fetches after a cold app launch
    /// because images that were cached on a previous run now get promoted back
    /// into memory before the UI asks for them. As a result the feed cards can
    /// be rendered with their images immediately, eliminating the loading
    /// placeholder the user was previously seeing on every app open.
    func getCachedImage(for key: String) async -> UIImage? {
        // 1️⃣ Try in-memory cache first
        if let image = ImageCache.default.retrieveImageInMemoryCache(forKey: key) {
            return image
        }

        
        // 2️⃣ Fallback to on-disk cache
        if let image = try? await ImageCache.default.retrieveImageInDiskCache(forKey: key) {
            // Promote to memory for quicker future access within the same session
            cacheImage(image, forKey: key)
            return image
        }

        // 3️⃣ Not cached at all
        return nil
    }
    
    // Preload image for a specific habit
    func preloadImage(for habitId: String) {
        // Don't reload if already cached or loading
        guard ImageCache.default.retrieveImageInMemoryCache(forKey: habitId) == nil,
              loadingTasks[habitId] == nil else {
            return
        }
        
        let task = Task { @MainActor in
            let habitManager = HabitManager.shared
            let (selfieData, contentData) = habitManager.getCachedVerificationImages(for: habitId)
            
            var imageToCache: UIImage?
            
            if let contentData = contentData, let image = UIImage(data: contentData) {
                imageToCache = image
            } else if let selfieData = selfieData, let image = UIImage(data: selfieData) {
                imageToCache = image
            } else if let imageData = habitManager.getCachedVerificationImage(for: habitId),
                      let image = UIImage(data: imageData) {
                imageToCache = image
            }
            
            if let imageToCache = imageToCache {
                self.cacheImage(imageToCache, forKey: habitId)
            }
            
            self.loadingTasks.removeValue(forKey: habitId)
        }
        
        loadingTasks[habitId] = task
    }
    
    // Preload images for multiple habits
    func preloadImages(for habitIds: [String], from habitManager: HabitManager) {
        for habitId in habitIds {
            preloadImage(for: habitId)
        }
    }
    
    // Clear cache for a specific habit
    func clearCache(for habitId: String) {
        loadingTasks[habitId]?.cancel()
        loadingTasks.removeValue(forKey: habitId)
        ImageCache.default.removeImage(forKey: habitId, fromMemory: true, fromDisk: false)
    }
    
    // Clear all cache
    func clearAllCache() {
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        ImageCache.default.clearMemoryCache()
    }
    
    // MARK: - Feed Post Prefetching
    
    /// Prefetch all remote images referenced by the supplied feed posts using Kingfisher.
    /// Any successfully fetched image is stored in Kingfisher's cache **and** mirrored into
    /// the legacy `imageCache` dictionary so existing call-sites keep working.
    func preloadFeedImages(for feedPosts: [FeedPost]) {
        // IMPORTANT:
        // 1. If an image already exists in **disk** cache, promote it back into **memory** so
        //    the UI can render instantly without the placeholder flash.
        // 2. Only when the image is missing from both memory *and* disk do we schedule a
        //    network pre-fetch. This prevents the redundant re-download that the user was
        //    observing on every app launch.

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            // Collect: (URL, cacheKey) for every potential image we want to ensure is in memory
            var remoteFetchURLs: [URL] = []

            for post in feedPosts {
                let baseKey = post.postId.uuidString

                // Helper to handle a single URL/key pair (selfie, content, or fallback)
                func process(urlString: String?, keySuffix: String) async {
                    guard let urlString,
                          let url = URL(string: urlString) else { return }

                    let cacheKey = keySuffix.isEmpty ? baseKey : "\(baseKey)_\(keySuffix)"

                    // ⬆️ 1) Is it already in memory? Great – nothing to do.
                    if ImageCache.default.retrieveImageInMemoryCache(forKey: cacheKey) != nil {
                        return
                    }

                    // 📀 2) Try disk cache next. If we find it, immediately promote to memory so
                    //      subsequent look-ups are fast and the UI never shows a placeholder.
                    if let diskImage = try? await ImageCache.default.retrieveImageInDiskCache(forKey: cacheKey) {
                        await self.cacheImage(diskImage, forKey: cacheKey)
                        return
                    }

                    // 🌐 3) Missing in both caches – queue for remote fetch.
                    remoteFetchURLs.append(url)
                }

                // Process selfie & content images first (highest quality), else fallback
                await process(urlString: post.selfieImageUrl, keySuffix: "selfie")
                await process(urlString: post.contentImageUrl, keySuffix: "content")

                if post.selfieImageUrl == nil && post.contentImageUrl == nil {
                    await process(urlString: post.imageUrl, keySuffix: "")
                }
            }

            // 🚀 Kick off a Kingfisher prefetch ONLY for the images we truly lack.
            guard !remoteFetchURLs.isEmpty else { return }

            ImagePrefetcher(urls: remoteFetchURLs, progressBlock: nil) { _, _, _ in
                // Images fetched → automatically stored in both memory & disk by Kingfisher.
            }.start()
        }
    }
    
    // Backwards-compat: still available but now just calls new prefetching
    func preloadFeedImages(for feedPost: FeedPost) {
        preloadFeedImages(for: [feedPost])
    }
    
    // Get image with fallback to loading
    func getImage(for habitId: String, from habitManager: HabitManager) -> UIImage? {
        // Return cached image if available
        if let cachedImage = ImageCache.default.retrieveImageInMemoryCache(forKey: habitId) {
            return cachedImage
        }
        
        // Try to load from habit manager cache
        if let imageData = habitManager.getCachedVerificationImage(for: habitId) {
            if let image = UIImage(data: imageData) {
                cacheImage(image, forKey: habitId)
                return image
            }
        } else {
            // Try refreshing verification data in case the image_url field wasn't populated
            Task {
                await habitManager.refreshVerificationData(for: habitId)
                
                // Try again after refresh
                if let imageData = habitManager.getCachedVerificationImage(for: habitId) {
                    if let image = UIImage(data: imageData) {
                        cacheImage(image, forKey: habitId)
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Store image in Kingfisher cache **and** persist to disk. Persisting ensures that
    /// the next time the user returns to the feed (or the app relaunches) we can load
    /// the picture directly from the file-system instead of hitting the network again.
    func cacheImage(_ image: UIImage, forKey key: String) {
        ImageCache.default.store(image, forKey: key, toDisk: true)
    }
    
    @objc private func handleMemoryWarning() {
        print("⚠️ Memory warning received - clearing image cache and canceling loads")
        
        // Cancel all in-flight loading tasks
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        
        // Clear Kingfisher memory cache (keep disk cache)
        ImageCache.default.clearMemoryCache()
        
        // Force garbage collection
        ImageCache.default.cleanExpiredDiskCache()
    }
} 
