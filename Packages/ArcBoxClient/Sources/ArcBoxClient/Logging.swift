import OSLog

enum ClientLog {
    private static let subsystem = "com.arcboxlabs.desktop"
    static let startup = Logger(subsystem: subsystem, category: "startup")
    static let daemon  = Logger(subsystem: subsystem, category: "daemon")
    static let helper  = Logger(subsystem: subsystem, category: "helper")
    static let grpc    = Logger(subsystem: subsystem, category: "grpc")
    static let cli     = Logger(subsystem: subsystem, category: "cli")
    static let dns     = Logger(subsystem: subsystem, category: "dns")
}
