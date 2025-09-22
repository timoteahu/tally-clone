import SwiftUI

struct SegmentedNumberPicker: View {
    @Binding var value: Double
    let presets: [Double]
    let customRange: ClosedRange<Double>
    let step: Double
    let unit: String
    let formatter: (Double) -> String
    
    @State private var showCustomInput = false
    @State private var customTextValue: String = ""
    @FocusState private var isCustomInputFocused: Bool
    
    init(
        value: Binding<Double>,
        presets: [Double],
        customRange: ClosedRange<Double>,
        step: Double = 1.0,
        unit: String = "",
        formatter: @escaping (Double) -> String = { String(format: "%.0f", $0) }
    ) {
        self._value = value
        self.presets = presets
        self.customRange = customRange
        self.step = step
        self.unit = unit
        self.formatter = formatter
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Preset buttons row
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { preset in
                    PresetButton(
                        value: preset,
                        isSelected: !showCustomInput && value == preset,
                        formatter: formatter,
                        unit: unit,
                        action: { selectPreset(preset) },
                        isCompact: true
                    )
                }
            }
            // Custom button row (centered)
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCustomInput = true
                        customTextValue = formatter(value)
                        isCustomInputFocused = true
                    }
                }) {
                    VStack(spacing: 4) {
                        Text("Custom")
                            .font(.custom("EBGaramond-Regular", size: 16))
                        // Removed value/unit display when pressed
                    }
                    .foregroundColor(showCustomInput ? .black : .white)
                    .frame(maxWidth: 60)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(showCustomInput ? Color.white : Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                showCustomInput ? Color.clear : Color.white.opacity(0.2),
                                lineWidth: 1
                            )
                    )
                }
                .scaleEffect(showCustomInput ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: showCustomInput)
                Spacer()
            }
            
            // Custom input field
            if showCustomInput {
                HStack(spacing: 12) {
                    // TextField with unit
                    HStack(spacing: 8) {
                        TextField("Enter value", text: $customTextValue)
                            .font(.custom("EBGaramond-Regular", size: 18))
                            .foregroundColor(.white)
                            .keyboardType(.numberPad)
                            .focused($isCustomInputFocused)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: customTextValue) { _, newValue in
                                validateCustomValue(newValue)
                            }
                            .frame(minWidth: 40, maxWidth: 70) // limit width
                        if !unit.isEmpty {
                            Text(unit)
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                    
                    // Stepper (now horizontal)
                    HStack(spacing: 0) {
                        Button(action: decrementCustomValue) {
                            Image(systemName: "minus")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 32)
                                .background(Color.white.opacity(0.1))
                                .contentShape(Rectangle())
                        }
                        .disabled(value <= customRange.lowerBound)
                        Divider()
                            .frame(height: 28)
                            .background(Color.white.opacity(0.2))
                        Button(action: incrementCustomValue) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 32)
                                .background(Color.white.opacity(0.1))
                                .contentShape(Rectangle())
                        }
                        .disabled(value >= customRange.upperBound)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Range hint
            Text("Range: \(formatter(customRange.lowerBound)) - \(formatter(customRange.upperBound)) \(unit)")
                .font(.custom("EBGaramond-Regular", size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    private func selectPreset(_ preset: Double) {
        withAnimation(.easeInOut(duration: 0.2)) {
            value = preset
            showCustomInput = false
            isCustomInputFocused = false
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func validateCustomValue(_ text: String) {
        let filtered = text.filter { "0123456789.".contains($0) }
        
        if let doubleValue = Double(filtered) {
            if customRange.contains(doubleValue) {
                value = doubleValue
            }
        }
    }
    
    private func incrementCustomValue() {
        let newValue = min(value + step, customRange.upperBound)
        withAnimation(.easeInOut(duration: 0.15)) {
            value = newValue
            customTextValue = formatter(newValue)
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func decrementCustomValue() {
        let newValue = max(value - step, customRange.lowerBound)
        withAnimation(.easeInOut(duration: 0.15)) {
            value = newValue
            customTextValue = formatter(newValue)
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// Update PresetButton to accept isCompact and adjust style
struct PresetButton: View {
    let value: Double
    let isSelected: Bool
    let formatter: (Double) -> String
    let unit: String
    let action: () -> Void
    var isCompact: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(formatter(value))
                    .font(.custom("EBGaramond-Bold", size: isCompact ? 16 : 20))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.custom("EBGaramond-Regular", size: isCompact ? 12 : 14))
                        .opacity(0.7)
                }
            }
            .foregroundColor(isSelected ? .black : .white)
            .frame(maxWidth: isCompact ? 48 : .infinity)
            .padding(.vertical, isCompact ? 10 : 16)
            .padding(.horizontal, isCompact ? 4 : 0)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.clear : Color.white.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// Preview
struct SegmentedNumberPicker_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            SegmentedNumberPicker(
                value: .constant(10000),
                presets: [5000, 8000, 10000, 15000],
                customRange: 1000...30000,
                step: 500,
                unit: "steps"
            )
            .padding()
            .background(Color.black)
        }
        .preferredColorScheme(.dark)
    }
}
