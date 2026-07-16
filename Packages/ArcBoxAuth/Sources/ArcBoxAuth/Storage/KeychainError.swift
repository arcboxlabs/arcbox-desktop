import Security

public enum KeychainError: Error, Sendable, Equatable {
    case unhandledStatus(OSStatus)
    case corruptedItem
}
