import OSLog

enum ClientLog {
    private static let subsystem = "com.arcboxlabs.desktop"
    static let auth = Logger(subsystem: subsystem, category: "auth")
}
