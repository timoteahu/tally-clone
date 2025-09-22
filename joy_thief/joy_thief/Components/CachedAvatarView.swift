//
//  CachedAvatarView.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//


import SwiftUI
import Kingfisher
import Combine

/// A SwiftUI view that displays user avatars with aggressive caching for instant loading
struct CachedAvatarView: View {
    let url80: String?
    let url200: String?
    let urlOriginal: String?
    let size: AvatarDisplaySize
    let placeholder: String
    let contentMode: SwiftUI.ContentMode
    
    @State private var isLoading = false
    @State private var showLoadingIndicator = false
    @State private var loadingDelayTask: Task<Void, Never>? = nil
    @State private var displayImage: UIImage? = nil
    @State private var currentTargetURL: String? = nil
    @State private var loadingTask: Task<Void, Never>? = nil
    // Combine cancellable to observe shared avatar store updates
    @State private var avatarCancellable: AnyCancellable? = nil
    
    // Add a computed property to track URL identity
    private var urlIdentity: String {
        "\(url80 ?? "")-\(url200 ?? "")-\(urlOriginal ?? "")"
    }
    
    // We use a deterministic identity (hash of URLs) so SwiftUI can reuse the
    // same view instance instead of creating a new one on every scroll.  This
    // eliminates needless image reloads that were causing jank.
    private var identityKey: String {
        urlIdentity // already unique per avatar size set
    }
    
    init(
        url80: String? = nil,
        url200: String? = nil,
        urlOriginal: String? = nil,
        size: AvatarDisplaySize = .medium,
        placeholder: String = "person.crop.circle.fill",
        contentMode: SwiftUI.ContentMode = .fill
    ) {
        self.url80 = url80
        self.url200 = url200
        self.urlOriginal = urlOriginal
        self.size = size
        self.placeholder = placeholder
        self.contentMode = contentMode
        
        // Initialize state
        self._displayImage = State(initialValue: nil)
        self._isLoading = State(initialValue: false)
        self._showLoadingIndicator = State(initialValue: false)
        self._currentTargetURL = State(initialValue: nil)
        self._loadingTask = State(initialValue: nil)
        self._loadingDelayTask = State(initialValue: nil)
    }
    
    /// Returns the best available avatar URL based on requested size, **skipping empty strings** so
    /// that we can still fall back to the next variant when the server sends "" for a particular
    /// resolution.
    private func computeTargetURL() -> URL? {
        // Helper that turns "" into `nil` so the `??` fallback chain works as expected.
        func cleaned(_ str: String?) -> String? {
            guard let str = str, !str.isEmpty else { return nil }
            return str
        }

        // Sanitize all variants once up-front.
        let u80   = cleaned(url80)
        let u200  = cleaned(url200)
        let uOrig = cleaned(urlOriginal)

        let selected: String?
        switch size {
        case .small:
            selected = u80   ?? u200 ?? uOrig
        case .medium:
            selected = u200  ?? uOrig ?? u80
        case .large:
            selected = uOrig ?? u200 ?? u80
        }

        guard let urlString = selected else { return nil }
        return URL(string: urlString)
    }
    

    
    private var targetURL: URL? {
        let url = computeTargetURL()
        
        if let url = url {
            avatarLog("CachedAvatarView: Final URL: \(url.absoluteString)")
        } else {
            avatarLog("CachedAvatarView: No URL available, showing placeholder")
        }
        
        return url
    }
    
    private var frameSize: CGFloat {
        switch size {
        case .small:
            return 35
        case .medium:
            return 54
        case .large:
            return 120
        }
    }
    
    var body: some View {
        Group {
            if let image = displayImage {
                // Show current image
                if contentMode == .fit {
                    // For fit mode, scale image to fit entirely within circle
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: frameSize, height: frameSize)
                        .background(Color.black.opacity(0.1))
                        .clipShape(Circle())
                } else {
                    // For fill mode, scale image to fill entire circle
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: frameSize, height: frameSize)
                        .clipShape(Circle())
                }
            } else {
                // Show placeholder while loading
                placeholderView
            }
        }
        .overlay(
            loadingOverlay
        )
        // Assign a stable identity tied to the avatar URLs so SwiftUI reuses views when
        // they represent the same bitmap, avoiding unnecessary reloads while still
        // preventing incorrect image reuse across *different* avatars.
        .id(identityKey)
        .onChange(of: urlIdentity) { oldValue, _ in
            // URLs changed - cancel old task and load new image
            avatarLog("CachedAvatarView: URL identity changed, reloading image")
            cancelLoadingTask()
            displayImage = nil
            currentTargetURL = nil
            loadImageIfNeeded()
        }
        .task {
            // Load image only once when the view first appears
            loadImageIfNeeded()
            // Subscribe to shared avatar updates so that if another view
            // finishes loading the same avatar we reflect it immediately.
            if avatarCancellable == nil {
                avatarCancellable = AvatarImageStore.shared.$cachedKeys
                    .receive(on: RunLoop.main)
                    .sink { cachedKeys in
                        // Check both current and target URLs for updates
                        let checkKeys = [self.currentTargetURL, self.targetURL?.absoluteString].compactMap { $0 }
                        for key in checkKeys {
                            if cachedKeys.contains(key),
                               let sharedImage = AvatarImageStore.shared.image(for: key) {
                                // Always update if we find a newer image in the store, 
                                // even if we already have one displayed
                                self.displayImage = sharedImage
                                self.isLoading = false
                                self.showLoadingIndicator = false
                                self.loadingDelayTask?.cancel()
                                break
                            }
                        }
                    }
            }
        }
        .onDisappear {
            // Clean up when view disappears
            cancelLoadingTask()
            avatarCancellable?.cancel()
            avatarCancellable = nil
        }
    }
    
    private func cancelLoadingTask() {
        loadingTask?.cancel()
        loadingTask = nil
        loadingDelayTask?.cancel()
        loadingDelayTask = nil
        showLoadingIndicator = false
    }
    
    private func loadImageIfNeeded() {
        guard let url = targetURL else {
            avatarLog("CachedAvatarView: No URL available, showing placeholder")
            displayImage = nil
            isLoading = false
            showLoadingIndicator = false
            loadingDelayTask?.cancel()
            return
        }
        
        let urlString = url.absoluteString
        
        // Skip if already loading this exact URL and we have an image
        if currentTargetURL == urlString && displayImage != nil {
            avatarLog("CachedAvatarView: Already have image for URL: \(urlString)")
            return
        }
        
        avatarLog("CachedAvatarView: Loading image from URL: \(urlString)")
        currentTargetURL = urlString
        
        // 0️⃣ Check if another view already loaded the image this session (immediate check)
        if let sharedImage = AvatarImageStore.shared.image(for: urlString) {
            avatarLog("CachedAvatarView: Found in shared AvatarImageStore")
            displayImage = sharedImage
            isLoading = false
            showLoadingIndicator = false
            loadingDelayTask?.cancel()
            return
        }
        
        // 1️⃣ Try to get from memory cache first (synchronous)
        if let cachedImage = ImageCache.default.retrieveImageInMemoryCache(forKey: urlString) {
            avatarLog("CachedAvatarView: Found in memory cache")
            displayImage = cachedImage
            isLoading = false
            showLoadingIndicator = false
            loadingDelayTask?.cancel()
            AvatarImageStore.shared.set(cachedImage, for: urlString)
            return
        }
        
        // If no immediate image found, start loading
        isLoading = true
        
        // Delay showing loading indicator to prevent flashing
        loadingDelayTask?.cancel()
        loadingDelayTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms delay
            if !Task.isCancelled && isLoading {
                await MainActor.run {
                    showLoadingIndicator = true
                }
            }
        }
        
        // Cancel any previous loading task
        cancelLoadingTask()
        
        // 2️⃣ Try disk cache and network fetch (async)
        loadingTask = Task {
            // First try disk cache
            if let diskImage = try? await ImageCache.default.retrieveImageInDiskCache(forKey: urlString) {
                avatarLog("CachedAvatarView: Found in disk cache – promoting to memory for instant display")
                // Promote to memory cache for faster subsequent displays
                _ = try? await ImageCache.default.store(diskImage, forKey: urlString)
                
                await MainActor.run {
                    // Only update if this task wasn't cancelled and URL is still current
                    guard !Task.isCancelled, self.currentTargetURL == urlString else { return }
                    self.displayImage = diskImage
                    self.isLoading = false
                    self.showLoadingIndicator = false
                    self.loadingDelayTask?.cancel()
                    AvatarImageStore.shared.set(diskImage, for: urlString)
                }
                return
            }
            
            // Check if task was cancelled before network fetch
            guard !Task.isCancelled else { return }

            // 3️⃣ Fallback: network fetch via KingfisherManager
            let options: KingfisherOptionsInfo = [
                .cacheOriginalImage,
                .backgroundDecode,              // Decode in background
                .callbackQueue(.mainAsync),     // Ensure main thread callbacks
                .loadDiskFileSynchronously      // Load disk files synchronously for faster display
            ]

            do {
                let result = try await KingfisherManager.shared.retrieveImage(with: url, options: options)
                
                await MainActor.run {
                    // Only update if this task wasn't cancelled and URL is still current
                    guard !Task.isCancelled, self.currentTargetURL == urlString else { return }
                    self.displayImage = result.image
                    self.isLoading = false
                    self.showLoadingIndicator = false
                    self.loadingDelayTask?.cancel()
                    avatarLog("CachedAvatarView: Successfully loaded image - \(result.cacheType)")
                    // Broadcast the loaded image so all other views can pick it up.
                    AvatarImageStore.shared.set(result.image, for: urlString)
                }
            } catch {
                await MainActor.run {
                    // Only update if this task wasn't cancelled and URL is still current
                    guard !Task.isCancelled, self.currentTargetURL == urlString else { return }
                    self.displayImage = nil
                    self.isLoading = false
                    self.showLoadingIndicator = false
                    self.loadingDelayTask?.cancel()
                    avatarLog("CachedAvatarView: Failed to load image: \(error)")
                }
            }
        }
    }
    
    private var placeholderView: some View {
        Circle()
            .fill(Color.black)
            .frame(width: frameSize, height: frameSize)
            .overlay(
                Image(systemName: placeholder)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: frameSize * 0.6, height: frameSize * 0.6)
                    .foregroundColor(.white.opacity(0.9))
            )
    }
    
    private var loadingOverlay: some View {
        Group {
            if showLoadingIndicator {
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: frameSize, height: frameSize)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    )
            }
        }
    }
}

enum AvatarDisplaySize {
    case small  // 40pt (80px on 2x screens)
    case medium // 72pt (144px on 2x screens)
    case large  // 120pt (240px on 2x screens)
}

// MARK: - Convenience Initializers

extension CachedAvatarView {
    /// Initialize with a User model
    init(user: User?, size: AvatarDisplaySize = .medium, contentMode: SwiftUI.ContentMode = .fill) {
        // Debug logging to see what we're getting
        let dbg = """
        CachedAvatarView: Initializing with user avatar URLs:
          - url80: \(user?.avatarUrl80 ?? "nil")
          - url200: \(user?.avatarUrl200 ?? "nil")
          - urlOriginal: \(user?.avatarUrlOriginal ?? "nil")
          - profilePhotoUrl: \(user?.profilePhotoUrl ?? "nil")
          - avatarVersion: \(user?.avatarVersion ?? -1)
        """
        avatarLog(dbg)
        
        // Fallback to profilePhotoUrl if avatar URLs are not available
        let fallbackUrl80 = user?.avatarUrl80 ?? (user?.profilePhotoUrl?.isEmpty == false ? user?.profilePhotoUrl : nil)
        let fallbackUrl200 = user?.avatarUrl200 ?? (user?.profilePhotoUrl?.isEmpty == false ? user?.profilePhotoUrl : nil)
        let fallbackUrlOriginal = user?.avatarUrlOriginal ?? (user?.profilePhotoUrl?.isEmpty == false ? user?.profilePhotoUrl : nil)
        
        self.init(
            url80: fallbackUrl80,
            url200: fallbackUrl200,
            urlOriginal: fallbackUrlOriginal,
            size: size,
            contentMode: contentMode
        )
    }
}

// MARK: - Preview

struct CachedAvatarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Different sizes
            HStack(spacing: 20) {
                CachedAvatarView(size: .small)
                CachedAvatarView(size: .medium)
                CachedAvatarView(size: .large)
            }
            
            // With URLs (these won't work in preview but show the interface)
            CachedAvatarView(
                url80: "https://example.com/avatar80.jpg",
                url200: "https://example.com/avatar200.jpg",
                urlOriginal: "https://example.com/avatar.jpg",
                size: .medium
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

// MARK: - Lightweight Debug Logger

#if DEBUG
private let avatarLoggingEnabled = false // set to `true` temporarily when debugging avatars
#else
private let avatarLoggingEnabled = false
#endif

@inline(__always)
private func avatarLog(_ msg: @autoclosure () -> String) {
    if avatarLoggingEnabled { print(msg()) }
} 