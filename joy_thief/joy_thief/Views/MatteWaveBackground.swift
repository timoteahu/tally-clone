import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Wave-shaped highlight
struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)

        // Adjust these control points for different curves
        p.addCurve(
            to:    CGPoint(x: rect.maxX, y: rect.height * 0.38),
            control1: CGPoint(x: rect.width * 0.25, y: rect.height * 0.05),
            control2: CGPoint(x: rect.width * 0.75, y: rect.height * 0.12)
        )

        // Close the bottom edges
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0,        y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

extension WaveShape {
    /// A silvery gradient that blends into black using `.screen` blend mode
    var fillStyle: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(white: 0.35),    // lighter ridge
                Color(white: 0.12),    // mid-tone
                Color(white: 0.02),    // almost black
                .black                 // fade completely into background
            ],
            startPoint: .topLeading,
            endPoint:   .bottomTrailing
        )
    }
}

// MARK: - Procedural noise overlay
struct NoiseView: View {
    @State private var noise: Image?

    var body: some View {
        GeometryReader { geo in
            (noise ?? Image(systemName: "square.fill")) // placeholder while generating
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .blendMode(.overlay)
                .opacity(0.15)
                .task {
                    // Generate once per view size and keep it
                    let uiImage = generateGrain(size: geo.size)
                    noise = Image(uiImage: uiImage)
                }
        }
    }

    private func generateGrain(size: CGSize) -> UIImage {
        // 1. Random CoreImage noise
        let noiseFilter = CIFilter.randomGenerator()
        let ciImage    = noiseFilter.outputImage!
            .cropped(to: CGRect(origin: .zero, size: size))

        // 2. Turn CIImage into UIImage
        let context    = CIContext()
        let cgImage    = context.createCGImage(ciImage, from: ciImage.extent)!
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Convenience wrapper for use as a wallpaper
struct MatteWaveBackground: View {
    var body: some View {
        ZStack {
            Color.black // base

            // S-curve highlight
            WaveShape()
                .fill(WaveShape().fillStyle)
                .opacity(0.8)              // keep highlight subtle
                .blur(radius: 60)          // softer transition
                .blendMode(.screen)        // lift light tones only

            // Grain texture
            NoiseView()
        }
        .ignoresSafeArea()                 // full-screen wallpaper
    }
} 