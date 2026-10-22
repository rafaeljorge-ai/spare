import Foundation

public struct SpareSettings: Codable, Sendable, Equatable {
    public var diskAlertThresholdGB: Int = 15
    public var memoryAlertsEnabled: Bool = true
    public var projectRootPaths: [String] = []
    public var projectIdleDays: Int = 30

    public init() {}

    public static func defaults(home: URL) -> SpareSettings {
        var settings = SpareSettings()
        settings.projectRootPaths = ProjectScanner.defaultRoots(home: home).map(\.path)
        return settings
    }

    enum CodingKeys: String, CodingKey {
        case diskAlertThresholdGB, memoryAlertsEnabled, projectRootPaths, projectIdleDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SpareSettings()
        diskAlertThresholdGB = try container.decodeIfPresent(Int.self, forKey: .diskAlertThresholdGB) ?? fallback.diskAlertThresholdGB
        memoryAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .memoryAlertsEnabled) ?? fallback.memoryAlertsEnabled
        projectRootPaths = try container.decodeIfPresent([String].self, forKey: .projectRootPaths) ?? fallback.projectRootPaths
        projectIdleDays = try container.decodeIfPresent(Int.self, forKey: .projectIdleDays) ?? fallback.projectIdleDays
    }
}
