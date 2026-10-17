import SwiftUI
import UIKit

extension Color {
    /// App brand green. Defined in code because the asset-catalog AccentColor isn't reliably
    /// applied as the global tint, and the widget has no asset catalog.
    static let brand = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.235, green: 0.780, blue: 0.580, alpha: 1)
            : UIColor(red: 0.118, green: 0.627, blue: 0.455, alpha: 1)
    })
}

extension ShapeStyle where Self == Color {
    static var brand: Color { .brand }
}
