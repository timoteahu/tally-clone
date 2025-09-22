import SwiftUI
import Kingfisher

// MARK: - FeedCard Image Helpers
struct FeedCardImageHelpers {
    
    // MARK: - Image Initialization
    
    static func initializeCachedImages(baseKey: String) -> (UIImage?, UIImage?, UIImage?) {
        func syncCached(_ key: String) -> UIImage? {
            // 1️⃣ Memory first (fast dictionary look-up)
            if let mem = ImageCache.default.retrieveImageInMemoryCache(forKey: key) {
                return mem
            }

            // 2️⃣ Disk – use Kingfisher's file URL helper and decode synchronously
            let cache = ImageCache.default
            let fileURL = cache.diskStorage.cacheFileURL(forKey: key)
            if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
                // Promote back to memory so future look-ups are instantaneous
                cache.store(img, forKey: key, toDisk: false)
                return img
            }
            return nil
        }

        let image = syncCached(baseKey)
        let selfieImage = syncCached(baseKey + "_selfie")
        let contentImage = syncCached(baseKey + "_content")
        
        return (image, selfieImage, contentImage)
    }
    
    // MARK: - Image Loading
    
    static func loadPostImageWithCaching(
        feedPost: FeedPost,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        cachedImage: Binding<UIImage?>,
        cachedSelfieImage: Binding<UIImage?>,
        cachedContentImage: Binding<UIImage?>,
        downloadProgress: Binding<Double>,
        imageCacheManager: ImageCacheManager
    ) {
        if cachedSelfieImage.wrappedValue != nil && cachedContentImage.wrappedValue != nil {
            return
        }

        // Early exit for single-image posts: if both selfie & content are absent but we
        // already hold a generic `cachedImage`, we can render immediately without
        // scheduling unnecessary network work.
        if feedPost.selfieImageUrl == nil && feedPost.contentImageUrl == nil && cachedImage.wrappedValue != nil {
            return
        }

        // Kick off asynchronous work so the UI remains responsive.
        Task {
            await MainActor.run { downloadProgress.wrappedValue = 0.0 }

            // Attempt to fetch whichever images are still missing.
            if cachedSelfieImage.wrappedValue == nil { 
                loadSelfieImage(
                    feedPost: feedPost,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    cachedSelfieImage: cachedSelfieImage,
                    downloadProgress: downloadProgress,
                    imageCacheManager: imageCacheManager
                )
            }
            if cachedContentImage.wrappedValue == nil { 
                loadContentImage(
                    feedPost: feedPost,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    cachedContentImage: cachedContentImage,
                    downloadProgress: downloadProgress,
                    imageCacheManager: imageCacheManager
                )
            }
            if cachedImage.wrappedValue == nil  { 
                loadFallbackImage(
                    feedPost: feedPost,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    cachedImage: cachedImage,
                    downloadProgress: downloadProgress,
                    imageCacheManager: imageCacheManager
                )
            }
        }
    }
    
    // MARK: - Individual Image Loaders
    
    private static func loadSelfieImage(
        feedPost: FeedPost,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        cachedSelfieImage: Binding<UIImage?>,
        downloadProgress: Binding<Double>,
        imageCacheManager: ImageCacheManager
    ) {
        guard let selfieUrl = feedPost.selfieImageUrl,
              let url = URL(string: selfieUrl) else {
            return
        }

        let selfieKey = "\(feedPost.postId.uuidString)_selfie"

        Task {
            // 1️⃣ Return immediately if we already have it in cache (memory or disk).
            if let cached = await imageCacheManager.getCachedImage(for: selfieKey) {
                await MainActor.run { cachedSelfieImage.wrappedValue = cached }
                return
            }

            print("🔄 Loading selfie image via Kingfisher: \(selfieUrl)")

            // Down-sample to the exact on-screen size (× device scale) so we never decode
            // a giant image only to shrink it in the view. This alone can drop memory
            // usage by >80 % on high-resolution photos and removes jank while scrolling.
            let scale = await UIScreen.main.scale
            let targetSize = CGSize(width: cardWidth * scale,
                                    height: cardHeight * scale)

            let options: KingfisherOptionsInfo = [
                .processor(DownsamplingImageProcessor(size: targetSize)),
                .scaleFactor(scale),
                .cacheOriginalImage,
                .backgroundDecode // decode off the main thread
            ]

            KingfisherManager.shared.retrieveImage(
                with: url,
                options: options,
                progressBlock: { received, total in
                    if total > 0 {
                        let prog = Double(received) / Double(total)
                        Task { @MainActor in downloadProgress.wrappedValue = prog }
                    }
                }) { result in
                switch result {
                case .success(let value):
                    Task { @MainActor in
                        cachedSelfieImage.wrappedValue = value.image
                        downloadProgress.wrappedValue = 1.0
                        imageCacheManager.cacheImage(value.image, forKey: selfieKey)
                        print("✅ Selfie image fetched & cached for post: \(feedPost.postId)")
                    }
                case .failure(let error):
                    print("❌ Kingfisher failed to load selfie image: \(error). Retrying in 0.5s")
                    // Retry once after a short delay to mitigate transient network issues.
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        if cachedSelfieImage.wrappedValue == nil {
                            loadSelfieImage(
                                feedPost: feedPost,
                                cardWidth: cardWidth,
                                cardHeight: cardHeight,
                                cachedSelfieImage: cachedSelfieImage,
                                downloadProgress: downloadProgress,
                                imageCacheManager: imageCacheManager
                            )
                        }
                    }
                }
            }
        }
    }
    
    private static func loadContentImage(
        feedPost: FeedPost,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        cachedContentImage: Binding<UIImage?>,
        downloadProgress: Binding<Double>,
        imageCacheManager: ImageCacheManager
    ) {
        guard let contentUrl = feedPost.contentImageUrl,
              let url = URL(string: contentUrl) else {
            return
        }

        let contentKey = "\(feedPost.postId.uuidString)_content"

        Task {
            if let cached = await imageCacheManager.getCachedImage(for: contentKey) {
                await MainActor.run { cachedContentImage.wrappedValue = cached }
                return
            }

            print("🔄 Loading content image via Kingfisher: \(contentUrl)")

            let scale = await UIScreen.main.scale
            let targetSize = CGSize(width: cardWidth * scale,
                                    height: cardHeight * scale)

            let options: KingfisherOptionsInfo = [
                .processor(DownsamplingImageProcessor(size: targetSize)),
                .scaleFactor(scale),
                .cacheOriginalImage,
                .backgroundDecode
            ]

            KingfisherManager.shared.retrieveImage(
                with: url,
                options: options,
                progressBlock: { received, total in
                    if total > 0 {
                        let prog = Double(received) / Double(total)
                        Task { @MainActor in downloadProgress.wrappedValue = prog }
                    }
                }) { result in
                switch result {
                case .success(let value):
                    Task { @MainActor in
                        cachedContentImage.wrappedValue = value.image
                        downloadProgress.wrappedValue = 1.0
                        imageCacheManager.cacheImage(value.image, forKey: contentKey)
                        print("✅ Content image fetched & cached for post: \(feedPost.postId)")
                    }
                case .failure(let error):
                    print("❌ Kingfisher failed to load content image: \(error). Retrying in 0.5s")
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        if cachedContentImage.wrappedValue == nil {
                            loadContentImage(
                                feedPost: feedPost,
                                cardWidth: cardWidth,
                                cardHeight: cardHeight,
                                cachedContentImage: cachedContentImage,
                                downloadProgress: downloadProgress,
                                imageCacheManager: imageCacheManager
                            )
                        }
                    }
                }
            }
        }
    }
    
    /// Loads `imageUrl` (legacy single-image field) into `cachedImage` if present.
    private static func loadFallbackImage(
        feedPost: FeedPost,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        cachedImage: Binding<UIImage?>,
        downloadProgress: Binding<Double>,
        imageCacheManager: ImageCacheManager
    ) {
        guard let fallbackUrl = feedPost.imageUrl,
              let url = URL(string: fallbackUrl) else {
            return
        }

        let baseKey = feedPost.postId.uuidString

        Task {
            // Reuse existing cache helpers to avoid duplicated requests
            if let cached = await imageCacheManager.getCachedImage(for: baseKey) {
                await MainActor.run { cachedImage.wrappedValue = cached }
                return
            }

            print("🔄 Loading fallback image via Kingfisher: \(fallbackUrl)")

            let scale = await UIScreen.main.scale
            let targetSize = CGSize(width: cardWidth * scale,
                                    height: cardHeight * scale)

            let options: KingfisherOptionsInfo = [
                .processor(DownsamplingImageProcessor(size: targetSize)),
                .scaleFactor(scale),
                .cacheOriginalImage,
                .backgroundDecode
            ]

            KingfisherManager.shared.retrieveImage(
                with: url,
                options: options,
                progressBlock: { received, total in
                    if total > 0 {
                        let prog = Double(received) / Double(total)
                        Task { @MainActor in downloadProgress.wrappedValue = prog }
                    }
                }) { result in
                switch result {
                case .success(let value):
                    Task { @MainActor in
                        cachedImage.wrappedValue = value.image
                        downloadProgress.wrappedValue = 1.0
                        imageCacheManager.cacheImage(value.image, forKey: baseKey)
                        print("✅ Fallback image fetched & cached for post: \(feedPost.postId)")
                    }
                case .failure(let error):
                    print("❌ Kingfisher failed to load fallback image: \(error). Retrying in 0.5s")
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        if cachedImage.wrappedValue == nil {
                            loadFallbackImage(
                                feedPost: feedPost,
                                cardWidth: cardWidth,
                                cardHeight: cardHeight,
                                cachedImage: cachedImage,
                                downloadProgress: downloadProgress,
                                imageCacheManager: imageCacheManager
                            )
                        }
                    }
                }
            }
        }
    }
} 