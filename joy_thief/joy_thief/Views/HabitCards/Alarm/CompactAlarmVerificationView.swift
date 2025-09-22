//
//  CompactAlarmVerificationView.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//

import SwiftUI

struct CompactAlarmVerificationView: View {
    let habit: Habit
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    @Binding var selfieImageData: Data?
    @Binding var contentImageData: Data?
    let isVerifying: Bool
    @Binding var cameraMode: SwipeableHabitCard.CameraMode
    @Binding var showingCamera: Bool
    let verifyWithBothImages: (String, String) async -> Void
    let getSuccessMessage: (String) -> String
    
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
                                "alarm", 
                                getSuccessMessage("alarm")
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
                        selfieImageData = nil
                        contentImageData = nil
                        cameraMode = .selfie
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

struct CompactAlarmImageVerificationView: View {
    let placeholderText: String
    @Binding var selfieImageData: Data?
    @Binding var contentImageData: Data?
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isVerifying: Bool
    @Binding var cameraMode: SwipeableHabitCard.CameraMode
    @Binding var showingCamera: Bool
    let verifyWithBothImages: (String, String) async -> Void
    let getSuccessMessage: (String) -> String
    
    // Cache UIImage instances to prevent recreation on re-renders
    @State private var cachedSelfieImage: UIImage?
    @State private var cachedContentImage: UIImage?

    var body: some View {
        VStack(spacing: cardHeight * 0.008) {
            HStack(spacing: cardWidth * 0.01) {
                VStack(spacing: cardHeight * 0.002) {
                    Text("Selfie")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.022))
                        .foregroundColor(.white.opacity(0.7))
                    Group {
                        if let selfieData = selfieImageData, let uiImage = UIImage(data: selfieData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: cardWidth * 0.35, height: cardHeight * 0.1)
                                .clipped()
                                .cornerRadius(cardWidth * 0.012)
                                .overlay(
                                    RoundedRectangle(cornerRadius: cardWidth * 0.012)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: cardWidth * 0.012)
                                .fill(Color.white.opacity(0.04))
                                .frame(width: cardWidth * 0.35, height: cardHeight * 0.1)
                                .overlay(
                                    VStack(spacing: cardHeight * 0.001) {
                                        Image(systemName: "person.crop.circle")
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025))
                                            .foregroundColor(.white.opacity(0.3))
                                        Text("Auto")
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.018))
                                            .foregroundColor(.white.opacity(0.3))
                                    }
                                )
                        }
                    }
                }
                VStack(spacing: cardHeight * 0.002) {
                    Text("Bathroom")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.022))
                        .foregroundColor(.white.opacity(0.7))
                    Group {
                        if let contentData = contentImageData, let uiImage = UIImage(data: contentData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: cardWidth * 0.35, height: cardHeight * 0.1)
                                .clipped()
                                .cornerRadius(cardWidth * 0.012)
                                .overlay(
                                    RoundedRectangle(cornerRadius: cardWidth * 0.012)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: cardWidth * 0.012)
                                .fill(Color.white.opacity(0.04))
                                .frame(width: cardWidth * 0.35, height: cardHeight * 0.1)
                                .overlay(
                                    VStack(spacing: cardHeight * 0.001) {
                                        Image(systemName: "camera.fill")
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025))
                                            .foregroundColor(.white.opacity(0.3))
                                        Text("Photo")
                                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.018))
                                            .foregroundColor(.white.opacity(0.3))
                                    }
                                )
                        }
                    }
                }
            }
            
            VStack(spacing: cardHeight * 0.006) {
                if selfieImageData == nil {
                    Button(action: {
                        cameraMode = .selfie
                        showingCamera = true
                    }) {
                        HStack(spacing: cardWidth * 0.01) {
                            Image(systemName: "camera.fill")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))
                            Text("Take Selfie")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, cardHeight * 0.01)
                        .background(
                            RoundedRectangle(cornerRadius: cardWidth * 0.015)
                                .fill(Color.white.opacity(0.08))
                        )
                        .foregroundColor(.white)
                    }
                } else if contentImageData == nil {
                    Button(action: {
                        cameraMode = .content
                        showingCamera = true
                    }) {
                        HStack(spacing: cardWidth * 0.01) {
                            Image(systemName: "camera.fill")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))
                            Text("Take Bathroom Photo")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, cardHeight * 0.01)
                        .background(
                            RoundedRectangle(cornerRadius: cardWidth * 0.015)
                                .fill(Color.white.opacity(0.08))
                        )
                        .foregroundColor(.white)
                    }
                } else {
                    Button(action: {
                        Task {
                            await verifyWithBothImages("alarm", getSuccessMessage("alarm"))
                        }
                    }) {
                        HStack(spacing: cardWidth * 0.01) {
                            if isVerifying {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))
                            }
                            Text(isVerifying ? "Verifying..." : "Verify")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, cardHeight * 0.01)
                        .background(
                            RoundedRectangle(cornerRadius: cardWidth * 0.015)
                                .fill(Color.white.opacity(0.08))
                        )
                        .foregroundColor(.white)
                    }
                    .disabled(isVerifying)
                    
                    Button(action: {
                        selfieImageData = nil
                        contentImageData = nil
                        cameraMode = .selfie
                    }) {
                        HStack(spacing: cardWidth * 0.006) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025))
                            Text("Reset")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, cardHeight * 0.006)
                        .background(
                            RoundedRectangle(cornerRadius: cardWidth * 0.015)
                                .fill(Color.white.opacity(0.04))
                        )
                        .foregroundColor(.white)
                    }
                }
            }
        }
    }
}


