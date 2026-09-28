import Foundation
import AppKit
import CryptoKit

/// Checks GitHub for a newer release and installs it.
///
/// The app is not notarised, so it cannot use Sparkle's usual signature chain
/// and there is no App Store to hand the job to. What it can do is what a user
/// would do by hand — fetch the release, mount the disk image, swap the bundle,
/// relaunch — without them having to.
///
/// The swap is deliberately done by a **detached shell script**, not in-process:
/// the app cannot replace its own bundle while running, and a process that
/// deletes its own executable behaves unpredictably from that moment on. The
/// script waits for the app to exit, does the swap, and starts the new one.
@MainActor
public final class Updater: ObservableObject {

    public enum State: Equatable {
        case idle
        case checking
        /// A newer version exists.
        case available(version: String, notes: String)
        /// Bytes so far, and the size when the server gave one — so the screen
        /// can say how much is left rather than spin.
        case downloading(received: Int64, total: Int64?)
        /// Checking the download against the checksum the release publishes.
        case verifying
        /// The app is about to quit so the new copy can replace it.
        case installing
        case upToDate
        case failed(String)

        /// Downloading, verifying or installing — the stretch the user waits
        /// through.
        public var isUnderWay: Bool {
            switch self {
            case .downloading, .verifying, .installing: return true
            default: return false
            }
        }
    }

    @Published public private(set) var state: State = .idle
    /// The version being fetched or installed.
    @Published public private(set) var pendingVersion: String?

    private let repository: String
    private let currentVersion: String
    private let session: URLSession

    public init(
        repository: String = "kiineld/moonlightvpn_macos",
        currentVersion: String = Bundle.main.appVersion
    ) {
        self.repository = repository
        self.currentVersion = currentVersion

        let configuration = URLSessionConfiguration.ephemeral
        // GitHub over the machine's own proxy would go through the tunnel this
        // app is managing; a swap mid-download would kill it.
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    private var downloadURL: URL?
    private var checksumURL: URL?

    public func check() async {
        guard state != .checking else { return }
        state = .checking
        LogStore.shared.client("Checking for updates (current \(currentVersion))")

        do {
            var request = URLRequest(url: URL(string:
                "https://api.github.com/repos/\(repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String else {
                throw Failure.badResponse
            }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard Self.isNewer(latest, than: currentVersion) else {
                LogStore.shared.client("Already on the latest version (\(currentVersion))")
                state = .upToDate
                return
            }

            // The universal build, so the download works on either architecture
            // and cannot install the wrong slice.
            let assets = object["assets"] as? [[String: Any]] ?? []
            guard let asset = assets.first(where: {
                ($0["name"] as? String) == "Moonlight-universal.dmg"
            }), let urlString = asset["browser_download_url"] as? String,
               let url = URL(string: urlString) else {
                throw Failure.noAsset
            }

            downloadURL = url
            checksumURL = assets.first(where: {
                ($0["name"] as? String) == "Moonlight-universal.dmg.sha256"
            }).flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
            pendingVersion = latest
            LogStore.shared.client("Update available: \(latest)")
            state = .available(version: latest, notes: object["body"] as? String ?? "")
        } catch {
            LogStore.shared.client("Update check failed: \(error.localizedDescription)", level: .error)
            state = .failed(error.localizedDescription)
        }
    }

    public func install() async {
        guard let url = downloadURL else { return }
        state = .downloading(received: 0, total: nil)
        LogStore.shared.client("Downloading \(url.lastPathComponent)")

        let image = FileManager.default.temporaryDirectory
            .appendingPathComponent("Moonlight-update.dmg")
        do {
            try await Download.run(from: url, to: image) { [weak self] received, total in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(received: received, total: total)
                }
            }

            // A truncated or corrupted image fails to mount only after the app
            // has quit; checked here, the user keeps a working app instead.
            if let checksumURL {
                state = .verifying
                let (data, response) = try await session.data(from: checksumURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let expected = Self.checksum(fromSHA256File: String(decoding: data, as: UTF8.self))
                else { throw Failure.badResponse }
                let actual = try await Task.detached(priority: .userInitiated) {
                    try Self.sha256(of: image)
                }.value
                guard actual == expected else { throw Failure.damaged }
            }

            state = .installing
            try swap(using: image)
        } catch {
            LogStore.shared.client("Update failed: \(error.localizedDescription)", level: .error)
            state = .failed(error.localizedDescription)
        }
    }

    /// Writes the swap script, detaches it, and quits.
    private func swap(using image: URL) throws {
        let bundle = Bundle.main.bundleURL
        // Checked *before* quitting. Run from the DMG, or from the read-only
        // copy macOS translocates a quarantined download to, the bundle cannot
        // be replaced — the script failed after the app had already gone, and
        // the user was left with no app at all.
        let parent = bundle.deletingLastPathComponent().path
        guard !bundle.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: parent) else {
            throw Failure.notReplaceable
        }
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("moonlight-update-\(UUID().uuidString).sh")

        // `ditto` rather than `cp -R`: it preserves the bundle's extended
        // attributes and any signature, which a plain copy strips.
        let body = """
        #!/bin/sh
        # Wait for the app to actually exit before touching its bundle. Longer
        # than the app's own quit takes, including a TUN teardown.
        app=\(ProcessInfo.processInfo.processIdentifier)
        for _ in $(seq 1 300); do
          kill -0 $app 2>/dev/null || break
          sleep 0.1
        done
        # Still there means its quit is stuck. Swapping the bundle under a live
        # app left it running the old version, and `open` below then only
        # brought that old window forward — the update looked like it had done
        # nothing. The next launch cleans up whatever a forced stop leaves.
        if kill -0 $app 2>/dev/null; then
          kill -TERM $app 2>/dev/null
          sleep 3
          kill -KILL $app 2>/dev/null
          sleep 0.5
        fi

        # Whatever fails from here, the user gets an app back: the old one.
        fail() { open '\(bundle.path)'; exit 1; }

        mount=$(mktemp -d)
        hdiutil attach -nobrowse -readonly -noverify -quiet -mountpoint "$mount" '\(image.path)' || fail
        trap 'hdiutil detach "$mount" -force >/dev/null 2>&1' EXIT
        [ -d "$mount/Moonlight.app" ] || fail

        rm -rf '\(bundle.path).old'
        mv '\(bundle.path)' '\(bundle.path).old' || fail
        if ! ditto "$mount/Moonlight.app" '\(bundle.path)'; then
          # Put the old one back rather than leaving the user with no app.
          rm -rf '\(bundle.path)'
          mv '\(bundle.path).old' '\(bundle.path)'
          fail
        fi
        rm -rf '\(bundle.path).old'
        xattr -dr com.apple.quarantine '\(bundle.path)' 2>/dev/null || true
        open '\(bundle.path)'
        rm -f '\(image.path)' "$0"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)

        LogStore.shared.client("Installing update and restarting")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        try process.run()

        // Quit so the script can replace the bundle. Terminating rather than
        // exiting lets the delegate bring the tunnel down first.
        AppExit.quit()
    }

    /// The hash in a `.sha256` file as `shasum -a 256` writes it, lower-cased;
    /// nil for anything that is not one.
    nonisolated public static func checksum(fromSHA256File text: String) -> String? {
        guard let field = text.split(whereSeparator: { $0 == " " || $0.isNewline }).first else {
            return nil
        }
        let hash = field.lowercased()
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
        return hash
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    enum Failure: LocalizedError {
        case badResponse
        case noAsset
        case notReplaceable
        case damaged

        var errorDescription: String? {
            switch self {
            case .badResponse: return "GitHub did not answer with a release"
            case .noAsset: return "That release has no universal build attached"
            case .notReplaceable:
                return "Move Moonlight to the Applications folder, then update"
            case .damaged:
                return "The download arrived damaged. Try again"
            }
        }
    }

    /// Compares dotted versions numerically, so 1.0.10 beats 1.0.9 — which a
    /// string comparison gets backwards.
    nonisolated public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

/// A download that reports its progress as it goes.
///
/// `URLSession.download(from:)` only answers at the end, so the screen could
/// say nothing but "Загрузка" for a 35 MB file. A session with a delegate gets
/// every chunk; updates are thinned to one per quarter megabyte so the main
/// thread is not flooded.
private final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Int64, Int64?) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var reported: Int64 = 0
    private let lock = NSLock()

    private init(destination: URL, onProgress: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    static func run(
        from url: URL, to destination: URL,
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws {
        let download = Download(destination: destination, onProgress: onProgress)
        let configuration = URLSessionConfiguration.ephemeral
        // Around the tunnel, as the rest of the updater: a swap mid-download
        // would kill it.
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            download.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten - reported >= 256 * 1024
                || totalBytesWritten == totalBytesExpectedToWrite else { return }
        reported = totalBytesWritten
        onProgress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temporary file is deleted as soon as this returns.
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
                throw Updater.Failure.badResponse
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}

/// Quitting the app from code.
public enum AppExit {
    /// Asks AppKit to terminate on the next turn of the run loop.
    ///
    /// Never directly from a `Task` or any other main-queue block: the app
    /// answers "terminate later" while it brings the tunnel down, and AppKit
    /// waits for that answer in a nested run loop — inside the block that
    /// asked. The main queue cannot start another block until that one returns,
    /// so neither the teardown nor its ten-second fallback ever ran, and the
    /// app hung in "quitting" until it was force-quit. The updater did exactly
    /// that, so an update never relaunched into the new version.
    @MainActor
    public static func quit() {
        RunLoop.main.perform { NSApp.terminate(nil) }
    }
}
