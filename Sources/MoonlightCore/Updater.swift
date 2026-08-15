import Foundation
import AppKit

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
        case downloading(progress: Double)
        case installing
        case upToDate
        case failed(String)
    }

    @Published public private(set) var state: State = .idle

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
            LogStore.shared.client("Update available: \(latest)")
            state = .available(version: latest, notes: object["body"] as? String ?? "")
        } catch {
            LogStore.shared.client("Update check failed: \(error.localizedDescription)", level: .error)
            state = .failed(error.localizedDescription)
        }
    }

    public func install() async {
        guard let url = downloadURL else { return }
        state = .downloading(progress: 0)
        LogStore.shared.client("Downloading \(url.lastPathComponent)")

        do {
            let (temporary, response) = try await session.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw Failure.badResponse
            }

            let image = FileManager.default.temporaryDirectory
                .appendingPathComponent("Moonlight-update.dmg")
            try? FileManager.default.removeItem(at: image)
            try FileManager.default.moveItem(at: temporary, to: image)

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
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("moonlight-update-\(UUID().uuidString).sh")

        // `ditto` rather than `cp -R`: it preserves the bundle's extended
        // attributes and any signature, which a plain copy strips.
        let body = """
        #!/bin/sh
        set -e
        # Wait for the app to actually exit before touching its bundle.
        for _ in $(seq 1 100); do
          kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null || break
          sleep 0.1
        done

        mount=$(mktemp -d)
        hdiutil attach -nobrowse -readonly -noverify -quiet -mountpoint "$mount" '\(image.path)'
        trap 'hdiutil detach "$mount" -force >/dev/null 2>&1' EXIT

        rm -rf '\(bundle.path).old'
        mv '\(bundle.path)' '\(bundle.path).old'
        if ! ditto "$mount/Moonlight.app" '\(bundle.path)'; then
          # Put the old one back rather than leaving the user with no app.
          rm -rf '\(bundle.path)'
          mv '\(bundle.path).old' '\(bundle.path)'
          exit 1
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
        NSApp.terminate(nil)
    }

    enum Failure: LocalizedError {
        case badResponse
        case noAsset

        var errorDescription: String? {
            switch self {
            case .badResponse: return "GitHub did not answer with a release"
            case .noAsset: return "That release has no universal build attached"
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
