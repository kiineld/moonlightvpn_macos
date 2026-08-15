import Foundation

/// Supervises the bundled mihomo core as a child process.
///
/// In system-proxy mode the core runs as the user, which needs no privileges at
/// all. TUN mode needs root to create the `utun` interface and to install
/// routes, so there the core is started by the privileged helper instead — see
/// ``HelperClient``. Both paths produce the same running core reachable on the
/// same loopback controller, which is why everything above this type is
/// indifferent to which one started it.
public final class MihomoProcess: @unchecked Sendable {

    public enum Failure: LocalizedError {
        case binaryMissing
        case exited(Int32, String)

        public var errorDescription: String? {
            switch self {
            case .binaryMissing:
                return "The mihomo core is missing from the app bundle"
            case .exited(let code, let output):
                let detail = output.isEmpty ? "" : "\n\(output)"
                return "Core exited with status \(code)\(detail)"
            }
        }
    }

    private let binary: URL
    private let dataDirectory: URL
    private var process: Process?
    private let lock = NSLock()

    /// The tail of the core's own log, kept so a failed start can say why.
    /// Bounded, because a core in a crash loop would otherwise grow it without
    /// limit for the lifetime of the app.
    private var logLines: [String] = []
    private static let logLimit = 200

    public var onLog: (@Sendable (String) -> Void)?
    /// Fired when the core exits without being asked to.
    public var onUnexpectedExit: (@Sendable (Int32) -> Void)?

    private var stopping = false

    public init(binary: URL, dataDirectory: URL) {
        self.binary = binary
        self.dataDirectory = dataDirectory
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    /// The reason TUN failed to come up, if it did.
    ///
    /// This has to be asked for explicitly, because the failure is **not** a
    /// crash: the core keeps running and keeps answering its API with the
    /// interface never established, so every other signal says "connected"
    /// while no traffic moves.
    public static func tunFailure(in log: String) -> String? {
        guard let line = log
            .split(whereSeparator: \.isNewline)
            .last(where: { $0.contains("Start TUN listening error") })
        else { return nil }

        // `add route: …: file exists` means another VPN client already owns the
        // routes auto-route wants. That is the common case by far, and the raw
        // message sends people looking for a bug in this app.
        if line.contains("file exists") || line.contains("add route") {
            return "Another VPN or proxy client already owns the system routes. "
                + "Quit it and connect again, or use system-proxy mode."
        }
        if let range = line.range(of: "Start TUN listening error: ") {
            // The core logs `msg="…"`, so the closing quote comes along with the
            // reason and would be shown to the user.
            return String(line[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return "The TUN interface could not be created"
    }

    public var recentLog: String {
        lock.lock(); defer { lock.unlock() }
        return logLines.joined(separator: "\n")
    }

    /// Validates a config without starting anything.
    ///
    /// Worth doing before every start: `mihomo -t` reports the offending key and
    /// line, whereas a core that fails at startup exits with a status and a log
    /// line the user never sees.
    public func validate(configPath: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw Failure.binaryMissing
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["-d", dataDirectory.path, "-t", "-f", configPath.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw Failure.exited(
                process.terminationStatus,
                String(data: output, encoding: .utf8)?
                    .split(whereSeparator: \.isNewline).suffix(6).joined(separator: "\n") ?? ""
            )
        }
    }

    public func start(configPath: URL) throws {
        stop()

        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw Failure.binaryMissing
        }
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = binary
        process.arguments = ["-d", dataDirectory.path, "-f", configPath.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.append(text)
        }

        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            lock.lock()
            let wasStopping = stopping
            lock.unlock()
            pipe.fileHandleForReading.readabilityHandler = nil
            if !wasStopping {
                onUnexpectedExit?(finished.terminationStatus)
            }
        }

        lock.lock()
        stopping = false
        logLines.removeAll()
        lock.unlock()

        try process.run()

        lock.lock()
        self.process = process
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let running = process
        stopping = true
        process = nil
        lock.unlock()

        guard let running, running.isRunning else { return }
        // SIGTERM first: mihomo tears down its interface and restores routes on
        // it. A SIGKILL here would leave a `utun` device and its routes behind.
        running.terminate()

        let deadline = Date().addingTimeInterval(5)
        while running.isRunning, Date() < deadline {
            usleep(50_000)
        }
        if running.isRunning {
            kill(running.processIdentifier, SIGKILL)
        }
    }

    private func append(_ text: String) {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        lock.lock()
        logLines.append(contentsOf: lines)
        if logLines.count > Self.logLimit {
            logLines.removeFirst(logLines.count - Self.logLimit)
        }
        lock.unlock()
        for line in lines { onLog?(line) }
    }

    deinit { stop() }
}
