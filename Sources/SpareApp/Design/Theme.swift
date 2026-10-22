import SwiftUI

/// Night sky over a calm sea: the disk is the horizon, mint is space coming back to you.
/// Tokens of the approved prototype (`.interface-design/system.md`).
enum Ink {
    static let night = Color(red: 0.09, green: 0.08, blue: 0.22)
    static let tide = Color(red: 0.04, green: 0.17, blue: 0.23)
    static let glow = Color(red: 0.16, green: 0.72, blue: 0.78)

    /// Space you can take back safely.
    static let spare = Color(red: 0.37, green: 0.95, blue: 0.75)
    /// Needs a human look before cleaning.
    static let review = Color(red: 1.0, green: 0.78, blue: 0.42)
    /// In use or destructive.
    static let busy = Color(red: 1.0, green: 0.50, blue: 0.50)

    static let primary = Color.white
    static let secondary = Color.white.opacity(0.72)
    static let tertiary = Color.white.opacity(0.50)
    static let muted = Color.white.opacity(0.32)

    static let surface1 = Color.white.opacity(0.06)
    static let surface2 = Color.white.opacity(0.10)
    static let line = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.07)
    static let used = Color.white.opacity(0.22)
}

enum Txt {
    static let display = Font.system(size: 44, weight: .semibold, design: .rounded)
    static let h1 = Font.system(size: 26, weight: .semibold)
    static let h2 = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let h3 = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let label = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11, weight: .medium)
    static let figure = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let path = Font.system(size: 11, design: .monospaced)
}

struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Ink.night, Ink.tide], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Ink.glow.opacity(0.22), .clear], center: .init(x: 0.62, y: 0.0), startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}
