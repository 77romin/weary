import SwiftUI

enum WEARyTheme {
    static let snow = Color(hex: "FFFAFA")
    static let canvas = Color(hex: "F5F1E8")
    static let surface = Color(hex: "FFFCF6")
    static let ink = Color(hex: "171714")
    static let secondaryInk = Color(hex: "67665F")
    static let lime = Color(hex: "C7F25B")
    static let coral = Color(hex: "FF765F")
    static let line = Color.black.opacity(0.09)
    static let cornerRadius: CGFloat = 22
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        if hex.count == 3 {
            red = ((value >> 8) & 0xF) * 17
            green = ((value >> 4) & 0xF) * 17
            blue = (value & 0xF) * 17
        } else {
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }
}

private struct LightTextOutlineModifier: ViewModifier {
    let isActive: Bool

    private var outlineColor: Color {
        isActive ? .black.opacity(0.92) : .clear
    }

    func body(content: Content) -> some View {
        content
            .shadow(color: outlineColor, radius: 0, x: -0.7, y: 0)
            .shadow(color: outlineColor, radius: 0, x: 0.7, y: 0)
            .shadow(color: outlineColor, radius: 0, x: 0, y: -0.7)
            .shadow(color: outlineColor, radius: 0, x: 0, y: 0.7)
            .shadow(color: outlineColor, radius: 0, x: -0.5, y: -0.5)
            .shadow(color: outlineColor, radius: 0, x: 0.5, y: -0.5)
            .shadow(color: outlineColor, radius: 0, x: -0.5, y: 0.5)
            .shadow(color: outlineColor, radius: 0, x: 0.5, y: 0.5)
    }
}

extension View {
    /// Keeps light labels readable over photos and warm background colors.
    nonisolated func lightTextOutline(isActive: Bool = true) -> some View {
        modifier(LightTextOutlineModifier(isActive: isActive))
    }
}
