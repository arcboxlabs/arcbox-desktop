import Foundation
import OSLog

// MARK: - DNS Server

/// Lightweight UDP DNS server that resolves `*.arcbox.local` queries to container IPs.
///
/// The macOS resolver at `/etc/resolver/arcbox.local` directs all `.arcbox.local`
/// queries to `127.0.0.1:<port>`. This server answers those queries with A records
/// mapped from sanitized container names to their real Docker network IPs.
///
/// Thread-safe: record updates and reads are protected by `NSLock`.
public final class DNSServer: @unchecked Sendable {

    public static let defaultPort: UInt16 = 5553
    public static let domain = "arcbox.local"

    private let port: UInt16
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.arcboxlabs.dns", qos: .utility)
    private let lock = NSLock()
    /// Sanitized container DNS name (without `.arcbox.local` suffix) → IPv4 address string.
    private var records: [String: String] = [:]

    public init(port: UInt16 = DNSServer.defaultPort) {
        self.port = port
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Bind a UDP socket and start listening for DNS queries.
    public func start() throws {
        guard fd == -1 else { return } // already running

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else {
            throw DNSServerError.socketCreationFailed(errno)
        }

        // Allow address reuse so restarts don't fail with EADDRINUSE.
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(sock)
            throw DNSServerError.bindFailed(errno)
        }

        fd = sock

        let readSource = DispatchSource.makeReadSource(fileDescriptor: sock, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.handleIncoming()
        }
        let capturedFd = sock
        readSource.setCancelHandler { [weak self] in
            Darwin.close(capturedFd)
            self?.fd = -1
        }
        readSource.resume()
        source = readSource

        ClientLog.dns.info("DNS server started on 127.0.0.1:\(self.port, privacy: .public)")
    }

    /// Stop the DNS server and release the socket.
    public func stop() {
        source?.cancel()
        source = nil
        // fd is closed by the cancel handler
    }

    // MARK: - Record Management

    /// Replace all DNS records atomically.
    /// - Parameter newRecords: Map of sanitized container name → IPv4 string.
    ///   Keys should NOT include the `.arcbox.local` suffix.
    public func updateRecords(_ newRecords: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        records = newRecords
        ClientLog.dns.info("DNS records updated: \(newRecords.count, privacy: .public) entries")
    }

    /// Look up the IP for a given container DNS name (without suffix).
    private func resolve(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return records[name]
    }

    // MARK: - Packet Handling

    private func handleIncoming() {
        var clientAddr = sockaddr_storage()
        var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
        var buffer = [UInt8](repeating: 0, count: 512) // DNS over UDP max is 512 bytes

        let bytesRead = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(fd, &buffer, buffer.count, 0, sa, &addrLen)
            }
        }
        guard bytesRead > 12 else { return } // Minimum DNS header size

        let query = Array(buffer[0..<bytesRead])
        guard let response = buildResponse(query: query) else { return }

        response.withUnsafeBufferPointer { buf in
            withUnsafePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = sendto(fd, buf.baseAddress, buf.count, 0, sa, addrLen)
                }
            }
        }
    }

    /// Parse a DNS query and build a response packet.
    ///
    /// Supports only A (type 1) / IN (class 1) queries for `*.arcbox.local`.
    /// Returns NXDOMAIN for unknown names, REFUSED for non-matching domains.
    func buildResponse(query: [UInt8]) -> [UInt8]? {
        guard query.count >= 12 else { return nil }

        // Parse header
        let id = (UInt16(query[0]) << 8) | UInt16(query[1])
        let qdCount = (UInt16(query[4]) << 8) | UInt16(query[5])
        guard qdCount >= 1 else { return nil }

        // Parse first question
        guard let (qname, qnameEnd) = parseDomainName(query, offset: 12) else { return nil }
        guard qnameEnd + 4 <= query.count else { return nil }

        let qtype = (UInt16(query[qnameEnd]) << 8) | UInt16(query[qnameEnd + 1])
        let qclass = (UInt16(query[qnameEnd + 2]) << 8) | UInt16(query[qnameEnd + 3])

        let questionEnd = qnameEnd + 4
        let questionSection = Array(query[12..<questionEnd])

        // Only handle A (1) IN (1) queries
        guard qtype == 1, qclass == 1 else {
            return makeResponse(id: id, rcode: 5, question: questionSection) // REFUSED
        }

        // Check if domain ends with .arcbox.local
        let lowerName = qname.lowercased()
        let suffix = ".\(Self.domain)"
        guard lowerName.hasSuffix(suffix) else {
            return makeResponse(id: id, rcode: 5, question: questionSection) // REFUSED
        }

        // Extract container name (everything before .arcbox.local)
        let containerName = String(lowerName.dropLast(suffix.count))
        guard !containerName.isEmpty else {
            return makeResponse(id: id, rcode: 3, question: questionSection) // NXDOMAIN
        }

        // Look up IP
        guard let ip = resolve(containerName), let ipBytes = parseIPv4(ip) else {
            return makeResponse(id: id, rcode: 3, question: questionSection) // NXDOMAIN
        }

        // Build response with A record
        return makeResponse(id: id, rcode: 0, question: questionSection, answerIP: ipBytes)
    }

    // MARK: - DNS Packet Construction

    /// Build a DNS response packet.
    private func makeResponse(
        id: UInt16,
        rcode: UInt8,
        question: [UInt8],
        answerIP: [UInt8]? = nil
    ) -> [UInt8] {
        var response = [UInt8]()
        response.reserveCapacity(64)

        // Header (12 bytes)
        response.append(UInt8(id >> 8))
        response.append(UInt8(id & 0xFF))

        // Flags: QR=1 (response), AA=1 (authoritative), RD=1 (recursion desired, echoed)
        let flags: UInt16 = 0x8400 | UInt16(rcode)
        response.append(UInt8(flags >> 8))
        response.append(UInt8(flags & 0xFF))

        // QDCOUNT = 1
        response.append(0)
        response.append(1)

        // ANCOUNT
        let ancount: UInt16 = answerIP != nil ? 1 : 0
        response.append(UInt8(ancount >> 8))
        response.append(UInt8(ancount & 0xFF))

        // NSCOUNT = 0, ARCOUNT = 0
        response.append(contentsOf: [0, 0, 0, 0])

        // Question section (echoed from query)
        response.append(contentsOf: question)

        // Answer section (A record)
        if let ip = answerIP {
            // Name pointer to question (offset 12)
            response.append(0xC0)
            response.append(0x0C)

            // Type A (1)
            response.append(0)
            response.append(1)

            // Class IN (1)
            response.append(0)
            response.append(1)

            // TTL: 5 seconds (short so changes propagate quickly)
            response.append(0)
            response.append(0)
            response.append(0)
            response.append(5)

            // RDLENGTH: 4
            response.append(0)
            response.append(4)

            // RDATA: IPv4 address
            response.append(contentsOf: ip)
        }

        return response
    }

    // MARK: - DNS Parsing Helpers

    /// Parse a DNS domain name from a packet starting at `offset`.
    /// Returns the dotted name and the byte offset after the name.
    private func parseDomainName(_ packet: [UInt8], offset: Int, depth: Int = 0) -> (String, Int)? {
        guard depth < 10 else { return nil } // prevent infinite recursion from pointer cycles
        var labels: [String] = []
        var pos = offset

        while pos < packet.count {
            let length = Int(packet[pos])
            if length == 0 {
                pos += 1
                break
            }
            // Pointer (compression)
            if length & 0xC0 == 0xC0 {
                guard pos + 1 < packet.count else { return nil }
                let ptrOffset = Int(length & 0x3F) << 8 | Int(packet[pos + 1])
                guard let (name, _) = parseDomainName(packet, offset: ptrOffset, depth: depth + 1) else { return nil }
                let remaining = name.split(separator: ".").map(String.init)
                labels.append(contentsOf: remaining)
                pos += 2
                return (labels.joined(separator: "."), pos)
            }
            guard pos + 1 + length <= packet.count else { return nil }
            let label = String(bytes: packet[(pos + 1)..<(pos + 1 + length)], encoding: .ascii) ?? ""
            labels.append(label)
            pos += 1 + length
        }

        return (labels.joined(separator: "."), pos)
    }

    /// Parse an IPv4 address string into 4 bytes.
    private func parseIPv4(_ ip: String) -> [UInt8]? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var bytes = [UInt8]()
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            bytes.append(byte)
        }
        return bytes
    }
}

// MARK: - Container Name Sanitization

extension DNSServer {
    /// Convert a Docker container name to a valid DNS label.
    ///
    /// Rules:
    /// - Strip leading `/` (Docker convention)
    /// - Replace `_` and `.` with `-`
    /// - Remove characters not in `[a-z0-9-]`
    /// - Collapse consecutive `-` into one
    /// - Trim leading/trailing `-`
    /// - Lowercase
    /// - Truncate to 63 characters (DNS label max)
    public static func sanitizeContainerName(_ name: String) -> String {
        var result = name
        // Strip leading /
        if result.hasPrefix("/") {
            result = String(result.dropFirst())
        }
        result = result.lowercased()
        // Replace _ and . with -
        result = result.map { c -> Character in
            if c == "_" || c == "." { return "-" }
            return c
        }.map(String.init).joined()
        // Remove invalid characters
        result = result.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        // Collapse consecutive -
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        // Trim - from ends
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        // Truncate to 63
        if result.count > 63 {
            result = String(result.prefix(63))
            result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return result
    }
}

// MARK: - Errors

public enum DNSServerError: LocalizedError {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let code):
            return "Failed to create UDP socket: \(String(cString: strerror(code)))"
        case .bindFailed(let code):
            return "Failed to bind to port: \(String(cString: strerror(code)))"
        }
    }
}
