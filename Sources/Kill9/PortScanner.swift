import Foundation
import Darwin

enum NetProtocol: String, CaseIterable {
    case tcp = "TCP"
    case udp = "UDP"
}

/// One process bound to one port on one protocol (IPv4 + IPv6 entries are merged).
struct PortProcess: Identifiable, Equatable {
    let port: Int
    let pid: pid_t
    let command: String
    let user: String
    let proto: NetProtocol
    var addresses: [String]
    let path: String?

    var id: String { "\(proto.rawValue)-\(pid)-\(port)" }

    /// "/Applications/Foo.app" for anything living inside an app bundle (helpers included).
    var appBundlePath: String? {
        guard let path, let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    /// Display name used for grouping: the app's name, or the CLI command.
    var appName: String {
        guard let bundle = appBundlePath else { return command }
        return URL(fileURLWithPath: bundle).deletingPathExtension().lastPathComponent
    }

    var groupKey: String { appBundlePath ?? command }

    /// True when only reachable from this machine (127.x / ::1).
    var isLocalOnly: Bool {
        addresses.allSatisfy { $0.hasPrefix("127.") || $0 == "[::1]" }
    }

    var killCommand: String { "kill -9 $(lsof -ti \(proto.rawValue.lowercased()):\(port))" }
}

enum PortScanner {

    // MARK: Scan

    /// TCP: lsof +c 0 -nP -iTCP -sTCP:LISTEN   (listening servers)
    /// UDP: lsof +c 0 -nP -iUDP                 (bound sockets — UDP has no "listen" state)
    static func scan() throws -> [PortProcess] {
        let tcp = try parse(run("/usr/sbin/lsof", ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcLn"]), proto: .tcp)
        let udp = try parse(run("/usr/sbin/lsof", ["+c", "0", "-nP", "-iUDP", "-F", "pcLn"]), proto: .udp)
        return (tcp + udp).sorted {
            ($0.port, $0.proto == .tcp ? 0 : 1, $0.pid) < ($1.port, $1.proto == .tcp ? 0 : 1, $1.pid)
        }
    }

    private static func parse(_ output: String, proto: NetProtocol) -> [PortProcess] {
        var current = (pid: pid_t(0), command: "", user: "")
        var entries: [String: PortProcess] = [:]
        var paths: [pid_t: String?] = [:]

        // -F output is one field per line, prefixed by a tag character:
        // p<pid>  c<command>  L<login>  f<fd>  n<address:port>
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            var value = String(line.dropFirst())

            switch tag {
            case "p": current = (pid_t(value) ?? 0, "", "")
            case "c": current.command = value
            case "L": current.user = value
            case "n":
                // Connected UDP sockets look like "local:port->remote:port"; keep the local side.
                if let arrow = value.range(of: "->") { value = String(value[..<arrow.lowerBound]) }
                // Unbound sockets ("*:*") have no numeric port and are skipped here.
                guard let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                let host = String(value[..<colon])
                let key = "\(current.pid)-\(port)"

                if var existing = entries[key] {
                    if !existing.addresses.contains(host) { existing.addresses.append(host) }
                    entries[key] = existing
                } else {
                    if paths[current.pid] == nil { paths[current.pid] = executablePath(for: current.pid) }
                    entries[key] = PortProcess(
                        port: port, pid: current.pid,
                        command: current.command, user: current.user, proto: proto,
                        addresses: [host], path: paths[current.pid] ?? nil)
                }
            default:
                break
            }
        }
        return Array(entries.values)
    }

    // MARK: Kill

    /// Sends SIGTERM, waits up to ~1.5s, then SIGKILL if still alive.
    /// With `force`, sends SIGKILL immediately (same as `kill -9`).
    /// Returns an error message, or nil on success.
    static func terminate(pid: pid_t, force: Bool) -> String? {
        if Darwin.kill(pid, force ? SIGKILL : SIGTERM) != 0 {
            return describe(errno, pid: pid)
        }
        if force { return nil }

        for _ in 0..<15 {
            usleep(100_000)
            if !isAlive(pid) { return nil }
        }
        if Darwin.kill(pid, SIGKILL) != 0 {
            return describe(errno, pid: pid)
        }
        return nil
    }

    private static func isAlive(_ pid: pid_t) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    private static func describe(_ code: Int32, pid: pid_t) -> String? {
        switch code {
        case ESRCH: return nil // already gone — that's what we wanted
        case EPERM: return "PID \(pid) belongs to another user. Try: sudo kill -9 \(pid)"
        default:    return "PID \(pid): \(String(cString: strerror(code)))"
        }
    }

    // MARK: Helpers

    static func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    private static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // lsof exits 1 when nothing matches — that's not an error for us.
        return String(decoding: data, as: UTF8.self)
    }
}
