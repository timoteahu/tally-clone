import SwiftUI

struct CustomTextField: View {
    var placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                // Floating placeholder
                Text(placeholder)
                    .foregroundColor(.white.opacity(0.9))
                    .font(.custom("EBGaramond-Regular", size: (isFocused || !text.isEmpty) ? 14 : 22))
                    .offset(y: (isFocused || !text.isEmpty) ? -26 : 0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 0.2), value: isFocused || !text.isEmpty)

                // Actual text field (with empty placeholder so system one is hidden)
                TextField("", text: $text)
                    .keyboardType(keyboardType)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .foregroundColor(.white)
                    .font(.custom("EBGaramond-Regular", size: 22))
                    .focused($isFocused)
                    // note: numeric keyboard; dismissal handled by tap outside
            }
            // Single underline with extra top padding for visual gap
            Rectangle()
                .frame(width: 190, height: 1)
                .foregroundColor(.white)
        }
        // Fixed width to keep underline aligned and prevent centering
        .frame(width: 260, alignment: .leading)
        .padding(.leading, 30)
        // The width is already explicitly constrained above; no further expansion.
        // Expand tap area so the whole component is tappable
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
} 