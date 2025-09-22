//
//  CompactImageVerificationView.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//

import SwiftUI

struct CompactImageVerificationView: View {
    let placeholderText: String
    let habitType: String
    @Binding var selfieImageData: Data?
    @Binding var contentImageData: Data?
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    @Binding var cameraMode: SwipeableHabitCard.CameraMode
    @Binding var showingCamera: Bool
    @Binding var isVerifying: Bool
    @Binding var firstImageTaken: Bool
    let verifyWithBothImages: (String, String) async -> Void
    let getSuccessMessage: (String) -> String
    let resetVerificationState: () -> Void
    
    // Cache UIImage instances to prevent recreation on re-renders
    @State private var cachedSelfieImage: UIImage?
    @State private var cachedContentImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            // Two-image layout side by side
            HStack(spacing: cardWidth * 0.02) {
                // Selfie image section (always front camera)
                VStack(spacing: cardHeight * 0.01) {
                    Text("take a selfie")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035)).fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.bottom, 2)
                    
                    Group {
                        if let cachedImage = cachedSelfieImage {
                            Image(uiImage: cachedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth * 0.42, height: cardHeight * 0.42)
                                .clipShape(RoundedRectangle(cornerRadius: cardWidth * 0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cardWidth * 0.03)
                                        .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                .drawingGroup()
                                .animation(.easeInOut(duration: 0.2), value: cachedSelfieImage)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            RoundedRectangle(cornerRadius: cardWidth * 0.03)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: cardWidth * 0.42, height: cardHeight * 0.42)
                                .overlay(
                                    VStack(spacing: cardHeight * 0.008) {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.05))
                                            .foregroundColor(.white.opacity(0.5))
                                        Text("snap a picture")
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028)).fontWeight(.medium)
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                )
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        }
                    }
                }
                
                // Content image section (always rear camera)
                VStack(spacing: cardHeight * 0.01) {
                    Text("then activity")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035)).fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.bottom, 2)
                    
                    Group {
                        if let cachedImage = cachedContentImage {
                            Image(uiImage: cachedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth * 0.42, height: cardHeight * 0.42)
                                .clipShape(RoundedRectangle(cornerRadius: cardWidth * 0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cardWidth * 0.03)
                                        .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                .drawingGroup()
                                .animation(.easeInOut(duration: 0.2), value: cachedContentImage)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            RoundedRectangle(cornerRadius: cardWidth * 0.03)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: cardWidth * 0.42, height: cardHeight * 0.42)
                                .overlay(
                                    VStack(spacing: cardHeight * 0.008) {
                                        Image(systemName: "camera.fill")
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.045))
                                            .foregroundColor(.white.opacity(0.5))
                                        Text("auto-captured")
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028)).fontWeight(.medium)
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                )
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, cardWidth * 0.02)
            
            
            // Reduce vertical gap between images and buttons for better fit
            Spacer().frame(height: cardHeight * 0.04)
            
            // Action buttons at the bottom
            VStack(spacing: cardHeight * 0.015) {
                if selfieImageData == nil && contentImageData == nil {
                    Button(action: { 
                        cameraMode = .selfie
                        firstImageTaken = false
                        showingCamera = true 
                    }) {
                        HStack(spacing: cardWidth * 0.02) {
                            Text("verify")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.038)).fontWeight(.semibold)
                        }
                        .padding(.vertical, cardHeight * 0.02)
                        .padding(.horizontal, cardWidth * 0.15)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: cardWidth * 0.015)
                                .stroke(Color.white, lineWidth: 1.5)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(cardWidth * 0.015)
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                } else if selfieImageData != nil && contentImageData != nil {
                    // Both images taken - verify
                    Button(action: { 
                        Task { 
                            await verifyWithBothImages(
                                habitType, 
                                getSuccessMessage(habitType)
                            ) 
                        } 
                    }) {
                        Text(isVerifying ? "verifying..." : "verify")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.038)).fontWeight(.semibold)
                            .padding(.vertical, cardHeight * 0.02)
                            .padding(.horizontal, cardWidth * 0.15)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: cardWidth * 0.015)
                                    .stroke(Color.white, lineWidth: 1.5)
                            )
                            .foregroundColor(.white)
                            .cornerRadius(cardWidth * 0.015)
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                    .disabled(isVerifying)
                    
                    Button(action: { 
                        resetVerificationState()
                    }) {
                        HStack(spacing: cardWidth * 0.02) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04))
                            Text("retake")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.038)).fontWeight(.semibold)
                        }
                        .padding(.horizontal, cardWidth * 0.15)
                        .background(Color.clear)
                        .foregroundColor(.white)
                        .cornerRadius(cardWidth * 0.015)
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .padding(.horizontal, cardWidth * 0.02)
            .padding(.bottom, cardHeight * 0.02)
        }
        .onChange(of: selfieImageData) { _, newData in
            cachedSelfieImage = newData.flatMap { UIImage(data: $0) }
        }
        .onChange(of: contentImageData) { _, newData in
            cachedContentImage = newData.flatMap { UIImage(data: $0) }
        }
        .onAppear {
            // Initialize cached images on appear
            cachedSelfieImage = selfieImageData.flatMap { UIImage(data: $0) }
            cachedContentImage = contentImageData.flatMap { UIImage(data: $0) }
        }
    }
}

