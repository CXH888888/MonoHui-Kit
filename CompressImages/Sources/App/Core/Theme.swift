import SwiftUI

extension Color {
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        }))
    }
    static let appleBlue = Color(red: 0, green: 0.443, blue: 0.89)
    static let appleBlueHover = Color(red: 0, green: 0.467, blue: 0.929)
    static let appleBluePressed = Color(red: 0, green: 0.431, blue: 0.859)
    static let appleInk = dynamic(light: Color(red: 0.114, green: 0.114, blue: 0.122),
                                  dark: Color(red: 0.961, green: 0.961, blue: 0.969))
    static let appleSoft = dynamic(light: Color(red: 0.431, green: 0.431, blue: 0.451),
                                   dark: Color(red: 0.631, green: 0.631, blue: 0.651))
    static let appleMuted = Color(red: 0.525, green: 0.525, blue: 0.545)
    static let appleSurface = dynamic(light: Color(red: 0.98, green: 0.98, blue: 0.988),
                                      dark: Color(red: 0.11, green: 0.11, blue: 0.122))
    static let appleSurface2 = dynamic(light: Color(red: 0.961, green: 0.961, blue: 0.969),
                                       dark: Color(red: 0.173, green: 0.173, blue: 0.18))
    static let appleCanvas = dynamic(light: .white,
                                     dark: Color(red: 0.11, green: 0.11, blue: 0.12))
    static let appleBorder = dynamic(light: Color.black.opacity(0.16),
                                     dark: Color.white.opacity(0.16))
}
