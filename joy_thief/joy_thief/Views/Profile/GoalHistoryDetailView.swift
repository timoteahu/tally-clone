import SwiftUI

struct GoalHistoryDetailView: View {
    @EnvironmentObject var owedAmountManager: OwedAmountManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Goal History")
                    .jtStyle(.title)
                    .foregroundColor(.white)
                    .padding(.top, 24)
                    .padding(.horizontal, 20)
                
                VStack(spacing: 0) {
                    if owedAmountManager.isLoadingOwed {
                        HStack {
                            ProgressView("Loading owed amounts...")
                                .padding()
                            Spacer()
                        }
                    } else if let owedError = owedAmountManager.owedError {
                        HStack {
                            Text("Error: \(owedError)")
                                .foregroundColor(.red)
                                .padding()
                            Spacer()
                        }
                    } else if owedAmountManager.owedRecipients.isEmpty {
                        HStack {
                            Text("You don't owe anyone this week!")
                                .foregroundColor(.white.opacity(0.7))
                                .padding()
                            Spacer()
                        }
                    } else {
                        ForEach(owedAmountManager.owedRecipients) { owed in
                            HStack {
                                Image(systemName: "person.crop.circle")
                                    .font(.custom("EBGaramond-Regular", size: 20))
                                    .foregroundColor(.white.opacity(0.7))
                                Text(owed.recipient_name.isEmpty ? owed.recipient_id : owed.recipient_name)
                                    .foregroundColor(.white)
                                Spacer()
                                Text(String(format: "$%.2f", owed.amount_owed))
                                    .foregroundColor(.yellow)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Color.clear)
                        }
                    }
                }
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 100)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

#Preview {
    GoalHistoryDetailView()
        .environmentObject(OwedAmountManager())
} 