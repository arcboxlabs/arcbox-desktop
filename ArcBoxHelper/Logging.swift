import OSLog

enum HelperLog {
    private static let subsystem = "com.arcboxlabs.desktop.helper"
    static let xpc    = Logger(subsystem: subsystem, category: "xpc")
    static let socket = Logger(subsystem: subsystem, category: "socket")
    static let ops    = Logger(subsystem: subsystem, category: "ops")
}
