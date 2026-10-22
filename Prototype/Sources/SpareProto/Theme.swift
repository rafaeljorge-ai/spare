import SwiftUI

/// Night sky over a calm sea: the disk is the horizon, mint is space coming back to you.
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

/// "15,4 GB" in pt-BR style, "850 MB" below one gigabyte.
func size(_ gb: Double) -> String {
    if gb < 1 { return "\(Int((gb * 1000).rounded())) MB" }
    let text = String(format: "%.1f", gb).replacingOccurrences(of: ".", with: ",")
    return "\(text) GB"
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Ink.night)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(Capsule().fill(LinearGradient(colors: [Ink.spare, Ink.glow], startPoint: .leading, endPoint: .trailing)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct QuietButton: ButtonStyle {
    var tint: Color = Ink.primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(configuration.isPressed ? Ink.surface2.opacity(1.6) : Ink.surface2))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct Tile: View {
    let symbol: String
    let tint: Color
    var side: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            .frame(width: side, height: side)
            .overlay(Image(systemName: symbol).font(.system(size: side * 0.48, weight: .semibold)).foregroundStyle(.white))
    }
}

struct Badge: View {
    let safety: Safety

    var body: some View {
        let tint = safety == .safe ? Ink.spare : Ink.review
        Text(safety == .safe ? "Seguro" : "Revisar")
            .font(Txt.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.surface1))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Ink.line))
    }
}

struct Checkbox: View {
    let on: Bool
    let enabled: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(on ? Ink.spare : Color.clear)
            .frame(width: 18, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(on ? Color.clear : Ink.muted, lineWidth: 1.5))
            .overlay(Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Ink.night).opacity(on ? 1 : 0))
            .opacity(enabled ? 1 : 0.35)
    }
}
