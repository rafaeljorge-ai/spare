import SwiftUI

/// The Spare Ring: the whole disk as one circle. Mint is space you can take back,
/// amber needs a look, white is the rest in use, the empty track is already free.
struct SpareRing: View {
    @ObservedObject var model: ProtoModel
    var diameter: CGFloat = 280
    private let width: CGFloat = 18

    var body: some View {
        let total = model.totalGB
        let free = model.freeGB / total
        let done = model.phase == .done
        let safe = done ? model.safeGB / total : 0
        let review = done ? model.reviewGB / total : 0
        let used = 1 - free

        ZStack {
            Circle().stroke(Ink.track, lineWidth: width)
            arc(from: 0, to: used, color: Ink.used)
            arc(from: used - safe - review, to: used - review, color: Ink.review)
                .opacity(done ? 1 : 0)
            arc(from: used - safe, to: used, color: Ink.spare)
                .shadow(color: Ink.spare.opacity(0.55), radius: 10)
                .opacity(done ? 1 : 0)
            if model.phase == .scanning {
                Sweep(width: width)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.6), value: model.phase)
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
                Text("Analisar")
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
