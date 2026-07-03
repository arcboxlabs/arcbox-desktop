import OSLog

enum FleetControlLog {
    private static let subsystem = "com.arcboxlabs.desktop"

    static let grpc = Logger(subsystem: subsystem, category: "fleet-grpc")
}
