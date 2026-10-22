import SwiftUI

/// A confirmation card over a dimmed screen, in the prototype's style. Escape cancels; Return confirms only a non-destructive action.
struct ToolConfirmation<Content: View>: View {
    let title: LocalizedStringKey
    let confirm: LocalizedStringKey
    var destructive = true
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(Txt.h2)
                content
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(QuietButton())
                        .keyboardShortcut(.cancelAction)
                    // Return never confirms a destructive action: it has to be clicked.
                    if destructive {
                        Button(action: onConfirm) { Text(confirm) }
                            .buttonStyle(QuietButton(tint: Ink.busy))
                    } else {
                        Button(action: onConfirm) { Text(confirm) }
                            .buttonStyle(QuietButton())
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.night))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Ink.line))
        }
        .transition(.opacity)
    }
}

/// One line under the header: what just happened, with an optional action.
struct ToolNotice: View {
    let symbol: String
    let tint: Color
    let text: LocalizedStringKey
    var action: (label: LocalizedStringKey, run: () -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(Txt.body).foregroundStyle(Ink.secondary).lineLimit(2)
            Spacer()
            if let action {
                Button(action: action.run) { Text(action.label) }.buttonStyle(QuietButton())
            }
            Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.tertiary)
                .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.surface1))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Ink.line))
    }
}

/// A card that lists rows with hairline dividers.
struct ToolList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.surface1))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Ink.line))
    }
}

/// Centered message for empty, idle and error states.
struct ToolEmptyState: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Tile(symbol: symbol, tint: Ink.glow, side: 40)
            Text(text).font(Txt.body).foregroundStyle(Ink.tertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
