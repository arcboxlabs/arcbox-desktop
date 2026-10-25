import Foundation

/// A Platform workspace available to the signed-in user.
public struct FleetWorkspace: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let plan: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, name: String, plan: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.plan = plan
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Short-lived Platform credential presented once to the local Fleet Agent.
public struct FleetEnrollmentToken: Codable, Sendable, Equatable {
    public let token: String
    public let expiresAt: Date

    public init(token: String, expiresAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
    }
}
