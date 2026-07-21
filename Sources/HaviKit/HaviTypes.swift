import Foundation

public enum HaviLogLevel: String, Sendable, CaseIterable {
    case debug, info, warning, error
}

public enum HaviPriority: String, Sendable, CaseIterable {
    case high, medium, low
}

public enum HaviImageFormat: String, Sendable {
    case png, jpeg
}

public enum HaviAuthState: Equatable, Sendable {
    case unconfigured
    case authenticated(workspaceID: String)
    case needsReconnect
}

public struct HaviDeviceFlow: Sendable {
    public let userCode: String
    public let verificationURI: URL
    public let interval: Int

    public init(userCode: String, verificationURI: URL, interval: Int) {
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.interval = interval
    }
}

public enum HaviError: Error, Sendable {
    case notImplemented
    case notEnabled
    case encoding
}

public struct HaviLogEntry: Sendable, Equatable {
    public let level: HaviLogLevel
    public let category: String
    public let message: String

    public init(level: HaviLogLevel, category: String, message: String) {
        self.level = level
        self.category = category
        self.message = message
    }
}
