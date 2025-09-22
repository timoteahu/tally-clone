//
//  TermsOfServiceView.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/7/25.
//


import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hasAcceptedTerms: Bool
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Navigation Bar
                HStack {
                    Text("Terms of Service")
                        .jtStyle(.title)
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                // Terms Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Introduction
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Welcome to Tally")
                                .jtStyle(.title)
                                .foregroundColor(.white)
                            
                            Text("Please read these terms carefully before using our app.")
                                .jtStyle(.body)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        // Terms Sections
                        Group {
                            termsSection(
                                title: "1. Acceptance of Terms",
                                content: "By using Tally (\"the App\"), you agree to comply with and be legally bound by these Terms of Service (\"Terms\"). If you do not agree with these Terms, please do not use the App."
                            )
                            
                            termsSection(
                                title: "2. Description of Service",
                                content: "Tally helps you create and track habits. You agree to verify completion of your selected habits on scheduled days. Failure to verify habit completion results in an automatic monetary charge, debited from your linked payment method through our secure payment processing partner, Stripe."
                            )
                            
                            termsSection(
                                title: "3. Eligibility and Age Restrictions",
                                content: "You must be at least 18 years of age to use Tally. By using the App, you represent that you are legally eligible to enter into binding contracts."
                            )
                            
                            termsSection(
                                title: "4. Account and Payment Authorization",
                                content: "You authorize Tally to charge your provided payment method (via Stripe) automatically whenever you fail to verify a habit as scheduled. You are responsible for maintaining accurate and current payment information. If your payment method fails, we may limit or terminate your access to the App."
                            )
                            
                            termsSection(
                                title: "5. Recipient Accountability Feature",
                                content: "If you select another user or external recipient to receive funds from your missed habit verification, you expressly consent to transferring such funds to the designated recipient. Tally is not responsible for the use of these funds by recipients."
                            )
                            
                            termsSection(
                                title: "6. Refund Policy",
                                content: "Charges are generally final. However, we will provide refunds upon receiving sufficient proof of habit completion or valid reasons for exemption. All refund requests will be reviewed at our discretion."
                            )
                            
                            termsSection(
                                title: "7. User Conduct",
                                content: "You agree not to misuse Tally or engage in fraudulent or unlawful activities. Violation of this term may result in immediate termination of your account and potential legal action."
                            )
                            
                            termsSection(
                                title: "8. Privacy and Security",
                                content: "Your privacy and the security of your information are important to us. We implement industry-standard measures to ensure your personal and payment data are securely stored and processed. Please review our Privacy Policy separately provided, which details how we collect, store, and use your personal data."
                            )
                            
                            termsSection(
                                title: "9. Limitation of Liability",
                                content: "The App is provided on an \"as is\" basis. We disclaim all warranties, explicit or implied. In no event shall we be liable for any direct, indirect, incidental, special, or consequential damages resulting from your use or inability to use the App."
                            )
                            
                            termsSection(
                                title: "10. Termination of Services",
                                content: "We reserve the right to suspend or terminate your account at our sole discretion if you breach these Terms or if we determine that your use of the App adversely affects the App's operation or other users."
                            )
                            
                            termsSection(
                                title: "11. Changes to Terms",
                                content: "We reserve the right to update or modify these Terms at any time. Continued use of the App following changes constitutes your acceptance of the revised Terms."
                            )
                            
                            termsSection(
                                title: "12. Dispute Resolution",
                                content: "Any disputes arising from your use of the App will be resolved through arbitration under the rules of the American Arbitration Association (AAA) or any equivalent organization mutually agreed upon by both parties."
                            )
                            
                            termsSection(
                                title: "13. Governing Law",
                                content: "These Terms are governed by and construed according to the laws of the United States."
                            )
                            
                            termsSection(
                                title: "14. Contact Information",
                                content: "If you have any questions regarding these Terms, please contact us at support@jointly.app"
                            )
                            
                            // Effective Date
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Effective Date")
                                    .jtStyle(.body)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Text("June 7, 2025")
                                    .jtStyle(.body)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(20)
                }
                
                // Accept Button
                VStack(spacing: 16) {
                    Button(action: {
                        withAnimation {
                            hasAcceptedTerms = true
                            dismiss()
                        }
                    }) {
                        Text("I Accept the Terms of Service")
                            .jtStyle(.body)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white,
                                                Color.white.opacity(0.95)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .shadow(
                                        color: Color.white.opacity(0.3),
                                        radius: 8,
                                        x: 0,
                                        y: 4
                                    )
                            )
                    }
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Decline")
                            .jtStyle(.body)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(20)
                .background(
                    Rectangle()
                        .fill(Color.black)
                        .shadow(color: .black.opacity(0.3), radius: 20, y: -10)
                )
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func termsSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .jtStyle(.body)
                .foregroundColor(.white)
            
            Text(content)
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    TermsOfServiceView(hasAcceptedTerms: .constant(false))
} 