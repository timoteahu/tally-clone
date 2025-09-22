import SwiftUI

struct HoursStepperField: View {
    @Binding var hours: Double
    let isWeekly: Bool
    
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool
    
    private var range: ClosedRange<Double> {
        isWeekly ? 1...168 : 0.5...24
    }
    
    private var step: Double {
        0.5
    }
    
    private var quickSelectValues: [Double] {
        isWeekly ? [7, 14, 21, 28] : [1, 2, 3, 4]
    }
    
    private var label: String {
        formatHours(hours)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Main input row
            HStack(spacing: 16) {
                // Decrement button
                Button(action: decrementValue) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(hours > range.lowerBound ? .white : .white.opacity(0.3))
                }
                .disabled(hours <= range.lowerBound)
                .scaleEffect(hours <= range.lowerBound ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: hours <= range.lowerBound)
                
                // Value display with TextField
                VStack(spacing: 4) {
                    TextField("", text: $textValue)
                        .font(.custom("EBGaramond-Regular", size: 32))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .keyboardType(.decimalPad)
                        .focused($isFocused)
                        .frame(minWidth: 80)
                        .onChange(of: textValue) { _, newValue in
                            validateValue(newValue)
                        }
                        .onAppear {
                            textValue = formatValueForInput(hours)
                        }
                        .onChange(of: hours) { _, newValue in
                            if !isFocused {
                                textValue = formatValueForInput(newValue)
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
                        .foregroundColor(hours < range.upperBound ? .white : .white.opacity(0.3))
                }
                .disabled(hours >= range.upperBound)
                .scaleEffect(hours >= range.upperBound ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: hours >= range.upperBound)
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
            
            // Quick select buttons
            HStack(spacing: 8) {
                ForEach(quickSelectValues, id: \.self) { quickValue in
                    Button(action: {
                        selectValue(quickValue)
                    }) {
                        Text(formatQuickValue(quickValue))
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(hours == quickValue ? .black : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(hours == quickValue ? Color.white : Color.white.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        hours == quickValue ? Color.clear : Color.white.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .scaleEffect(hours == quickValue ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: hours == quickValue)
                }
            }
        }
    }
    
    private func formatValueForInput(_ value: Double) -> String {
        // Remove decimal if it's .0
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
    
    private func formatHours(_ value: Double) -> String {
        return value == 1 ? "hour" : "hours"
    }
    
    private func formatQuickValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))h"
        } else {
            return String(format: "%.1fh", value)
        }
    }
    
    private func validateValue(_ text: String) {
        let filtered = text.filter { "0123456789.".contains($0) }
        
        // Ensure only one decimal point
        let components = filtered.split(separator: ".")
        if components.count > 2 {
            return
        }
        
        // Parse the value
        if let doubleValue = Double(filtered) {
            // Round to nearest 0.5
            let rounded = (doubleValue * 2).rounded() / 2
            
            if range.contains(rounded) {
                hours = rounded
            } else if rounded < range.lowerBound {
                hours = range.lowerBound
                textValue = formatValueForInput(range.lowerBound)
            } else {
                hours = range.upperBound
                textValue = formatValueForInput(range.upperBound)
            }
        } else if filtered.isEmpty {
            hours = range.lowerBound
            textValue = formatValueForInput(range.lowerBound)
        }
    }
    
    private func incrementValue() {
        guard hours < range.upperBound else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            hours = min(hours + step, range.upperBound)
            textValue = formatValueForInput(hours)
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func decrementValue() {
        guard hours > range.lowerBound else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            hours = max(hours - step, range.lowerBound)
            textValue = formatValueForInput(hours)
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func selectValue(_ quickValue: Double) {
        withAnimation(.easeInOut(duration: 0.2)) {
            hours = quickValue
            textValue = formatValueForInput(quickValue)
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// Preview
struct HoursStepperField_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            VStack(alignment: .leading) {
                Text("Daily Limit")
                    .font(.custom("EBGaramond-Regular", size: 20))
                    .foregroundColor(.white)
                HoursStepperField(hours: .constant(2.0), isWeekly: false)
            }
            
            VStack(alignment: .leading) {
                Text("Weekly Limit")
                    .font(.custom("EBGaramond-Regular", size: 20))
                    .foregroundColor(.white)
                HoursStepperField(hours: .constant(21.0), isWeekly: true)
            }
        }
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}