import SwiftUI

struct KeyboardUtils {
    static func dismiss() {
        #if canImport(UIKit)
        // This forces any active text field to resign first responder status
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}