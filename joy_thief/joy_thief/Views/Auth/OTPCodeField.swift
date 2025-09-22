import SwiftUI

/// A six-digit one-time-password field rendered as discrete boxes.
/// Bind the entered code via `code`. The component internally uses a
/// hidden text field so the system keyboard & auto-fill work normally.
struct OTPCodeField: View {
    @Binding var code: String
    var length: Int = 6
    var placeholder: String = "enter your code"

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                Text(placeholder)
                    .foregroundColor(.white.opacity(0.9))
                    .font(.custom("EBGaramond-Regular", size: (isFocused || !code.isEmpty) ? 14 : 22))
                    .offset(y: (isFocused || !code.isEmpty) ? -26 : 0)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .animation(.easeInOut(duration: 0.2), value: isFocused || !code.isEmpty)

                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isFocused)
                    .foregroundColor(.white)
                    .font(.custom("EBGaramond-Regular", size: 22))
                    .onChange(of: code) { oldValue, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { code = filtered }
                        if code.count > length { code = String(code.prefix(length)) }
                    }
                    // numeric pad – dismissal handled by tap outside
            }
            Rectangle()
                .frame(width: 190, height: 1)
                .foregroundColor(.white)
        }
        // Fixed width to align with text field component for consistent layout
        .frame(width: 260, alignment: .leading)
        .padding(.leading, 30)
        // Field remains left-aligned; no additional frame to prevent unexpected expansion.
    }
}

private extension String {
    /// Returns the character at `index` as a String, or empty string if out of bounds.
    func digit(at index: Int) -> String {
        guard index < count else { return "" }
        let idx = self.index(startIndex, offsetBy: index)
        return String(self[idx])
    }
} 