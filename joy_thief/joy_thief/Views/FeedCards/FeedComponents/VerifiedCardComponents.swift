import SwiftUI

struct VerifiedCardFront: View {
    var showingSelfieAsMain: Bool
    let cachedSelfieImage: UIImage?
    let cachedContentImage: UIImage?
    let cachedImage: UIImage?
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onOverlayTap: () -> Void
    let downloadProgress: Double
    /// When `true` the UI will wait until *both* images are available before displaying
    /// anything.  This prevents the flicker where only the main image appears first and
    /// the overlay pops in a split-second later.
    let expectsBothImages: Bool

    // Choose the best available images for display
    private var primaryImage: UIImage? {
        if showingSelfieAsMain {
            return cachedSelfieImage ?? cachedContentImage ?? cachedImage
        } else {
            return cachedContentImage ?? cachedSelfieImage ?? cachedImage
        }
    }

    private var secondaryImage: UIImage? {
        if showingSelfieAsMain {
            return cachedContentImage
        } else {
            return cachedSelfieImage
        }
    }

    // Determines if we have two distinct images ready for the dual-image layout.
    private var hasBothImages: Bool {
        cachedSelfieImage != nil && cachedContentImage != nil
    }

    // Determines if *any* image is currently available. This lets us fall back to a
    // single-image presentation in scenarios where only one of the selfie/content or
    // a legacy fallback image exists. Without this, the user would see an endless
    // loading placeholder even though we already have something worth showing.
    private var hasAtLeastOneImage: Bool {
        primaryImage != nil
    }

    var body: some View {
        Group {
            if expectsBothImages {
                // Posts with BOTH selfie & content: only show once both are ready.
                if hasBothImages, let main = primaryImage, let overlay = secondaryImage {
                    DualImageCardView(
                        mainImage: main,
                        overlayImage: overlay,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        onOverlayTap: onOverlayTap
                    )
                } else {
                    LoadingCardView(
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        progress: downloadProgress
                    )
                }
            } else {
                // Legacy single-image posts: render as soon as we have one.
                if hasAtLeastOneImage, let single = primaryImage {
                    SingleImageCardView(
                        singleImage: single,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight
                    )
                } else {
                    LoadingCardView(
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        progress: downloadProgress
                    )
                }
            }
        }
    }
}

struct VerifiedCardBack: View {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let userName: String
    let habitName: String?
    let habitTypeDisplayName: String?
    let habitType: String?
    let createdAt: Date
    let streakValue: Int
    let progressCurrent: Int?
    let progressTotal: Int?
    let penaltyAmount: Double
    let captionSectionBack: AnyView
    let formatDate: (Date) -> String
    
    var body: some View {
        VStack(spacing: 0) {
            // Card back content
            VStack(spacing: 0) {
                // Centered content
                VStack(spacing: 20) {
                    // Habit name at top
                    if let habitName = habitName {
                        Text(habitName)
                            .jtStyle(.title)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    // Habit type and date section
                    VStack(spacing: 8) {
                        if let habitTypeDisplay = habitTypeDisplayName, let habitTypeRaw = habitType {
                            HStack(spacing: 8) {
                                Group {
                                    if habitTypeRaw.hasPrefix("health_") {
                                        // Health habits use SF Symbols
                                        Image(systemName: HabitIconProvider.iconName(for: habitTypeRaw))
                                            .font(.system(size: 16, weight: .light))
                                            .foregroundColor(.white)
                                            .frame(width: 20, height: 20)
                                    } else if habitTypeRaw == "league_of_legends" || habitTypeRaw == "valorant" || habitTypeRaw == "github_commits" {
                                        Image(HabitIconProvider.iconName(for: habitTypeRaw))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                    } else {
                                        // Regular habits (gym, outdoor, etc.) - show as filled icons
                                        Image(HabitIconProvider.iconName(for: habitTypeRaw))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                    }
                                }
                                
                                Text(habitTypeDisplay)
                                    .jtStyle(.body)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                            }
                        } else if let habitTypeDisplay = habitTypeDisplayName {
                            Text(habitTypeDisplay)
                                .jtStyle(.body)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                        
                        Text(formatDate(createdAt))
                            .jtStyle(.body)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    // Stats section - horizontal layout
                    HStack(spacing: 30) {
                        // Streak
                        VStack(spacing: 4) {
                            Text("streak")
                                .jtStyle(.caption)
                            
                            Text("\(streakValue)")
                                .jtStyle(.title)
                        }
                        
                        // Divider
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 1, height: 40)
                        
                        // Penalty
                        VStack(spacing: 4) {
                            Text("penalty")
                                .jtStyle(.caption)
                            
                            Text("\(String(format: "%.2f", penaltyAmount))")
                                .jtStyle(.title)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 30)
                .padding(.vertical, 40)
            }
            .padding(.horizontal, cardWidth * 0.05)
            .padding(.bottom, cardHeight * 0.04)
        }
    }
} 

struct DualImageCardView: View {
    let mainImage: UIImage
    let overlayImage: UIImage
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onOverlayTap: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Main image with zoom - contained within card frame
            Image(uiImage: mainImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
                .cornerRadius(cardWidth * 0.035)
                .scaleEffect(scale)
                .clipped() // Additional clipping to ensure zoom stays within bounds
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            
                            // Allow zooming during gesture
                            let newScale = scale * delta
                            scale = max(1.0, min(3.0, newScale))
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            // Auto-reset to original state with animation
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scale = 1.0
                            }
                        }
                )
            
            VStack {
                ImageOverlaySection(
                    overlayImage: overlayImage,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    onTap: onOverlayTap
                )
                Spacer()
            }
        }
        .clipped() // Ensure the entire card content stays within bounds
    }
} 

struct SingleImageCardView: View {
    let singleImage: UIImage
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        Image(uiImage: singleImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: cardWidth, height: cardHeight)
            .clipped()
            .cornerRadius(cardWidth * 0.035)
            .scaleEffect(scale)
            .clipped() // Additional clipping to ensure zoom stays within bounds
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        
                        // Allow zooming during gesture
                        let newScale = scale * delta
                        scale = max(1.0, min(3.0, newScale))
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        // Auto-reset to original state with animation
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scale = 1.0
                        }
                    }
            )
    }
}

struct LoadingCardView: View {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let progress: Double

    var body: some View {
        ZStack {
            // Grey placeholder
            RoundedRectangle(cornerRadius: cardWidth * 0.035)
                .fill(Color.gray.opacity(0.3))

            // Progress bar anchored at the bottom
            VStack {
                Spacer()
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .padding(.horizontal, cardWidth * 0.1)
                    .padding(.bottom, cardHeight * 0.03)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

struct ImageOverlaySection: View {
    let overlayImage: UIImage
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onTap: () -> Void

    var body: some View {
        HStack {
            Button(action: {
                onTap()
            }) {
                Image(uiImage: overlayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth * 0.25, height: cardWidth * 0.25)
                    .clipped()
                    .cornerRadius(cardWidth * 0.025)
                    .overlay(
                        RoundedRectangle(cornerRadius: cardWidth * 0.025)
                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .padding(.top, cardHeight * 0.04)
            .padding(.leading, cardWidth * 0.04)
            Spacer()
        }
    }
}
