import SwiftUI

struct StepperField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: String
    let quickSelectValues: [Int]?
    
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool
    
    init(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        label: String,
        quickSelectValues: [Int]? = nil
    ) {
        self._value = value
        self.range = range
        self.label = label
        self.quickSelectValues = quickSelectValues
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Main input row
            HStack(spacing: 16) {
                // Decrement button
                Button(action: decrementValue) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(value > range.lowerBound ? .white : .white.opacity(0.3))
                }
                .disabled(value <= range.lowerBound)
                .scaleEffect(value <= range.lowerBound ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: value <= range.lowerBound)
                
                // Value display with TextField
                VStack(spacing: 4) {
                    TextField("", text: $textValue)
                        .font(.custom("EBGaramond-Regular", size: 32))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                        .frame(minWidth: 80)
                        .onChange(of: textValue) { _, newValue in
                            validateValue(newValue)
                        }
                        .onAppear {
                            textValue = String(value)
                        }
                        .onChange(of: value) { _, newValue in
                            if !isFocused {
                                textValue = String(newValue)
                            }
                        }
                    
                    Text(label)
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // Increment button
                Button(action: incrementValue) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(value < range.upperBound ? .white : .white.opacity(0.3))
                }
                .disabled(value >= range.upperBound)
                .scaleEffect(value >= range.upperBound ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: value >= range.upperBound)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            
            // Quick select buttons if provided
            if let quickValues = quickSelectValues {
                HStack(spacing: 8) {
                    ForEach(quickValues, id: \.self) { quickValue in
                        Button(action: {
                            selectValue(quickValue)
                        }) {
                            Text("\(quickValue)")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(value == quickValue ? .black : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(value == quickValue ? Color.white : Color.white.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            value == quickValue ? Color.clear : Color.white.opacity(0.2),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .scaleEffect(value == quickValue ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: value == quickValue)
                    }
                }
            }
        }
    }
    
    private func validateValue(_ text: String) {
        let filtered = text.filter { "0123456789".contains($0) }
        
        if let intValue = Int(filtered) {
            if range.contains(intValue) {
                value = intValue
            } else if intValue < range.lowerBound {
                value = range.lowerBound
                textValue = String(range.lowerBound)
            } else {
                value = range.upperBound
                textValue = String(range.upperBound)
            }
        } else if filtered.isEmpty {
            value = range.lowerBound
            textValue = String(range.lowerBound)
        }
    }
    
    private func incrementValue() {
        guard value < range.upperBound else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            value = min(value + 1, range.upperBound)
            textValue = String(value)
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func decrementValue() {
        guard value > range.lowerBound else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            value = max(value - 1, range.lowerBound)
            textValue = String(value)
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func selectValue(_ quickValue: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            value = quickValue
            textValue = String(quickValue)
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// Compact version for inline use
struct CompactStepperField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String?
    
    init(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String? = nil
    ) {
        self._value = value
        self.range = range
        self.suffix = suffix
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                if value > range.lowerBound {
                    value -= 1
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
            }) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(value > range.lowerBound ? .white : .white.opacity(0.3))
            }
            .disabled(value <= range.lowerBound)
            
            HStack(spacing: 4) {
                Text("\(value)")
                    .font(.custom("EBGaramond-Regular", size: 20))
                    .foregroundColor(.white)
                if let suffix = suffix {
                    Text(suffix)
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(minWidth: suffix != nil ? 120 : 40)
            
            Button(action: {
                if value < range.upperBound {
                    value += 1
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(value < range.upperBound ? .white : .white.opacity(0.3))
            }
            .disabled(value >= range.upperBound)
        }
    }
}

// Preview
struct StepperField_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            StepperField(
                value: .constant(5),
                range: 1...7,
                label: "times per week"
            )
            
            StepperField(
                value: .constant(10),
                range: 1...50,
                label: "commits per day",
                quickSelectValues: [1, 5, 10, 20]
            )
            
            CompactStepperField(
                value: .constant(3),
                range: 1...7
            )
        }
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}