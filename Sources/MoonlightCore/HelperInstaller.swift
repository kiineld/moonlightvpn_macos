import Foundation

/// Installs and removes the privileged helper.
///
/// One admin prompt, once. The alternative — asking for a password on every
/// connect — is what makes people leave TUN mode off, and TUN mode is the only
/// one that captures traffic from applications that ignore the system proxy.
///
/// `SMJobBless` is not used because it requires a Developer ID signature on both
/// the app and the helper, and this build ships unsigned. The install therefore
/// runs a script through `osascript … with administrator privileges`, which is
/// the same authorisation dialog, with the file copies and the `launchctl`
/// bootstrap written out where the user can read them in the prompt.
public enum HelperInstaller {

    public enum Failure: LocalizedError {
        case cancelled
        case missingResource(String)
        case script(String)

        public var errorDescription: String? {
            switch self {
            case .cancelled: return "Administrator authorisation was cancelled"
            case .missingResource(let name): return "\(name) is missing from the app bundle"
            case .script(let output): return "Helper installation failed:\n\(output)"
            }
        }
    }

    public static let installRoot = "/Library/Application Support/Moonlight"
    public static let daemonPlist = "/Library/LaunchDaemons/\(HelperClient.label).plist"

    /// The helper's root-owned copy of the core, which TUN mode runs.
    public static var installedCore: URL { URL(fileURLWithPath: "\(installRoot)/mihomo") }
    /// The installed helper program itself.
    public static var installedHelper: URL { URL(fileURLWithPath: "\(installRoot)/moonlight-helper") }

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: daemonPlist)
    }

    /// Copies the helper and a root-owned core into `/Library`, writes the
    /// LaunchDaemon, and bootstraps it.
    ///
    /// The core is copied rather than referenced in place: the helper must exec a
    /// binary no unprivileged account can rewrite, and `/Applications` is
    /// writable by admin users.
    public static func install(helper: URL, core: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw Failure.missingResource("moonlight-helper")
        }
        guard FileManager.default.isExecutableFile(atPath: core.path) else {
            throw Failure.missingResource("mihomo")
        }

        try runAsAdministrator(installScript(helper: helper, core: core))
    }

    /// The install as a script — the old helper unloaded and gone first, then
    /// the files replaced, then the new one loaded.
    ///
    /// The order matters twice over. `launchctl bootout` returns before launchd
    /// has finished removing the service, and a `bootstrap` in that window
    /// fails with "Bootstrap failed: 5: Input/output error"; so this waits
    /// until the service is really gone, and retries the load. And the files
    /// are replaced by rename, never by writing into them: copying over the
    /// binary of a helper or core that is still running rewrites pages it is
    /// executing.
    public static func installScript(helper: URL, core: URL) -> String {
        """
        set -e
        \(unloadAndWait)
        mkdir -p '\(installRoot)'
        cp -f '\(helper.path)' '\(installRoot)/moonlight-helper.new'
        cp -f '\(core.path)' '\(installRoot)/mihomo.new'
        mv -f '\(installRoot)/moonlight-helper.new' '\(installRoot)/moonlight-helper'
        mv -f '\(installRoot)/mihomo.new' '\(installRoot)/mihomo'
        chown -R root:wheel '\(installRoot)'
        chmod 755 '\(installRoot)' '\(installRoot)/moonlight-helper' '\(installRoot)/mihomo'
        cat > '\(daemonPlist)' <<'PLIST'
        \(plist)
        PLIST
        chown root:wheel '\(daemonPlist)'
        chmod 644 '\(daemonPlist)'
        for attempt in 1 2 3 4 5; do
          launchctl bootstrap system '\(daemonPlist)' && break
          [ "$attempt" = 5 ] && exit 1
          sleep 1
        done
        """
    }

    /// Unloads the helper and waits — up to fifteen seconds — until launchd no
    /// longer knows the service, which is when a new one can be loaded.
    private static var unloadAndWait: String {
        """
        launchctl bootout system/\(HelperClient.label) 2>/dev/null || true
        for _ in $(seq 1 150); do
          launchctl print system/\(HelperClient.label) >/dev/null 2>&1 || break
          sleep 0.1
        done
        """
    }

    public static func uninstall() throws {
        try runAsAdministrator(uninstallScript)
    }

    /// Removal as a script: unloaded and gone before the files go, so an
    /// install straight after it finds nothing half-removed.
    public static var uninstallScript: String {
        """
        \(unloadAndWait)
        rm -f '\(daemonPlist)'
        rm -rf '\(installRoot)'
        rm -f '\(HelperClient.socketPath)'
        """
    }

    private static var plist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(HelperClient.label)</string>
            <key>ProgramArguments</key>
            <array><string>\(installRoot)/moonlight-helper</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><true/>
        </dict>
        </plist>
        """
    }

    /// One authorisation dialog, showing the script.
    private static func runAsAdministrator(_ script: String) throws {
        // The script goes through a here-doc in a temp file rather than inline in
        // the AppleScript string: escaping a multi-line shell script into
        // AppleScript's own string literal is where this kind of code goes wrong.
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("moonlight-helper-\(UUID().uuidString).sh")
        try script.write(to: temporary, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"/bin/sh \" & quoted form of \"\(temporary.path)\" with administrator privileges",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let text = String(data: output, encoding: .utf8) ?? ""
            // -128 is AppleScript's "user cancelled", which is a decision, not a
            // failure, and must not be reported as one.
            if text.contains("-128") || process.terminationStatus == 1 && text.contains("User canceled") {
                throw Failure.cancelled
            }
            throw Failure.script(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
