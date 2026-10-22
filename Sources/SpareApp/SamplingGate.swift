import Foundation

/// Runs a periodic sample only while something that shows it is on screen. The menu bar panel is hidden,
/// not destroyed, so a plain `.task` on its view would keep running `ps` for the rest of the session.
/// Sources ("panel", "main") report their visibility; sampling runs while at least one is visible, once at
/// once (a sample never overlaps another, even when visibility flips quickly).
@MainActor
final class SamplingGate {
    private let interval: Duration
    private let sample: @MainActor () async -> Void
    private let debug: Bool
    private var visible: Set<String> = []
    private var task: Task<Void, Never>?
    private var inFlight = false

    /// How many samples ran so far. With `SPARE_DEBUG_SAMPLES` set, each one is also logged to stderr.
    private(set) var sampleCount = 0

    var isRunning: Bool { task != nil }

    init(
        interval: Duration,
        debug: Bool = ProcessInfo.processInfo.environment["SPARE_DEBUG_SAMPLES"] != nil,
        sample: @escaping @MainActor () async -> Void
    ) {
        self.interval = interval
        self.debug = debug
        self.sample = sample
    }

    func setVisible(_ isVisible: Bool, source: String) {
        if isVisible { visible.insert(source) } else { visible.remove(source) }
        if visible.isEmpty {
            task?.cancel()
            task = nil
        } else if task == nil {
            task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.tick()
                    try? await Task.sleep(for: self.interval)
                }
            }
        }
    }

    private func tick() async {
        guard !inFlight, !Task.isCancelled else { return }
        inFlight = true
        defer { inFlight = false }
        await sample()
        sampleCount += 1
        if debug {
            FileHandle.standardError.write(Data("spare: memory sample #\(sampleCount)\n".utf8))
        }
    }
}
