import SpareCore
import SwiftUI

/// The Spare Ring: the whole disk as one circle. Mint is space you can take back,
/// amber needs a look, white is the rest in use, the empty track is already free.
struct SpareRing: View {
    let totalBytes: Int64
    let freeBytes: Int64
    /// Slices at the end of the used arc; zero until a scan finished.
    var safeBytes: Int64 = 0
    var reviewBytes: Int64 = 0
    var scanning = false
    var diameter: CGFloat = 280
    private let width: CGFloat = 18

    var body: some View {
        let total = Double(max(totalBytes, 1))
        let used = min(1, max(0, 1 - Double(freeBytes) / total))
        let safe = min(used, Double(safeBytes) / total)
        let review = min(used - safe, Double(reviewBytes) / total)

        ZStack {
            Circle().stroke(Ink.track, lineWidth: width)
            arc(from: 0, to: used, color: Ink.used)
            arc(from: used - safe - review, to: used - safe, color: Ink.review)
            arc(from: used - safe, to: used, color: Ink.spare)
                .shadow(color: Ink.spare.opacity(safe > 0 ? 0.55 : 0), radius: 10)
            if scanning {
                Sweep(width: width)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.6), value: safeBytes)
        .animation(.easeOut(duration: 0.6), value: reviewBytes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        let disk = Text("\(ByteFormat.string(freeBytes)) free of \(ByteFormat.string(totalBytes))")
        guard safeBytes > 0 else { return disk }
        return disk + Text(verbatim: ". ") + Text("Safe \(ByteFormat.string(safeBytes))")
    }

    private func arc(from: Double, to: Double, color: Color) -> some View {
        Circle()
            .trim(from: max(0, from), to: max(0, to))
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }
}

private struct Sweep: View {
    let width: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(AngularGradient(colors: [Ink.spare.opacity(0), Ink.spare], center: .center, startAngle: .degrees(0), endAngle: .degrees(100)),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(turns * 360 - 90))
        }
    }
}

/// The big round call to action inside the ring.
struct ScanButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Ink.spare, Ink.glow], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Ink.spare.opacity(0.45), radius: 24)
                Text("Analyze")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.night)
            }
            .frame(width: 168, height: 168)
        }
        .buttonStyle(Press())
    }

    private struct Press: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
        }
    }
}
