import Foundation
import Testing
@testable import SpareApp

@MainActor @Suite struct SamplingGateTests {
    @MainActor final class Probe {
        var samples = 0
        var active = 0
        var maxActive = 0
        var duration: Duration = .milliseconds(0)

        func sample() async {
            active += 1
            maxActive = max(maxActive, active)
            samples += 1
            try? await Task.sleep(for: duration)
            active -= 1
        }
    }

    func makeGate(_ probe: Probe) -> SamplingGate {
        SamplingGate(interval: .milliseconds(10), debug: false) { await probe.sample() }
    }

    func settle(_ milliseconds: Int = 120) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    @Test func nothingRunsUntilSomethingIsVisible() async {
        let probe = Probe()
        let gate = makeGate(probe)

        await settle()

        #expect(probe.samples == 0)
        #expect(!gate.isRunning)
    }

    @Test func startsWhenVisibleAndSamplesRightAway() async {
        let probe = Probe()
        let gate = makeGate(probe)

        gate.setVisible(true, source: "panel")
        await settle()

        #expect(gate.isRunning)
        #expect(probe.samples >= 2)
        #expect(gate.sampleCount <= probe.samples)
        #expect(gate.sampleCount >= 1)
    }

    @Test func stopsWhenEverythingIsHidden() async {
        let probe = Probe()
        let gate = makeGate(probe)
        gate.setVisible(true, source: "panel")
        gate.setVisible(true, source: "main")
        await settle()

        gate.setVisible(false, source: "panel")
        #expect(gate.isRunning)  // the main window is still visible
        gate.setVisible(false, source: "main")
        await settle(30)
        let frozen = probe.samples
        await settle()

        #expect(!gate.isRunning)
        #expect(probe.samples == frozen)
    }

    @Test func neverSamplesInParallelEvenWhenToggledQuickly() async {
        let probe = Probe()
        probe.duration = .milliseconds(40)
        let gate = makeGate(probe)

        for _ in 0..<5 {
            gate.setVisible(true, source: "panel")
            gate.setVisible(true, source: "main")
            gate.setVisible(false, source: "panel")
            gate.setVisible(false, source: "main")
            gate.setVisible(true, source: "panel")
        }
        await settle(300)

        #expect(probe.maxActive == 1)
        #expect(probe.samples >= 2)
    }

    @Test func showingAgainAfterHidingResumes() async {
        let probe = Probe()
        let gate = makeGate(probe)
        gate.setVisible(true, source: "panel")
        await settle()
        gate.setVisible(false, source: "panel")
        await settle(40)
        let paused = probe.samples

        gate.setVisible(true, source: "panel")
        await settle()

        #expect(probe.samples > paused)
    }
}
