import AppKit
import SpareCore

/// How the Memory screen asks a process to quit. Apps with a bundle get the graceful
/// `NSRunningApplication.terminate()` (macOS shows "Save changes?"); only processes without a bundle get
/// SIGTERM. A helper process of a bundled app is never signaled: quitting the app takes its helpers along.
struct AppQuitter: ProcessQuitter {
    /// Asks the running app with this pid to quit. Nil when the pid is not a registered app.
    let graceful: @Sendable (Int32) -> Bool?
    let signal: any ProcessQuitter

    init(
        graceful: @escaping @Sendable (Int32) -> Bool? = { pid in
            NSRunningApplication(processIdentifier: pid)?.terminate()
        },
        signal: any ProcessQuitter = SignalQuitter()
    ) {
        self.graceful = graceful
        self.signal = signal
    }

    func quit(_ process: RunningProcess) -> Bool {
        if process.appBundlePath != nil || process.appBundleID != nil {
            return graceful(process.pid) ?? false
        }
        return signal.quit(process)
    }
}
