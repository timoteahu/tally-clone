import SwiftUI

struct PaginatedCommentView: View {
    let postId: UUID
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let timeAgo: (Date) -> String
    let onReply: (Comment) -> Void
    
    @State private var comments: [Comment] = []
    @State private var isLoading = false
    @State private var hasMoreComments = true
    @State private var currentPage = 0
    @State private var isInitialLoad = true
    @State private var errorMessage: String?
    
    private let pageSize = 20
    private let initialLoadSize = 10
    
    @EnvironmentObject private var feedManager: FeedManager
    
    var body: some View {
        LazyVStack(spacing: 16) {
            if isInitialLoad && isLoading {
                // Show skeleton for initial load
                ForEach(0..<3, id: \.self) { index in
                    SkeletonCommentView(
                        variation: index,
                        cardHeight: cardHeight,
                        cardWidth: cardWidth,
                        shimmerOpacity: 0.6
                    )
                }
            } else if comments.isEmpty && !isLoading {
                EmptyCommentsView(cardHeight: cardHeight, cardWidth: cardWidth)
            } else {
                // Display loaded comments
                ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                    CommentRowView(
                        comment: comment,
                        postAuthorId: postId, // You might need to pass the actual post author ID
                        timeAgo: timeAgo,
                        onReply: onReply
                    )
                    .padding(.leading, calculateIndentation(for: comment))
                    .onAppear {
                        // Load more when reaching near the end
                        if index >= comments.count - 3 && hasMoreComments && !isLoading {
                            loadMoreComments()
                        }
                    }
                }
                
                // Loading indicator for pagination
                if isLoading && !isInitialLoad {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading more comments...")
                            .jtStyle(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 8)
                }
                
                // "Load More" button if there are more comments
                if hasMoreComments && !isLoading {
                    Button(action: loadMoreComments) {
                        Text("Load More Comments")
                            .jtStyle(.body)
                            .foregroundColor(.blue)
                            .padding(.vertical, 8)
                    }
                }
            }
            
            // Error state
            if let error = errorMessage {
                VStack {
                    Text("Error loading comments")
                        .jtStyle(.body)
                        .foregroundColor(.red)
                    Text(error)
                        .jtStyle(.caption)
                        .foregroundColor(.gray)
                    Button("Retry") {
                        retryLoad()
                    }
                    .foregroundColor(.blue)
                    .padding(.top, 4)
                }
                .padding()
            }
        }
        .onAppear {
            if comments.isEmpty {
                loadInitialComments()
            }
        }
    }
    
    private func calculateIndentation(for comment: Comment) -> CGFloat {
        return comment.parentComment != nil ? 20.0 : 0.0
    }
    
    private func loadInitialComments() {
        guard !isLoading else { return }
        
        isLoading = true
        isInitialLoad = true
        errorMessage = nil
        
        Task {
            do {
                let newComments = try await fetchComments(page: 0, size: initialLoadSize)
                
                await MainActor.run {
                    self.comments = newComments
                    self.currentPage = 0
                    self.hasMoreComments = newComments.count >= initialLoadSize
                    self.isLoading = false
                    self.isInitialLoad = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.isInitialLoad = false
                }
            }
        }
    }
    
    private func loadMoreComments() {
        guard !isLoading && hasMoreComments else { return }
        
        isLoading = true
        
        Task {
            do {
                let newComments = try await fetchComments(page: currentPage + 1, size: pageSize)
                
                await MainActor.run {
                    if newComments.isEmpty {
                        self.hasMoreComments = false
                    } else {
                        self.comments.append(contentsOf: newComments)
                        self.currentPage += 1
                        self.hasMoreComments = newComments.count >= pageSize
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func retryLoad() {
        comments = []
        currentPage = 0
        hasMoreComments = true
        loadInitialComments()
    }
    
    private func fetchComments(page: Int, size: Int) async throws -> [Comment] {
        // This would call your optimized API endpoint with pagination
        // For now, using the existing FeedManager method as fallback
        
        guard let url = URL(string: "\(AppConfig.baseURL)/comments/\(postId.uuidString)/paginated") else {
            throw CommentError.invalidURL
        }
        
        guard let token = await AuthenticationManager.shared.storedAuthToken else {
            throw CommentError.noAuthToken
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let requestBody = [
            "page": page,
            "size": size
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CommentError.badResponse
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = DateFormatterManager.shared.parseISO8601Date(dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateString)"
            )
        }
        
        return try decoder.decode([Comment].self, from: data)
    }
}

enum CommentError: Error, LocalizedError {
    case invalidURL
    case noAuthToken
    case badResponse
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for comments"
        case .noAuthToken:
            return "No authentication token"
        case .badResponse:
            return "Server error"
        case .decodingError:
            return "Failed to decode comments"
        }
    }
} 