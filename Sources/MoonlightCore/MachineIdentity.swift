import Foundation
import CryptoKit
import IOKit

/// This Mac's identity for the service's device limit — the `x-hwid` header.
///
/// Derived from the hardware, so it is the same after an update, after the
/// app is deleted and installed again, and after its settings are wiped: the
/// service counts one Mac as one device however often the app is reinstalled.
/// It used to be a random UUID minted on first launch and stored with the
/// settings, which any of those minted afresh.
///
/// The hardware's own identifier never leaves the machine. What is sent is a
/// hash of it with this app's salt: stable for this Mac, meaningless anywhere
/// else, and not the identifier other software on the Mac can read.
public enum MachineIdentity {

    /// The hardware identifier macOS gives this Mac (`IOPlatformUUID`), or nil
    /// if it cannot be read.
    static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString,
                                                    kCFAllocatorDefault, 0)?.takeRetainedValue()
        guard let uuid = value as? String, !uuid.isEmpty else { return nil }
        return uuid
    }

    /// This Mac's HWID, or nil if the hardware cannot be read.
    public static func hwid() -> String? {
        platformUUID().map(hwid(platformUUID:))
    }

    /// The HWID for a hardware identifier: a salted SHA-256, laid out as a UUID
    /// like the random ones it replaces.
    public static func hwid(platformUUID: String) -> String {
        let digest = SHA256.hash(data: Data("moonlight-vpn/hwid/\(platformUUID.uppercased())".utf8))
        let hex = digest.prefix(16).map { String(format: "%02X", $0) }.joined()
        var parts: [Substring] = []
        var rest = Substring(hex)
        for length in [8, 4, 4, 4, 12] {
            parts.append(rest.prefix(length))
            rest = rest.dropFirst(length)
        }
        return parts.joined(separator: "-")
    }
}
