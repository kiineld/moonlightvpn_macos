import Foundation
import MoonlightCore

/// Links that open the app, and the identity it gives the service.
func deepLinkTests() {
    func parse(_ string: String) -> DeepLink? { URL(string: string).flatMap(DeepLink.init) }
    let sub = "https://example.com/sub/token"

    Check.suite("Deep link · adding a subscription") {
        Check.equal(parse("moonlight://install-config?url=https%3A%2F%2Fexample.com%2Fsub%2Ftoken"),
                    .addSubscription(sub), "the Clash form, encoded as it should be")
        Check.equal(parse("moonlight://import?url=https%3A%2F%2Fexample.com%2Fsub%2Ftoken"),
                    .addSubscription(sub), "Flowvy's `import`")
        Check.equal(parse("moonlight:///import?url=https%3A%2F%2Fexample.com%2Fsub%2Ftoken"),
                    .addSubscription(sub), "the action as a path")
        Check.equal(parse("MOONLIGHT://Install-Config?url=https%3A%2F%2Fexample.com%2Fsub%2Ftoken"),
                    .addSubscription(sub), "scheme and action in any case")
        Check.equal(parse("moonlight://install-config?url=https://example.com/sub/token?format=mihomo&device=mac"),
                    .addSubscription("https://example.com/sub/token?format=mihomo&device=mac"),
                    "an unencoded link keeps its own query, `&` and all")
        Check.equal(parse("moonlight://install-config?url=https%3A%2F%2Fexample.com%2Fsub%2F%D1%82%D0%BE%D0%BA%D0%B5%D0%BD"),
                    .addSubscription("https://example.com/sub/токен"), "non-ASCII, decoded")
    }

    Check.suite("Deep link · refused") {
        Check.isNil(parse("moonlight://install-config"), "no link")
        Check.isNil(parse("moonlight://install-config?url="), "an empty link")
        Check.isNil(parse("moonlight://install-config?url=file%3A%2F%2F%2Fetc%2Fpasswd"),
                    "a file, not a web address")
        Check.isNil(parse("moonlight://install-config?url=vless%3A%2F%2Fid%40host%3A443"),
                    "a single server, not a subscription")
        Check.isNil(parse("moonlight://delete-everything?url=https%3A%2F%2Fexample.com"),
                    "an action this app does not have")
        Check.isNil(parse("clash://install-config?url=https%3A%2F%2Fexample.com"),
                    "another app's scheme")
    }

    Check.suite("HWID · from the hardware") {
        let a = MachineIdentity.hwid(platformUUID: "01234567-89AB-CDEF-0123-456789ABCDEF")
        Check.equal(a, MachineIdentity.hwid(platformUUID: "01234567-89ab-cdef-0123-456789abcdef"),
                    "the same Mac, however its identifier is cased")
        Check.isTrue(a != MachineIdentity.hwid(platformUUID: "01234567-89AB-CDEF-0123-456789ABCDEE"),
                     "another Mac, another HWID")
        Check.isTrue(!a.contains("0123-456789AB"), "the hardware identifier itself is not in it")
        Check.isTrue(UUID(uuidString: a) != nil, "shaped like the UUIDs it replaces")
        Check.notNil(MachineIdentity.hwid(), "this Mac's hardware identifier can be read")
        Check.equal(MachineIdentity.hwid(), MachineIdentity.hwid(), "and gives the same HWID every time")
    }
}
