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

        let script = """
        set -e
        mkdir -p '\(installRoot)'
        cp -f '\(helper.path)' '\(installRoot)/moonlight-helper'
        cp -f '\(core.path)' '\(installRoot)/mihomo'
        chown -R root:wheel '\(installRoot)'
        chmod 755 '\(installRoot)' '\(installRoot)/moonlight-helper' '\(installRoot)/mihomo'
        cat > '\(daemonPlist)' <<'PLIST'
        \(plist)
        PLIST
        chown root:wheel '\(daemonPlist)'
        chmod 644 '\(daemonPlist)'
        launchctl bootout system/\(HelperClient.label) 2>/dev/null || true
        launchctl bootstrap system '\(daemonPlist)'
        """
        try runAsAdministrator(script)
    }

    public static func uninstall() throws {
        let script = """
        launchctl bootout system/\(HelperClient.label) 2>/dev/null || true
        rm -f '\(daemonPlist)'
        rm -rf '\(installRoot)'
        rm -f '\(HelperClient.socketPath)'
        """
        try runAsAdministrator(script)
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
