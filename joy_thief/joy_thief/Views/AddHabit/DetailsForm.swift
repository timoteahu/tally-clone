////
//  Step2_DetailsForm.swift
//  joy_thief
//
//  Created by RefactorBot on 2025-06-18.
//
//  Step 2 of Add Habit wizard – details form.
//

import SwiftUI

extension AddHabitRoot {
    struct HabitDetailsFormStep: View {
        @ObservedObject var vm: AddHabitViewModel
        @EnvironmentObject var customHabitManager: CustomHabitManager
        @EnvironmentObject var friendsManager: FriendsManager
        @EnvironmentObject var paymentManager: PaymentManager
        @FocusState private var focusedField: Field?

        let isOnboarding: Bool
        var onNext: () -> Void
        var onBack: () -> Void

        private enum Field {
            case name
            case customNotification
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    // Color.black.ignoresSafeArea() // Remove this line to show gradient
                    VStack {
                        wizardHeader
                        // Title below the header
                        Text("habit details")
                            .font(.custom("EBGaramond-Regular", size: 32))
                            .foregroundColor(.white)
                            .padding(.top, 4)
                        VStack(spacing: 18) {
                            nameSection
                            // customNotificationSection
                            if vm.selectedHabitType == HabitType.alarm.rawValue {
                                alarmSection
                            }
                            friendSelectionSection
                            HStack {
                                Spacer()
                                Button(action: onNext) {
                                    Text("next")
                                        .font(.custom("EBGaramond-Bold", size: 22))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: 180)
                                        .padding(.vertical, 16)
                                        .background(Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                                        )
                                        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                                }
                                .disabled(vm.name.isEmpty)
                                .opacity(vm.name.isEmpty ? 0.5 : 1.0)
                                .padding(.horizontal, 0)
                                Spacer()
                            }
                            .padding(.top, 32)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .ignoresSafeArea(.keyboard)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled(true)
            .alert("payment setup needed", isPresented: $vm.showingStripeWarning) {
                Button("ok, got it", role: .cancel) {
                    // Keep the friend selected
                }
            } message: {
                Text("\(vm.stripeWarningFriendName) needs to set up a Stripe Connect account to receive money. They'll be notified when you create this habit.")
            }
            .onAppear {
                // Load friends with Stripe Connect when the details form appears
                Task {
                    print("🔄 [AddHabitDetailsForm] Loading friends with Stripe Connect...")
                    print("📊 [AddHabitDetailsForm] Current friends count: \(friendsManager.preloadedFriends.count)")
                    print("📊 [AddHabitDetailsForm] Current friends with Stripe count: \(friendsManager.preloadedFriendsWithStripeConnect.count)")
                    
                    await friendsManager.refreshFriendsWithStripeConnect()
                    
                    print("✅ [AddHabitDetailsForm] After refresh:")
                    print("   - Total friends: \(friendsManager.preloadedFriends.count)")
                    print("   - Friends with Stripe: \(friendsManager.preloadedFriendsWithStripeConnect.count)")
                    
                    // Log the friends for debugging
                    for friend in friendsManager.preloadedFriendsWithStripeConnect {
                        print("   - Friend: \(friend.name) (ID: \(friend.friendId))")
                    }
                }
            }
        }

        // MARK: - Header
        private var wizardHeader: some View {
            HStack {
                // Back button (goes to previous step)
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .offset(x: 2, y: 2)

                Spacer()

                // Down arrow (dismisses overlay)
                Button(action: {
                    NotificationCenter.default.post(name: NSNotification.Name("DismissAddHabitOverlay"), object: nil)
                }) {
                    Image(systemName: "chevron.down")
                        .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .offset(x: -2, y: 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }

        // MARK: - Sub-sections
        private var nameSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("habit name")
                    .font(.custom("EBGaramond-Italic", size: 20))
                    .foregroundColor(.white.opacity(0.7))
                    .overlay(
                        Text("*")
                            .font(.custom("EBGaramond-Italic", size: 20))
                            .foregroundColor(.red)
                            .offset(x: 10, y: 0), alignment: .trailing
                    )
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 54)
                    TextField("enter a name", text: $vm.name)
                        .font(.custom("EBGaramond-Regular", size: 18))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                        .focused($focusedField, equals: .name)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture {
                    focusedField = .name
                }
            }
        }

        private var customNotificationSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("notification")
                    .font(.custom("EBGaramond-Italic", size: 20))
                    .foregroundColor(.white.opacity(0.7))
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 54)
                    TextField("enter custom notification", text: $vm.customNotification)
                        .font(.custom("EBGaramond-Italic", size: 18))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                        .focused($focusedField, equals: .customNotification)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture {
                    focusedField = .customNotification
                }
            }
        }

        private var alarmSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("alarm time")
                    .font(.custom("EBGaramond-Italic", size: 20))
                    .foregroundColor(.white.opacity(0.7))
                DatePicker("", selection: $vm.alarmTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .font(.custom("EBGaramond-Regular", size: 18))
                    .modernInputStyle()
                    .frame(maxWidth: .infinity)
            }
        }

        // MARK: - Friend Picker (migrated)
        private var friendSelectionSection: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("accountability partner")
                    .font(.custom("EBGaramond-Italic", size: 20))
                    .foregroundColor(.white.opacity(0.7))
                
                friendDropdownButton
                
                if vm.showingFriendsDropdown {
                    if friendsManager.preloadedFriendsWithStripeConnect.isEmpty {
                        noFriendsMessage
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                    } else {
                        friendsDropdownList
                    }
                }
            }
        }
        
        private var friendDropdownButton: some View {
            Button(action: { 
                focusedField = nil // Close the keyboard
                withAnimation(.easeInOut(duration: 0.3)) {
                    vm.showingFriendsDropdown.toggle()
                }
            }) {
                HStack {
                    Text(vm.selectedFriend?.name.split(separator: " ").first.map(String.init) ?? "recipient")
                        .font(.custom(vm.selectedFriend == nil ? "EBGaramond-Italic" : "EBGaramond-Regular", size: 18))
                        .foregroundColor(vm.selectedFriend == nil ? .white.opacity(0.7) : .white)
                    Spacer()
                    Image(systemName: vm.showingFriendsDropdown ? "chevron.up" : "chevron.down")
                        .font(.custom("EBGaramond-Regular", size: 24)).fontWeight(.regular)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .frame(height: 70)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        
        private var noFriendsMessage: some View {
            VStack(spacing: 16) {
                Text("no friends found")
                    .font(.custom("EBGaramond-Regular", size: 18))
                    .foregroundColor(.white.opacity(0.7))
                
                Button(action: {
                    // Dismiss the AddHabit overlay first
                    NotificationCenter.default.post(name: NSNotification.Name("DismissAddHabitOverlay"), object: nil)
                    
                    // Navigate to the Discover tab (friends page)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToDiscover"), object: nil)
                    }
                }) {
                    Text("find friends")
                        .font(.custom("EBGaramond-Bold", size: 18))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
            )
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.2), value: vm.showingFriendsDropdown)
        }
        
        private var friendsDropdownList: some View {
            VStack(alignment: .leading, spacing: 0) {
                if vm.selectedFriend != nil {
                    removePartnerButton
                    Divider().background(Color.white.opacity(0.12))
                }
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        friendsList
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 300) // Limit height to make it scrollable
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
            )
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.2), value: vm.showingFriendsDropdown)
        }
        
        private var removePartnerButton: some View {
            Button(action: {
                vm.selectedFriend = nil
                vm.showingFriendsDropdown = false
            }) {
                Text("remove partner")
                    .font(.custom("EBGaramond-Regular", size: 18))
                    .foregroundColor(.red)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        
        private var friendsList: some View {
            VStack(spacing: 2) {
                ForEach(friendsManager.preloadedFriendsWithStripeConnect, id: \.friendId) { friend in
                    Button(action: {
                        vm.selectedFriend = friend
                        vm.showingFriendsDropdown = false
                        
                        // Show warning if friend doesn't have Stripe
                        if !friend.hasStripe {
                            vm.showingStripeWarning = true
                            vm.stripeWarningFriendName = friend.name.split(separator: " ").first.map(String.init) ?? friend.name
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.name.split(separator: " ").first.map(String.init) ?? friend.name)
                                    .font(.custom("EBGaramond-Regular", size: 18))
                                    .foregroundColor(.white)
                                
                                if !friend.hasStripe {
                                    Text("needs to set up payments")
                                        .font(.custom("EBGaramond-Italic", size: 12))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                            Spacer()
                            if vm.selectedFriend?.friendId == friend.friendId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(vm.selectedFriend?.friendId == friend.friendId ? Color.white.opacity(0.10) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
        }

        private func initials(for name: String) -> String {
            let comps = name.split(separator: " ")
            if comps.count >= 2 {
                return String(comps[0].prefix(1)) + String(comps[1].prefix(1))
            } else if let first = comps.first {
                return String(first.prefix(2))
            } else {
                return "?"
            }
        }

        // MARK: - Friend Picker (migrated)
        private var onboardingFriendsView: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose someone who will receive money when you miss your habit:")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(sampleAccountabilityPartners, id: \.id) { partner in
                            samplePartnerButton(partner)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }

        private func samplePartnerButton(_ partner: SampleAccountabilityPartner) -> some View {
            Button {
                let friendData: [String: Any] = [
                    "id": partner.id,
                    "friend_id": partner.id,
                    "name": partner.name,
                    "phone_number": partner.phoneNumber
                ]
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: friendData)
                    let tempFriend = try JSONDecoder().decode(Friend.self, from: jsonData)
                    vm.selectedFriend = tempFriend
                } catch { print(error) }
            } label: {
                VStack(spacing: 10) {
                    Circle()
                        .fill(vm.selectedFriend?.friendId == partner.id ? Color.white : Color.white.opacity(0.1))
                        .frame(width: 55, height: 55)
                        .overlay(
                            Text(partner.initials)
                                .font(.custom("EBGaramond-Regular", size: 18)).fontWeight(.bold)
                                .foregroundColor(vm.selectedFriend?.friendId == partner.id ? .black : .white)
                        )
                    Text(partner.name.split(separator: " ").first ?? "")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(12)
        }

        private var regularFriendsView: some View {
            Group {
                if friendsManager.preloadedFriendsWithStripeConnect.isEmpty {
                    Text("No friends with Stripe Connect found")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(12)
                } else {
                    friendsDropdownView
                }
            }
        }

        private var friendsDropdownView: some View {
            VStack(spacing: 0) {
                dropdownButton
                if vm.showingFriendsDropdown { dropdownContent }
            }
        }

        private var dropdownButton: some View {
            Button {
                withAnimation { vm.showingFriendsDropdown.toggle() }
                if !vm.showingFriendsDropdown { vm.partnerSearchText = "" }
            } label: {
                HStack {
                    if let friend = vm.selectedFriend {
                        Text(friend.name)
                            .foregroundColor(.white)
                    } else {
                        Text("Select Partner")
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: vm.showingFriendsDropdown ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white.opacity(0.6))
                }
                .modernInputStyle()
            }
        }

        private var dropdownContent: some View {
            VStack(spacing: 12) {
                TextField("Search", text: $vm.partnerSearchText)
                    .foregroundColor(.white)
                    .modernInputStyle(cornerRadius: 8)
                ForEach(filteredFriends) { friend in
                    Button {
                        vm.selectedFriend = friend
                        withAnimation { vm.showingFriendsDropdown = false }
                        vm.partnerSearchText = ""
                    } label: {
                        HStack {
                            Text(friend.name)
                                .foregroundColor(.white)
                            Spacer()
                            if vm.selectedFriend?.friendId == friend.friendId {
                                Image(systemName: "checkmark").foregroundColor(.green)
                            }
                        }
                        .padding(6)
                    }
                }
            }
            .modernInputStyle()
        }

        private var filteredFriends: [Friend] {
            let all = friendsManager.preloadedFriendsWithStripeConnect
            if vm.partnerSearchText.isEmpty { return all }
            return all.filter { $0.name.lowercased().contains(vm.partnerSearchText.lowercased()) }
        }

        // Sample data used during onboarding
        private struct SampleAccountabilityPartner {
            let id: String
            let name: String
            let phoneNumber: String
            let initials: String
        }

        private var sampleAccountabilityPartners: [SampleAccountabilityPartner] {
            [
                .init(id: "sample-1", name: "Alex Johnson", phoneNumber: "+1234567890", initials: "AJ"),
                .init(id: "sample-2", name: "Sarah Chen", phoneNumber: "+1234567891", initials: "SC"),
                .init(id: "sample-3", name: "Mike Brown", phoneNumber: "+1234567892", initials: "MB")
            ]
        }
    }
}

// MARK: - Modern UI Helpers
fileprivate struct ModernInputStyle: ViewModifier {
    var cornerRadius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

fileprivate extension View {
    func modernInputStyle(cornerRadius: CGFloat = 12) -> some View {
        modifier(ModernInputStyle(cornerRadius: cornerRadius))
    }
}

fileprivate struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(background)
            .cornerRadius(14)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
    @ViewBuilder
    private var background: some View {
        if isEnabled {
            LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color.white.opacity(0.15)
        }
    }
} 