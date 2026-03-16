/// ArcBoxHelperCtl — Thin CLI bridge to the XPC helper.
///
/// Usage:
///   arcbox-helperctl route ensure --subnet 172.16.0.0/12 --bridge-mac aa:bb:cc:dd:ee:ff
///   arcbox-helperctl route remove --subnet 172.16.0.0/12
///   arcbox-helperctl route status --subnet 172.16.0.0/12
///
/// Output: JSON to stdout. Exit code 0 = success, 1 = error.
/// Designed to be called by arcbox-daemon (Rust) via Command::new().

import Foundation

// Load the helper protocol from the shared source.
// (HelperProtocol.swift is compiled into this target too.)

let args = CommandLine.arguments

guard args.count >= 3, args[1] == "route" else {
    fputs("Usage: arcbox-helperctl route {ensure|remove|status} [--subnet ...] [--bridge-mac ...]\n", stderr)
    exit(1)
}

let subcommand = args[2]

func arg(_ name: String) -> String? {
    guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

let subnet = arg("--subnet") ?? "172.16.0.0/12"

// Connect to XPC helper.
let conn = NSXPCConnection(machServiceName: "com.arcboxlabs.desktop.helper", options: .privileged)
conn.remoteObjectInterface = NSXPCInterface(with: ArcBoxHelperProtocol.self)
conn.resume()

let sem = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0

guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
    fputs("{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}\n", stderr)
    exitCode = 1
    sem.signal()
}) as? ArcBoxHelperProtocol else {
    fputs("{\"ok\":false,\"error\":\"failed to create XPC proxy\"}\n", stderr)
    exit(1)
}

switch subcommand {
case "ensure":
    guard let mac = arg("--bridge-mac") else {
        fputs("{\"ok\":false,\"error\":\"--bridge-mac required\"}\n", stderr)
        exit(1)
    }
    proxy.ensureRoute(subnet: subnet, bridgeMac: mac) { json, error in
        if let error {
            print("{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}")
            exitCode = 1
        } else if let json {
            print(json)
        } else {
            print("{\"ok\":false,\"error\":\"no response\"}")
            exitCode = 1
        }
        sem.signal()
    }

case "remove":
    proxy.removeRoute(subnet: subnet) { error in
        if let error {
            print("{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}")
            exitCode = 1
        } else {
            print("{\"ok\":true}")
        }
        sem.signal()
    }

case "status":
    proxy.routeStatus(subnet: subnet) { json in
        print(json ?? "{\"installed\":false}")
        sem.signal()
    }

default:
    fputs("Unknown subcommand: \(subcommand)\n", stderr)
    exit(1)
}

sem.wait()
conn.invalidate()
exit(exitCode)
