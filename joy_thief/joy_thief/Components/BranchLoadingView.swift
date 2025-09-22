import SwiftUI

struct BranchLoadingView: View {
    let state: BranchInitializationState
    
    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
            case .initializing:
                initializingView
            case .ready:
                EmptyView()
            case .failed(let error):
                errorView(error)
            }
        }
    }
    
    private var initializingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Initializing...")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.custom("EBGaramond-Regular", size: 24))
                .foregroundColor(.orange)
            
            Text("Initialization Failed")
                .jtStyle(.body)
                .foregroundColor(.white)
            
            Text(error.localizedDescription)
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

struct LinkGenerationLoadingView: View {
    let state: LinkGenerationState
    
    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
            case .generating:
                generatingView
            case .success:
                EmptyView() // Success is handled by parent view
            case .failed(let error):
                errorView(error)
            }
        }
    }
    
    private var generatingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
            
            Text("Generating invite link...")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.custom("EBGaramond-Regular", size: 20))
                .foregroundColor(.red)
            
            Text("Failed to generate link")
                .jtStyle(.caption)
                .foregroundColor(.white)
            
            Text(error.localizedDescription)
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.2))
        .cornerRadius(8)
    }
}

// MARK: - Preview Support

#Preview("Branch Loading - Initializing") {
    ZStack {
        Color.black.ignoresSafeArea()
        BranchLoadingView(state: .initializing)
    }
}

#Preview("Branch Loading - Error") {
    ZStack {
        Color.black.ignoresSafeArea()
        BranchLoadingView(state: .failed(BranchError.initializationFailed))
    }
}

#Preview("Link Generation - Generating") {
    ZStack {
        Color.black.ignoresSafeArea()
        LinkGenerationLoadingView(state: .generating)
    }
}

#Preview("Link Generation - Error") {
    ZStack {
        Color.black.ignoresSafeArea()
        LinkGenerationLoadingView(state: .failed(BranchError.linkGenerationFailed))
    }
} 