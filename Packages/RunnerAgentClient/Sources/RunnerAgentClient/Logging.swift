import OSLog

enum RunnerAgentLog {
    private static let subsystem = "com.arcboxlabs.desktop"

    static let grpc = Logger(subsystem: subsystem, category: "runner-agent-grpc")
}
