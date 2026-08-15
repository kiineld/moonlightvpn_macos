import AppKit

/// Lists installed applications for the split-tunnel screen.
///
/// The identity that matters is the **executable name**, because that is what
/// mihomo's `PROCESS-NAME` rules match — the core sees a process, not a bundle.
/// For `/Applications/Google Chrome.app` that is `Google Chrome`, from
/// `CFBundleExecutable`; guessing it from the bundle name is right most of the
/// time and wrong exactly where it matters (`Visual Studio Code` runs as
/// `Electron` in some builds, `zoom.us.app` runs as `zoom.us`).
public enum AppInventory {

    private static let searchPaths = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    public static func installed() -> [AppEntry] {
        var seen = Set<String>()
        var entries: [AppEntry] = []

        for directory in searchPaths {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for item in contents where item.hasSuffix(".app") {
                let path = directory + "/" + item
                guard let entry = describe(path), !seen.contains(entry.executable) else { continue }
                seen.insert(entry.executable)
                entries.append(entry)
            }
        }

        return entries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Apps with a window on screen right now, listed first in the UI because
    /// they are what a user reaching for this screen is usually thinking about.
    public static func running() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { application in
            guard application.activationPolicy == .regular,
                  let url = application.executableURL else { return nil }
            return url.lastPathComponent
        })
    }

    static func describe(_ path: String) -> AppEntry? {
        guard let bundle = Bundle(path: path) else { return nil }

        // `CFBundleExecutable` is the name the kernel gives the process, which is
        // the only name mihomo can match on.
        guard let executable = bundle.infoDictionary?["CFBundleExecutable"] as? String,
              !executable.isEmpty else { return nil }

        let display = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")

        return AppEntry(
            name: display,
            executable: executable,
            bundleID: bundle.bundleIdentifier,
            path: path
        )
    }
}
