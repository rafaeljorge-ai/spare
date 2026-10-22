import SpareCore
import SwiftUI

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
        Text(safety.title)
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

/// "In use by Claude" / "Not verified" for items the user may not select.
struct ItemStatusLabel: View {
    let availability: ItemAvailability

    var body: some View {
        switch availability {
        case .ready:
            Text("Ready").font(Txt.caption).foregroundStyle(Ink.tertiary)
        case .inUse(let app):
            Label("In use by \(app)", systemImage: "lock.fill").font(Txt.caption).foregroundStyle(Ink.busy)
        case .notVerified:
            Label("Not verified", systemImage: "questionmark.circle").font(Txt.caption).foregroundStyle(Ink.review)
        }
    }
}

/// A label above a block of figures: "DISK", "MEMORY".
struct Overline: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Ink.muted)
    }
}

struct ScreenHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Txt.h1).tracking(-0.3)
                Text(subtitle).font(Txt.body).foregroundStyle(Ink.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }
}
