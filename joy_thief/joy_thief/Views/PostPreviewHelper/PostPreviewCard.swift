import SwiftUI

struct PostPreviewCard: View {
    let verificationId: String
    let onPublish: (String) -> Void
    let onCancel: () -> Void
    
    @State private var feedPost: FeedPost?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var caption: String = ""
    @State private var originalCaption: String = ""
    @State private var isUpdatingCaption = false
    @State private var showingSelfieAsMain = false
    @State private var cachedContentImage: UIImage?
    @State private var cachedSelfieImage: UIImage?
    
    @FocusState private var isCaptionFocused: Bool
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var feedManager: FeedManager
    
    // Keyboard handling
    @StateObject private var keyboard = KeyboardObserver()
    
    // MARK: - New loading state for images
    @State private var areImagesLoaded = false
    @State private var expectedImageCount = 0
    @State private var imagesLoadedCount = 0
    
    // Computed progress for determinate progress view
    private var loadingProgress: Double {
        guard expectedImageCount > 0 else { return 0 }
        return min(1.0, Double(imagesLoadedCount) / Double(expectedImageCount))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background overlay
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Dismiss keyboard when tapping outside
                        hideKeyboard()
                    }
                
                if isLoading {
                    loadingView
                } else if !areImagesLoaded {
                    loadingView
                } else if let feedPost = feedPost {
                    postPreviewContent(feedPost: feedPost, geometry: geometry)
                } else if let errorMessage = errorMessage {
                    errorView(errorMessage)
                }
            }
        }
        .background(Color.black.opacity(0.95))
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
        .onAppear {
            Task {
                await loadPostData()
            }
        }
    }
    
    // MARK: - Views
    
    private var loadingView: some View {
        // Full-screen, centered indeterminate loading bar on a black background
        VStack {
            // Use determinate bar when we know total image count, otherwise fallback
            if expectedImageCount > 0 {
                ProgressView(value: loadingProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .frame(maxWidth: 200)
            } else {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .frame(maxWidth: 200)
            }
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.custom("EBGaramond-Regular", size: 50))
                .foregroundColor(.red)
            
            Text("Error")
                .jtStyle(.title)
                .foregroundColor(.white)
            
            Text(message)
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            Button("OK") {
                onCancel()
            }
            .font(.ebGaramondBody)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(25)
        }
        .padding(.horizontal, 40)
    }
    
    private func postPreviewContent(feedPost: FeedPost, geometry: GeometryProxy) -> some View {
        // Calculate responsive dimensions
        let availableWidth = geometry.size.width
        let availableHeight = geometry.size.height
        let safeAreaInsets = geometry.safeAreaInsets
        
        // Adaptive card sizing – now nearly full-width for a more immersive preview
        let horizontalPadding: CGFloat = min(20, availableWidth * 0.05)
        let cardWidth: CGFloat = availableWidth - horizontalPadding * 2
        // Preserve SwipeableFeedCard aspect ratio (≈ 1.3 – 1.4) but keep it within 75 % of the screen height
        let idealCardHeight = cardWidth * 1.3
        let cardHeight: CGFloat = min(idealCardHeight, availableHeight * 0.65)
        
        // STATIC layout – no scrolling. We shift the caption section up when keyboard appears.
        let verticalSpacing: CGFloat = min(10, availableHeight * 0.018)
        // Dynamic shrink factor
        let shrinkFactor: CGFloat = keyboard.height == 0 ? 1.0 : 0.6

        return VStack(spacing: verticalSpacing) {
            // Header (animates up with keyboard so card never covers it)
            Text("Post Preview")
                .font(.custom("EBGaramond-Regular", size: 18)).fontWeight(.semibold)
                .foregroundColor(.white)
                .offset(y: keyboard.height == 0 ? 0 : -keyboard.height * 0.25)
                .animation(.easeInOut(duration: 0.3), value: keyboard.height)
            
            // Post preview card – real frame resize to preserve ratio
            feedCardPreview(feedPost: feedPost, cardWidth: cardWidth, cardHeight: cardHeight)
                .scaleEffect(shrinkFactor)
                .offset(y: keyboard.height == 0 ? 0 : -keyboard.height * 0.10)
                .animation(.easeInOut(duration: 0.3), value: keyboard.height)
            
            // Caption + buttons container
            VStack(spacing: 12) {
                captionInputSection(geometry: geometry)
                actionButtonsSection(geometry: geometry)
            }
            // Slide the caption container upward when keyboard appears, but keep it slightly lower to avoid overlapping the image
            .offset(y: -keyboard.height * 0.22)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, max(4, safeAreaInsets.top * 0.20))
        // Lift the whole content a bit higher when the keyboard is visible so the send button isn't covered
        .padding(.bottom, keyboard.height == 0 ? 0 : keyboard.height - safeAreaInsets.bottom + 10)
        .animation(.easeInOut(duration: 0.3), value: keyboard.height)
        // Allow tapping anywhere (except the text field) to dismiss keyboard without blocking buttons
        .simultaneousGesture(
            TapGesture().onEnded {
                hideKeyboard()
            }
        )
        .clipped()
    }
    
    private func feedCardPreview(feedPost: FeedPost, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        ZStack {
            // Card background (matching SwipeableFeedCard)
            RoundedRectangle(cornerRadius: cardWidth * 0.07)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: cardWidth * 0.07)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(
                    color: Color.black.opacity(0.3),
                    radius: 20,
                    x: 0,
                    y: 4
                )
            
            // Card content (exactly like SwipeableFeedCard)
            feedCardContent(feedPost: feedPost, cardWidth: cardWidth, cardHeight: cardHeight)
        }
        .frame(width: cardWidth, height: cardHeight)
    }
    
    private func feedCardContent(feedPost: FeedPost, cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        Group {
            // UPDATED: Check for both selfie and content images first (dual image mode)
            if let mainImage = showingSelfieAsMain ? cachedSelfieImage : cachedContentImage,
               let overlayImage = showingSelfieAsMain ? cachedContentImage : cachedSelfieImage {
                ZStack {
                    // Main image (full size)
                    Image(uiImage: mainImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .cornerRadius(cardWidth * 0.07)
                    
                    // Overlay elements (matching SwipeableFeedCard)
                    VStack {
                        HStack {
                            // Image overlay (top left) - tappable to switch main/overlay
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showingSelfieAsMain.toggle()
                                }
                            }) {
                                Image(uiImage: overlayImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: cardWidth * 0.25, height: cardWidth * 0.25)
                                    .clipped()
                                    .cornerRadius(cardWidth * 0.035)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: cardWidth * 0.035)
                                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                                    )
                                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                            .padding(.top, cardHeight * 0.04)
                            .padding(.leading, cardWidth * 0.04)
                            
                            Spacer()
                        }
                        
                        Spacer()
                        
                        // User name and details at bottom
                        HStack {
                            VStack(alignment: .leading, spacing: cardHeight * 0.005) {
                                Text(feedPost.userName)
                                    .font(.custom("EBGaramond-Regular", size: cardWidth * 0.045)).fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text(timeAgo(from: feedPost.createdAt))
                                    .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                // Show caption preview if available
                                if !caption.isEmpty {
                                    Text(caption)
                                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.032))
                                        .foregroundColor(.white.opacity(0.9))
                                        .lineLimit(2)
                                        .padding(.top, cardHeight * 0.002)
                                } else if let originalCaption = feedPost.caption, !originalCaption.isEmpty, originalCaption != "Habit verification completed" {
                                    Text(originalCaption)
                                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.032))
                                        .foregroundColor(.white.opacity(0.9))
                                        .lineLimit(2)
                                        .padding(.top, cardHeight * 0.002)
                                }
                            }
                            .padding(.horizontal, cardWidth * 0.03)
                            .padding(.vertical, cardHeight * 0.01)
                            .background(
                                RoundedRectangle(cornerRadius: cardWidth * 0.02)
                                    .fill(Color.black.opacity(0.6))
                            )
                            .padding(.bottom, cardHeight * 0.02)
                            .padding(.leading, cardWidth * 0.04)
                            
                            Spacer()
                            
                            // Preview indicator
                            VStack(spacing: cardHeight * 0.01) {
                                Text("Preview")
                                    .jtStyle(.caption)
                                    .foregroundColor(.blue)
                                HStack(spacing: cardWidth * 0.01) {
                                    Image(systemName: "eye")
                                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025))
                                        .foregroundColor(.blue.opacity(0.8))
                                    Text("0")
                                        .jtStyle(.caption)
                                        .foregroundColor(.blue.opacity(0.8))
                                    Image(systemName: "message")
                                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025))
                                        .foregroundColor(.blue.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, cardWidth * 0.03)
                            .padding(.vertical, cardHeight * 0.01)
                            .background(
                                RoundedRectangle(cornerRadius: cardWidth * 0.02)
                                    .fill(Color.blue.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: cardWidth * 0.02)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .padding(.bottom, cardHeight * 0.02)
                            .padding(.trailing, cardWidth * 0.04)
                        }
                    }
                }
            }
            // UPDATED: Fallback to single image mode (backwards compatibility)
            else if let singleImage = cachedContentImage ?? cachedSelfieImage {
                Image(uiImage: singleImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .cornerRadius(cardWidth * 0.07)
                    .overlay(
                        // User name at bottom
                        VStack {
                            Spacer()
                            HStack {
                                VStack(alignment: .leading, spacing: cardHeight * 0.005) {
                                    Text(feedPost.userName)
                                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.045)).fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    Text(timeAgo(from: feedPost.createdAt))
                                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035))
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    // Show caption preview if available
                                    if !caption.isEmpty {
                                        Text(caption)
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.032))
                                            .foregroundColor(.white.opacity(0.9))
                                            .lineLimit(2)
                                            .padding(.top, cardHeight * 0.002)
                                    } else if let originalCaption = feedPost.caption, !originalCaption.isEmpty, originalCaption != "Habit verification completed" {
                                        Text(originalCaption)
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.032))
                                            .foregroundColor(.white.opacity(0.9))
                                            .lineLimit(2)
                                            .padding(.top, cardHeight * 0.002)
                                    }
                                }
                                .padding(.horizontal, cardWidth * 0.03)
                                .padding(.vertical, cardHeight * 0.01)
                                .background(
                                    RoundedRectangle(cornerRadius: cardWidth * 0.02)
                                        .fill(Color.black.opacity(0.6))
                                )
                                .padding(.bottom, cardHeight * 0.02)
                                .padding(.leading, cardWidth * 0.04)
                                
                                Spacer()
                                
                                // Preview indicator
                                VStack(spacing: cardHeight * 0.01) {
                                    Text("Preview")
                                        .jtStyle(.caption)
                                        .foregroundColor(.blue)
                                    HStack(spacing: cardWidth * 0.01) {
                                        Image(systemName: "eye")
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025))
                                            .foregroundColor(.blue.opacity(0.8))
                                        Text("0")
                                            .jtStyle(.caption)
                                            .foregroundColor(.blue.opacity(0.8))
                                        Image(systemName: "message")
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025))
                                            .foregroundColor(.blue.opacity(0.8))
                                    }
                                }
                                .padding(.horizontal, cardWidth * 0.03)
                                .padding(.vertical, cardHeight * 0.01)
                                .background(
                                    RoundedRectangle(cornerRadius: cardWidth * 0.02)
                                        .fill(Color.blue.opacity(0.2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: cardWidth * 0.02)
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                        )
                                )
                                .padding(.bottom, cardHeight * 0.02)
                                .padding(.trailing, cardWidth * 0.04)
                            }
                        }
                    )
            }
            // Loading state
            else {
                // Placeholder with centered linear loading bar while images load
                RoundedRectangle(cornerRadius: cardWidth * 0.07)
                    .fill(Color.black)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            .frame(maxWidth: cardWidth * 0.6)
                    )
            }
        }
        .onAppear {
            loadImages()
        }
    }
    
    private func captionInputSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a caption")
                .font(.custom("EBGaramond-Regular", size: min(16, geometry.size.width * 0.042)))
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            TextField("Share your thoughts about this achievement...", text: $caption, axis: .vertical)
                .focused($isCaptionFocused)
                .textFieldStyle(.plain)
                .font(.custom("EBGaramond-Regular", size: min(14, geometry.size.width * 0.038)))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isCaptionFocused ? Color.blue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .lineLimit(3...5)
        }
    }
    
    private func actionButtonsSection(geometry: GeometryProxy) -> some View {
        HStack(spacing: 16) {
            Button(action: {
                Task {
                    await updateCaptionAndPublish()
                }
            }) {
                HStack {
                    if isUpdatingCaption {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.custom("EBGaramond-Regular", size: 16))
                    }
                    Text(isUpdatingCaption ? "Publishing..." : "Share Post")
                        .font(.custom("EBGaramond-Regular", size: min(18, geometry.size.width * 0.045)))
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(12)
            }
            .disabled(isUpdatingCaption)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadPostData() async {
        print("🎬 [PostPreview] Starting to load post data for verification: \(verificationId)")
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            print("❌ [PostPreview] No authentication token available")
            await MainActor.run {
                errorMessage = "Authentication required"
                isLoading = false
            }
            return
        }
        
        print("🔐 [PostPreview] Using auth token: \(token.prefix(20))...")
        
        guard let url = URL(string: "\(AppConfig.baseURL)/feed/post/by-verification/\(verificationId)") else {
            print("❌ [PostPreview] Invalid URL: \(AppConfig.baseURL)/feed/post-by-verification/\(verificationId)")
            await MainActor.run {
                errorMessage = "Invalid URL configuration"
                isLoading = false
            }
            return
        }
        
        print("🌐 [PostPreview] Making request to: \(url.absoluteString)")
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30.0 // Add timeout
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            print("📡 [PostPreview] Received response with \(data.count) bytes")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [PostPreview] Invalid HTTP response type")
                throw URLError(.badServerResponse)
            }
            
            print("🔍 [PostPreview] HTTP Status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ [PostPreview] HTTP Error \(httpResponse.statusCode): \(responseString)")
                
                let errorMessage = switch httpResponse.statusCode {
                case 404: "Post not found - verification may not have created a post yet"
                case 401: "Authentication expired - please log in again"
                case 500: "Server error - please try again"
                default: "Server error (\(httpResponse.statusCode))"
                }
                throw PostPreviewError.serverError(errorMessage)
            }
            
            print("✅ [PostPreview] Successfully received post data, parsing JSON...")
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                let formatters = [
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"),
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"),
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ss'Z'"),
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX"),
                    createDateFormatter("yyyy-MM-dd HH:mm:ss.SSSSSS"),
                    createDateFormatter("yyyy-MM-dd HH:mm:ss")
                ]
                
                for formatter in formatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }
                
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
            }
            
            let post = try decoder.decode(FeedPost.self, from: data)
            print("🎯 [PostPreview] Successfully parsed FeedPost:")
            print("   - Post ID: \(post.postId)")
            print("   - User: \(post.userName)")
            print("   - Caption: \(post.caption ?? "nil")")
            print("   - Content Image URL: \(post.contentImageUrl ?? "nil")")
            print("   - Selfie Image URL: \(post.selfieImageUrl ?? "nil")")
            
            await MainActor.run {
                self.feedPost = post
                self.caption = post.caption == "Habit verification completed" ? "" : (post.caption ?? "")
                self.originalCaption = post.caption == "Habit verification completed" ? "" : (post.caption ?? "")
                
                // Determine how many images we need before showing the preview
                self.expectedImageCount = 0
                if post.contentImageUrl != nil { 
                    self.expectedImageCount += 1
                    print("📸 [PostPreview] Found content image URL")
                }
                if post.selfieImageUrl != nil { 
                    self.expectedImageCount += 1 
                    print("🤳 [PostPreview] Found selfie image URL")
                }
                
                print("🔢 [PostPreview] Expected image count: \(self.expectedImageCount)")
                
                // If there are no images to load, we can mark them as loaded immediately
                if self.expectedImageCount == 0 {
                    print("⚡ [PostPreview] No images to load, marking as ready")
                    self.areImagesLoaded = true
                } else {
                    print("📥 [PostPreview] Starting to load \(self.expectedImageCount) images")
                    self.areImagesLoaded = false
                    self.imagesLoadedCount = 0
                    // Start loading images as soon as post data arrives
                    self.loadImages()
                }
                isLoading = false
            }
            
            // Immediately push this post into the in-memory feed and cache so the UI updates without waiting for the next refresh
            await feedManager.insertOrUpdatePost(post)
            print("✅ [PostPreview] Post data loaded and cached successfully")
            
        } catch {
            print("❌ [PostPreview] Error loading post data: \(error)")
            if let urlError = error as? URLError {
                print("❌ [PostPreview] URLError details:")
                print("   - Code: \(urlError.code)")
                print("   - Description: \(urlError.localizedDescription)")
                print("   - URL: \(urlError.failingURL?.absoluteString ?? "nil")")
            }
            
            await MainActor.run {
                let userFriendlyMessage = switch error {
                case let urlError as URLError where urlError.code == .timedOut:
                    "Request timed out - check your internet connection"
                case let urlError as URLError where urlError.code == .notConnectedToInternet:
                    "No internet connection"
                case let urlError as URLError where urlError.code == .cannotConnectToHost:
                    "Cannot connect to server - server may be down"
                default:
                    "Failed to load post: \(error.localizedDescription)"
                }
                
                errorMessage = userFriendlyMessage
                isLoading = false
            }
        }
    }
    
    private func loadImages() {
        // Avoid duplicate work if we already have everything
        guard !areImagesLoaded, let feedPost = feedPost else { 
            print("⚠️ [PostPreview] loadImages called but images already loaded or no feedPost")
            return 
        }
        
        print("📸 [PostPreview] Starting image loading process...")
        print("   - Content URL: \(feedPost.contentImageUrl ?? "nil")")
        print("   - Selfie URL: \(feedPost.selfieImageUrl ?? "nil")")
        
        // Load content image
        if let contentImageUrl = feedPost.contentImageUrl, let url = URL(string: contentImageUrl) {
            print("📥 [PostPreview] Loading content image from: \(url.absoluteString)")
            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("📸 [PostPreview] Content image response: \(httpResponse.statusCode)")
                        guard httpResponse.statusCode == 200 else {
                            print("❌ [PostPreview] Content image HTTP error: \(httpResponse.statusCode)")
                            await MainActor.run { imageDidLoad() }
                            return
                        }
                    }
                    
                    if let image = UIImage(data: data) {
                        print("✅ [PostPreview] Content image loaded successfully - Size: \(image.size)")
                        await MainActor.run {
                            cachedContentImage = image
                            imageDidLoad()
                        }
                    } else {
                        print("❌ [PostPreview] Failed to create UIImage from content image data")
                        await MainActor.run { imageDidLoad() }
                    }
                } catch {
                    print("❌ [PostPreview] Failed to load content image: \(error)")
                    if let urlError = error as? URLError {
                        print("   - URLError code: \(urlError.code)")
                        print("   - Description: \(urlError.localizedDescription)")
                    }
                    await MainActor.run { imageDidLoad() }
                }
            }
        } else {
            print("⚠️ [PostPreview] No valid content image URL")
        }
        
        // Load selfie image
        if let selfieImageUrl = feedPost.selfieImageUrl, let url = URL(string: selfieImageUrl) {
            print("📥 [PostPreview] Loading selfie image from: \(url.absoluteString)")
            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("🤳 [PostPreview] Selfie image response: \(httpResponse.statusCode)")
                        guard httpResponse.statusCode == 200 else {
                            print("❌ [PostPreview] Selfie image HTTP error: \(httpResponse.statusCode)")
                            await MainActor.run { imageDidLoad() }
                            return
                        }
                    }
                    
                    if let image = UIImage(data: data) {
                        print("✅ [PostPreview] Selfie image loaded successfully - Size: \(image.size)")
                        await MainActor.run {
                            cachedSelfieImage = image
                            imageDidLoad()
                        }
                    } else {
                        print("❌ [PostPreview] Failed to create UIImage from selfie image data")
                        await MainActor.run { imageDidLoad() }
                    }
                } catch {
                    print("❌ [PostPreview] Failed to load selfie image: \(error)")
                    if let urlError = error as? URLError {
                        print("   - URLError code: \(urlError.code)")
                        print("   - Description: \(urlError.localizedDescription)")
                    }
                    await MainActor.run { imageDidLoad() }
                }
            }
        } else {
            print("⚠️ [PostPreview] No valid selfie image URL")
        }
        
        // Add timeout for image loading
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            if !areImagesLoaded {
                print("⏰ [PostPreview] Image loading timeout reached, marking as complete")
                await MainActor.run {
                    areImagesLoaded = true
                }
            }
        }
    }
    
    // Increment the loaded image counter and update the readiness flag
    private func imageDidLoad() {
        print("📊 [PostPreview] Image loaded - Count: \(imagesLoadedCount + 1)/\(expectedImageCount)")
        
        // Increment if we still expect more
        if imagesLoadedCount < expectedImageCount {
            imagesLoadedCount += 1
        }
        // Clamp to expected count
        if imagesLoadedCount >= expectedImageCount {
            print("🎉 [PostPreview] All images loaded! Showing preview")
            areImagesLoaded = true
        }
        
        print("📈 [PostPreview] Image loading progress: \(imagesLoadedCount)/\(expectedImageCount) - Ready: \(areImagesLoaded)")
    }
    
    private func updateCaptionAndPublish() async {
        guard let feedPost = feedPost else { return }
        
        await MainActor.run {
            isUpdatingCaption = true
        }
        
        // Update caption if it's not empty and different from original
        if !caption.isEmpty && caption != originalCaption {
            await updateCaption(verificationId: verificationId, caption: caption)
            
            // Update the FeedManager's cached post with the new caption
            await MainActor.run {
                feedManager.updatePostCaption(postId: feedPost.postId, newCaption: caption)
            }
        }
        
        await MainActor.run {
            isUpdatingCaption = false
            onPublish(caption)
        }
    }
    
    private func updateCaption(verificationId: String, caption: String) async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            return
        }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/feed/update-caption") else {
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = [
                "verification_id": verificationId,
                "caption": caption
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                print("✅ [PostPreview] Successfully updated post caption")
            } else {
                print("⚠️ [PostPreview] Failed to update post caption")
            }
        } catch {
            print("❌ [PostPreview] Error updating post caption: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
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
    
    private func createDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Error Types

enum PostPreviewError: Error, LocalizedError {
    case serverError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return message
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// Helper to react to keyboard events so we can slide content when typing
class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    private var showObserver: Any?
    private var hideObserver: Any?
    init() {
        showObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.height = frame.height
                }
            }
        }
        hideObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.height = 0
            }
        }
    }
    deinit {
        if let showObserver {
            NotificationCenter.default.removeObserver(showObserver)
        }
        if let hideObserver {
            NotificationCenter.default.removeObserver(hideObserver)
        }
    }
}

#Preview {
    PostPreviewCard(
        verificationId: "preview-verification-id",
        onPublish: { caption in
            print("Published with caption: \(caption)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
    .environmentObject(AuthenticationManager.shared)
}


