import OSLog

nonisolated enum Log {
    private static let subsystem = "com.arcboxlabs.desktop"
    static let startup = Logger(subsystem: subsystem, category: "startup")
    static let daemon = Logger(subsystem: subsystem, category: "daemon")
    static let helper = Logger(subsystem: subsystem, category: "helper")
    static let docker = Logger(subsystem: subsystem, category: "docker")
    static let container = Logger(subsystem: subsystem, category: "container")
    static let image = Logger(subsystem: subsystem, category: "image")
    static let volume = Logger(subsystem: subsystem, category: "volume")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let machine = Logger(subsystem: subsystem, category: "machine")
    static let pods = Logger(subsystem: subsystem, category: "pods")
    static let services = Logger(subsystem: subsystem, category: "services")
    static let context = Logger(subsystem: subsystem, category: "context")
    static let sleep = Logger(subsystem: subsystem, category: "sleep")
    static let terminal = Logger(subsystem: subsystem, category: "terminal")
}
