import Foundation

/// Talks to the privileged helper that runs the core in TUN mode.
///
/// The helper is a root LaunchDaemon installed once, with one admin prompt. See
/// `Sources/MoonlightHelper/main.swift` for the trust boundary; the short
/// version is that this client can ask for exactly three things — version,
/// start with this config text, stop — and cannot name a binary or a path.
public struct HelperClient: Sendable {

    public static let socketPath = "/var/run/moonlight-helper.sock"
    public static let label = "vpn.moonlight.helper"
    public static let protocolVersion = 1

    public enum Failure: LocalizedError, Equatable {
        case notInstalled
        case versionMismatch(Int)
        case refused(String)
        case io(String)

        public var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "The privileged helper is not installed"
            case .versionMismatch(let version):
                return "Installed helper speaks protocol \(version); this build needs \(HelperClient.protocolVersion)"
            case .refused(let reason):
                return reason
            case .io(let reason):
                return "Could not talk to the helper: \(reason)"
            }
        }
    }

    public init() {}

    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.socketPath)
    }

    @discardableResult
    public func version() throws -> Int {
        let response = try send(["cmd": "version"])
        guard let version = response["version"] as? Int else {
            throw Failure.refused("helper gave no version")
        }
        guard version == Self.protocolVersion else {
            throw Failure.versionMismatch(version)
        }
        return version
    }

    public func start(config: String) throws {
        _ = try send(["cmd": "start", "config": config])
    }

    public func stop() throws {
        _ = try send(["cmd": "stop"])
    }

    public func status() throws -> (running: Bool, log: String) {
        let response = try send(["cmd": "status"])
        return (response["running"] as? Bool ?? false, response["log"] as? String ?? "")
    }

    // MARK: -

    private func send(_ request: [String: Any]) throws -> [String: Any] {
        guard isInstalled else { throw Failure.notInstalled }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.io("socket(): \(errno)") }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(Self.socketPath.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            // EACCES here means the account is not in `admin`, which is a
            // different problem from the helper being absent.
            throw errno == EACCES
                ? Failure.refused("This account is not an administrator, so it cannot use TUN mode")
                : Failure.io("connect(): \(errno)")
        }

        // A config with a large rule set runs to a few hundred KB, so the write
        // is looped rather than assumed to complete in one call.
        var payload = try JSONSerialization.data(withJSONObject: request)
        payload.append(UInt8(ascii: "\n"))
        try payload.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                guard written > 0 else { throw Failure.io("write(): \(errno)") }
                sent += written
            }
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            response.append(contentsOf: buffer[0..<count])
            if response.last == UInt8(ascii: "\n") { break }
        }

        guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw Failure.io("helper sent a malformed reply")
        }
        guard object["ok"] as? Bool == true else {
            throw Failure.refused(object["error"] as? String ?? "helper refused the request")
        }
        return object
    }
}
