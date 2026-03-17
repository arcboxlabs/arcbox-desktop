import Foundation

enum VmnetBridgeDiscovery {
    private struct Snapshot {
        var bridgeMembers: [String: [String]] = [:]
        var macAddresses: [String: String] = [:]
    }

    static func findBridgeInterface(targetMACAddress: String? = nil) -> String? {
        if let output = runIfconfigAll() {
            if let bridge = parseBridgeInterface(
                fromIfconfigOutput: output,
                targetMACAddress: targetMACAddress
            ) {
                return bridge
            }
        }
        return fallbackBridgeInterface()
    }

    static func parseBridgeInterface(
        fromIfconfigOutput output: String,
        targetMACAddress: String? = nil
    ) -> String? {
        let snapshot = parseSnapshot(fromIfconfigOutput: output)

        if let targetMACAddress {
            let normalizedTargetMACAddress = normalizeMACAddress(targetMACAddress)
            if let memberInterface = snapshot.macAddresses.first(where: {
                $0.key.hasPrefix("vmenet") && $0.value == normalizedTargetMACAddress
            })?.key,
               let bridgeInterface = snapshot.bridgeMembers.first(where: {
                   $0.value.contains(memberInterface)
               })?.key
            {
                return bridgeInterface
            }
        }

        return snapshot.bridgeMembers.first(where: {
            $0.value.contains(where: { $0.hasPrefix("vmenet") })
        })?.key
    }

    static func normalizeMACAddress(_ macAddress: String) -> String {
        let hexDigits = macAddress.lowercased().filter(\.isHexDigit)
        guard hexDigits.count == 12 else {
            return macAddress.lowercased()
        }

        return stride(from: 0, to: hexDigits.count, by: 2).map { index in
            let start = hexDigits.index(hexDigits.startIndex, offsetBy: index)
            let end = hexDigits.index(start, offsetBy: 2)
            return String(hexDigits[start..<end])
        }.joined(separator: ":")
    }

    private static func parseSnapshot(fromIfconfigOutput output: String) -> Snapshot {
        var snapshot = Snapshot()
        var currentInterface: String?

        for line in output.components(separatedBy: .newlines) {
            if !line.hasPrefix("\t") && !line.hasPrefix(" ") && line.contains(": flags=") {
                let name = String(line.prefix(while: { $0 != ":" }))
                currentInterface = name
                if name.hasPrefix("bridge") {
                    snapshot.bridgeMembers[name, default: []] = []
                }
                continue
            }

            guard let currentInterface else {
                continue
            }

            if currentInterface.hasPrefix("bridge"),
               let memberInterface = parseBridgeMember(fromLine: line)
            {
                snapshot.bridgeMembers[currentInterface, default: []].append(memberInterface)
            }

            if let macAddress = parseMACAddress(fromLine: line) {
                snapshot.macAddresses[currentInterface] = normalizeMACAddress(macAddress)
            }
        }

        return snapshot
    }

    static func fallbackBridgeInterface(
        interfaceExists: (String) -> Bool = interfaceExists(named:)
    ) -> String? {
        for i in 100..<110 {
            let name = "bridge\(i)"
            if interfaceExists(name) {
                return name
            }
        }
        return nil
    }

    private static func runIfconfigAll() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        proc.arguments = ["-a"]
        let pipe = Pipe()
        proc.standardOutput = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        guard proc.terminationStatus == 0 else {
            return nil
        }

        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    private static func parseBridgeMember(fromLine line: String) -> String? {
        guard let range = line.range(of: "member:") else {
            return nil
        }

        let remainder = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return remainder.split(separator: " ").first.map(String.init)
    }

    private static func parseMACAddress(fromLine line: String) -> String? {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count >= 2 else {
            return nil
        }
        guard parts[0] == "ether" || parts[0] == "lladdr" else {
            return nil
        }
        return String(parts[1])
    }

    private static func interfaceExists(named name: String) -> Bool {
        var ifr = ifreq()
        name.withCString { cstr in
            withUnsafeMutablePointer(to: &ifr.ifr_name) { ptr in
                _ = strcpy(
                    UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self),
                    cstr
                )
            }
        }
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return ioctl(fd, UInt(0xc0206911) /* SIOCGIFFLAGS */, &ifr) == 0
    }
}
