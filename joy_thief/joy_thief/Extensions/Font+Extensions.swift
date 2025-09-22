import SwiftUI

extension Font {
    // MARK: - EB Garamond Font
    
    /// EB Garamond Regular font with custom size
    static func ebGaramond(size: CGFloat) -> Font {
        return Font.custom("EBGaramond-Regular", size: size)
    }
    
    // MARK: - Predefined EB Garamond Sizes
    
    /// Large title using EB Garamond (34pt)
    static var ebGaramondLargeTitle: Font {
        return Font.custom("EBGaramond-Regular", size: 34)
    }
    
    /// Title using EB Garamond (28pt)
    static var ebGaramondTitle: Font {
        return Font.custom("EBGaramond-Regular", size: 28)
    }
    
    /// Title 2 using EB Garamond (22pt)
    static var ebGaramondTitle2: Font {
        return Font.custom("EBGaramond-Regular", size: 22)
    }
    
    /// Title 3 using EB Garamond (20pt)
    static var ebGaramondTitle3: Font {
        return Font.custom("EBGaramond-Regular", size: 20)
    }
    
    /// Headline using EB Garamond (17pt)
    static var ebGaramondHeadline: Font {
        return Font.custom("EBGaramond-Regular", size: 17)
    }
    
    /// Body using EB Garamond (17pt)
    static var ebGaramondBody: Font {
        return Font.custom("EBGaramond-Regular", size: 17)
    }
    
    /// Callout using EB Garamond (16pt)
    static var ebGaramondCallout: Font {
        return Font.custom("EBGaramond-Regular", size: 16)
    }
    
    /// Subheadline using EB Garamond (15pt)
    static var ebGaramondSubheadline: Font {
        return Font.custom("EBGaramond-Regular", size: 15)
    }
    
    /// Footnote using EB Garamond (13pt)
    static var ebGaramondFootnote: Font {
        return Font.custom("EBGaramond-Regular", size: 13)
    }
    
    /// Caption using EB Garamond (12pt)
    static var ebGaramondCaption: Font {
        return Font.custom("EBGaramond-Regular", size: 12)
    }
    
    /// Caption 2 using EB Garamond (11pt)
    static var ebGaramondCaption2: Font {
        return Font.custom("EBGaramond-Regular", size: 11)
    }
}

// MARK: - UIFont Extension for UIKit components
extension UIFont {
    /// EB Garamond Regular font with custom size for UIKit
    static func ebGaramond(size: CGFloat) -> UIFont? {
        return UIFont(name: "EBGaramond-Regular", size: size)
    }
}

// MARK: - JTTextStyle Helper

public enum JTTextStyle {
    case title
    case title2
    case title3
    case body
    case bodyBold
    case caption
}

public extension Text {
    /// Apply EB Garamond font with automatic casing rules.
    /// - Parameter style: The `JTTextStyle` to apply.
    /// - Returns: A `Text` view configured with the correct EB Garamond font size and text-case.
    func jtStyle(_ style: JTTextStyle) -> some View {
        switch style {
        case .title:
            self
                .font(.ebGaramondTitle)
                .textCase(.lowercase)
        case .title2:
            self
                .font(.ebGaramondTitle2)
                .textCase(.lowercase)
        case .title3:
            self
                .font(.ebGaramondTitle3)
                .textCase(.lowercase)
        case .body:
            self
                .font(.ebGaramondBody)
                .textCase(.lowercase)
        case .bodyBold:
            self
                .font(.ebGaramondBody)
                .fontWeight(.bold)
                .textCase(.lowercase)
        case .caption:
            self
                .font(.ebGaramondCaption)
                .textCase(.uppercase)
        }
    }
} 