import SwiftUI

struct CurrencyTextField: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let quickSelectValues: [Float]
    
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool
    @State private var showValidationError = false
    
    // Optional callback for parent views to track focus state changes
    private let onFocusChange: ((Bool) -> Void)?
    
    init(
        value: Binding<Float>,
        range: ClosedRange<Float> = 0.5...500,
        step: Float = 0.5,
        quickSelectValues: [Float] = [5, 10, 20, 25],
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.quickSelectValues = quickSelectValues
        self.onFocusChange = onFocusChange
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Clean inline input without box styling
            HStack(spacing: 16) {
                // Decrement button
                Button(action: decrementValue) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(value > range.lowerBound ? .white : .white.opacity(0.3))
                }
                .disabled(value <= range.lowerBound)
                
                Spacer()
                
                // Value display with manual input capability
                VStack(spacing: 4) {
                    TextField("0.00", text: $textValue)
                        .font(.custom("EBGaramond-Regular", size: 32))
                        .foregroundColor(.white)
                        .keyboardType(.decimalPad)
                        .focused($isFocused)
                        .multilineTextAlignment(.center)
                        .onChange(of: textValue) { _, newValue in
                            validateAndUpdateValue(newValue)
                        }
                        .onAppear {
                            textValue = String(format: "%.2f", value)
                        }
                        .onChange(of: value) { _, newValue in
                            if !isFocused {
                                textValue = String(format: "%.2f", newValue)
                            }
                        }
                        .onChange(of: isFocused) { _, newValue in
                            // Sync with external focus binding if provided
                            onFocusChange?(newValue)
                        }
                    
                    Text("credits")
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Increment button
                Button(action: incrementValue) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(value < range.upperBound ? .white : .white.opacity(0.3))
                }
                .disabled(value >= range.upperBound)
            }
            .padding(.horizontal, 16)
            
            // Quick select buttons
            HStack(spacing: 12) {
                Spacer()
                ForEach(quickSelectValues, id: \.self) { quickValue in
                    Button(action: {
                        selectQuickValue(quickValue)
                    }) {
                        Text("\(Int(quickValue))")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(value == quickValue ? .black : .white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(value == quickValue ? Color.white : Color.white.opacity(0.1))
                            )
                    }
                }
                Spacer()
            }
            
            // Validation message
            if showValidationError {
                Text("Amount must be between \(String(format: "%.0f", range.lowerBound)) and \(String(format: "%.0f", range.upperBound))")
                    .font(.custom("EBGaramond-Regular", size: 12))
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
        .onTapGesture {
            // Ensure tapping anywhere in the component focuses the text field
            isFocused = true
        }
    }
    
    private func validateAndUpdateValue(_ text: String) {
        // Remove non-numeric characters except decimal point
        let filtered = text.filter { "0123456789.".contains($0) }
        
        // Ensure only one decimal point
        let components = filtered.split(separator: ".")
        if components.count > 2 {
            return
        }
        
        // Limit decimal places to 2
        if components.count == 2 && components[1].count > 2 {
            textValue = "\(components[0]).\(components[1].prefix(2))"
            return
        }
        
        // Parse the value
        if let floatValue = Float(filtered) {
            if range.contains(floatValue) {
                value = floatValue
                showValidationError = false
            } else {
                showValidationError = true
            }
        }
    }
    
    private func selectQuickValue(_ quickValue: Float) {
        withAnimation(.easeInOut(duration: 0.2)) {
            value = quickValue
            textValue = String(format: "%.2f", quickValue)
            showValidationError = false
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func incrementValue() {
        let newValue = min(value + step, range.upperBound)
        withAnimation(.easeInOut(duration: 0.15)) {
            value = newValue
            textValue = String(format: "%.2f", newValue)
            showValidationError = false
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func decrementValue() {
        let newValue = max(value - step, range.lowerBound)
        withAnimation(.easeInOut(duration: 0.15)) {
            value = newValue
            textValue = String(format: "%.2f", newValue)
            showValidationError = false
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// Preview
struct CurrencyTextField_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            CurrencyTextField(value: .constant(10.0))
                .padding()
                .background(Color.black)
        }
        .preferredColorScheme(.dark)
    }
}