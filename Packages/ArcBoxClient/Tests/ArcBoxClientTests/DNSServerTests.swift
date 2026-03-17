@testable import ArcBoxClient
import Testing

// MARK: - Container Name Sanitization

@Suite("DNSServer.sanitizeContainerName")
struct SanitizeContainerNameTests {
    @Test func stripsLeadingSlash() {
        #expect(DNSServer.sanitizeContainerName("/myapp") == "myapp")
    }

    @Test func lowercases() {
        #expect(DNSServer.sanitizeContainerName("MyApp") == "myapp")
    }

    @Test func replacesUnderscoresAndDots() {
        #expect(DNSServer.sanitizeContainerName("my_app.web") == "my-app-web")
    }

    @Test func removesInvalidCharacters() {
        #expect(DNSServer.sanitizeContainerName("my@app!") == "myapp")
    }

    @Test func collapsesConsecutiveDashes() {
        #expect(DNSServer.sanitizeContainerName("my--app") == "my-app")
    }

    @Test func trimsLeadingAndTrailingDashes() {
        #expect(DNSServer.sanitizeContainerName("-myapp-") == "myapp")
    }

    @Test func truncatesTo63Characters() {
        let long = String(repeating: "a", count: 100)
        #expect(DNSServer.sanitizeContainerName(long).count == 63)
    }

    @Test func returnsEmptyForAllInvalidChars() {
        #expect(DNSServer.sanitizeContainerName("/@#$") == "")
    }

    @Test func handlesDockerComposeName() {
        #expect(DNSServer.sanitizeContainerName("/project_web_1") == "project-web-1")
    }
}

// MARK: - DNS Response Building

@Suite("DNSServer.buildResponse")
struct DNSBuildResponseTests {
    /// Build a minimal DNS query packet for a given domain name (A record, IN class).
    private func makeQuery(domain: String, qtype: UInt16 = 1, qclass: UInt16 = 1) -> [UInt8] {
        var packet = [UInt8]()
        // Header: ID=0x1234, flags=0x0100 (RD), QDCOUNT=1
        packet.append(contentsOf: [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        // QNAME
        for label in domain.split(separator: ".") {
            packet.append(UInt8(label.count))
            packet.append(contentsOf: label.utf8)
        }
        packet.append(0) // root label
        // QTYPE
        packet.append(UInt8(qtype >> 8))
        packet.append(UInt8(qtype & 0xFF))
        // QCLASS
        packet.append(UInt8(qclass >> 8))
        packet.append(UInt8(qclass & 0xFF))
        return packet
    }

    private func responseRcode(_ response: [UInt8]) -> UInt8 {
        response[3] & 0x0F
    }

    private func responseAncount(_ response: [UInt8]) -> UInt16 {
        (UInt16(response[6]) << 8) | UInt16(response[7])
    }

    @Test func successfulARecordLookup() {
        let server = DNSServer()
        server.updateRecords(["myapp": "172.17.0.2"])

        let query = makeQuery(domain: "myapp.arcbox.local")
        let response = server.buildResponse(query: query)

        #expect(response != nil)
        if let r = response {
            #expect(responseRcode(r) == 0) // NOERROR
            #expect(responseAncount(r) == 1) // 1 answer
            // Last 4 bytes should be the IP
            let ip = Array(r.suffix(4))
            #expect(ip == [172, 17, 0, 2])
        }
    }

    @Test func nxdomainForUnknownContainer() {
        let server = DNSServer()
        server.updateRecords(["myapp": "172.17.0.2"])

        let query = makeQuery(domain: "unknown.arcbox.local")
        let response = server.buildResponse(query: query)

        #expect(response != nil)
        if let r = response {
            #expect(responseRcode(r) == 3) // NXDOMAIN
            #expect(responseAncount(r) == 0)
        }
    }

    @Test func refusedForNonArcboxDomain() {
        let server = DNSServer()
        let query = makeQuery(domain: "example.com")
        let response = server.buildResponse(query: query)

        #expect(response != nil)
        if let r = response {
            #expect(responseRcode(r) == 5) // REFUSED
        }
    }

    @Test func refusedForNonAQueryType() {
        let server = DNSServer()
        // AAAA = type 28
        let query = makeQuery(domain: "myapp.arcbox.local", qtype: 28)
        let response = server.buildResponse(query: query)

        #expect(response != nil)
        if let r = response {
            #expect(responseRcode(r) == 5) // REFUSED
        }
    }

    @Test func refusedForBareArcboxLocal() {
        let server = DNSServer()
        // Bare "arcbox.local" doesn't match "*.arcbox.local" pattern — gets REFUSED
        let query = makeQuery(domain: "arcbox.local")
        let response = server.buildResponse(query: query)

        #expect(response != nil)
        if let r = response {
            #expect(responseRcode(r) == 5) // REFUSED
        }
    }

    @Test func caseInsensitiveLookup() {
        let server = DNSServer()
        server.updateRecords(["myapp": "10.0.0.1"])

        let query = makeQuery(domain: "MyApp.ArcBox.Local")
        let response = server.buildResponse(query: query)

        #expect(response != nil)
        if let r = response {
            #expect(responseRcode(r) == 0)
            #expect(responseAncount(r) == 1)
        }
    }

    @Test func rejectsPacketTooShort() {
        let server = DNSServer()
        let response = server.buildResponse(query: [0x00, 0x01])
        #expect(response == nil)
    }

    @Test func pointerCompressionWithDepthLimit() {
        let server = DNSServer()
        // Build a packet with a self-referencing pointer (infinite loop)
        var packet: [UInt8] = [
            0x12, 0x34, 0x01, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        // At offset 12: pointer to offset 12 (self-referencing)
        packet.append(contentsOf: [0xC0, 0x0C])
        // QTYPE and QCLASS
        packet.append(contentsOf: [0x00, 0x01, 0x00, 0x01])

        let response = server.buildResponse(query: packet)
        // Should return nil (depth limit hit) rather than stack overflow
        #expect(response == nil)
    }
}
