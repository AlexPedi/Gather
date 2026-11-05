import Foundation

public struct OnboardingState: Codable, Sendable {
    public var completed = false
    public var step = 0
    public var folderPath: String?
    public var intakeEnabled = true
    public var indexingEnabled = true
    public var launchAtLogin = true
    public init() {}
    private enum CodingKeys: String, CodingKey { case completed, step, folderPath, intakeEnabled, indexingEnabled, launchAtLogin }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        completed = try values.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        step = try values.decodeIfPresent(Int.self, forKey: .step) ?? 0
        folderPath = try values.decodeIfPresent(String.self, forKey: .folderPath)
        intakeEnabled = try values.decodeIfPresent(Bool.self, forKey: .intakeEnabled) ?? true
        indexingEnabled = try values.decodeIfPresent(Bool.self, forKey: .indexingEnabled) ?? true
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
    }
}
