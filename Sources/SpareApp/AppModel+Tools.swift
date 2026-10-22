import SpareCore

/// Wiring of the tool screens (Large Files, Memory, Settings) and the alerts to the app model.
/// The models take closures instead of the app model itself, so tests can build them on their own.
extension AppModel {
    func makeLargeFilesModel() -> LargeFilesModel {
        LargeFilesModel(
            home: home, environment: { [unowned self] in environment },
            didChangeDisk: { [unowned self] in refreshDisk() })
    }

    func makeMemoryScreenModel() -> MemoryScreenModel {
        MemoryScreenModel(environment: { [unowned self] in environment })
    }

    func makeAlertCenter() -> AlertCenter {
        let center = AlertCenter(poster: SystemAlertPoster())
        center.onOpen = { [unowned self] kind in show(kind == .memory ? .memory : .overview) }
        return center
    }

    /// Asks for notification permission and checks the numbers once. Real launches only: snapshots and
    /// tests never call it.
    func startAlerts() {
        alerts.start()
        evaluateAlerts()
    }

    func evaluateAlerts() {
        alerts.evaluate(disk: disk, memory: memory, settings: settings)
    }
}
