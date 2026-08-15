import Foundation
import MoonlightCore

private func response(_ headers: [String: String]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://panel.example/sub/abc")!,
        statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers
    )!
}

func subscriptionInfoTests() {
    Check.suite("SubscriptionInfo") {
        let full = SubscriptionInfo.fromHeaders(response([
            "subscription-userinfo": "upload=228170138; download=26629345280; total=107374182400; expire=1735689600",
            "profile-title": "Luna",
        ]))
        Check.equal(full.upload, 228_170_138, "upload")
        Check.equal(full.download, 26_629_345_280, "download")
        Check.equal(full.total, 107_374_182_400, "total")
        Check.equal(full.expire, Date(timeIntervalSince1970: 1_735_689_600), "expire")
        Check.equal(full.title, "Luna", "profile-title")
        Check.equal(full.used, 26_857_515_418, "used is upload + download")

        // In this format a zero is "no limit". Mapping it to 0 would show the
        // user an exhausted plan they still have.
        let unlimited = SubscriptionInfo.fromHeaders(response([
            "subscription-userinfo": "upload=0; download=100; total=0; expire=0",
        ]))
        Check.isNil(unlimited.total, "total=0 means unlimited")
        Check.isNil(unlimited.expire, "expire=0 means no expiry")
        Check.isNil(unlimited.usedFraction, "no quota means no fraction")
        Check.isTrue(unlimited.isActive, "no expiry is active")

        let partial = SubscriptionInfo.fromHeaders(response([
            "subscription-userinfo": "download=500",
        ]))
        Check.equal(partial.download, 500, "partial header keeps what it has")
        Check.isNil(partial.upload, "absent field stays unknown")
        Check.equal(partial.used, 500, "used tolerates a missing half")

        let malformed = SubscriptionInfo.fromHeaders(response([
            "subscription-userinfo": "upload; download=7; =; total=nonsense; expire=1735689600",
        ]))
        Check.equal(malformed.download, 7, "malformed fields do not discard good ones")
        Check.isNil(malformed.total, "unparseable total is unknown")
        Check.equal(malformed.expire, Date(timeIntervalSince1970: 1_735_689_600), "expire survives")

        let empty = SubscriptionInfo.fromHeaders(response([:]))
        Check.isNil(empty.used, "no header means unknown, not zero")
        Check.isNil(empty.daysLeft, "no expiry means unknown")

        let encoded = Data("Луна".utf8).base64EncodedString()
        let titled = SubscriptionInfo.fromHeaders(response(["profile-title": "base64:\(encoded)"]))
        Check.equal(titled.title, "Луна", "base64 profile-title is decoded")

        Check.equal(SubscriptionInfo(download: 200, total: 100).usedFraction, 1,
                    "over-quota clamps to 1")
        Check.close(SubscriptionInfo(download: 25, total: 100).usedFraction ?? 0, 0.25, 0.0001,
                    "used fraction")

        let merged = SubscriptionInfo(title: "Luna", download: 1, total: 100, deviceLimit: 5)
            .merging(SubscriptionInfo(download: 2))
        Check.equal(merged.download, 2, "a present field wins")
        Check.equal(merged.total, 100, "a nil must not erase a good value")
        Check.equal(merged.deviceLimit, 5, "device limit survives the merge")
        Check.equal(merged.title, "Luna", "title survives the merge")

        Check.equal(SubscriptionInfo(expire: Date().addingTimeInterval(86_400 * 11.5)).daysLeft, 12,
                    "days left rounds up")
        let expired = SubscriptionInfo(expire: Date().addingTimeInterval(-86_400))
        Check.equal(expired.daysLeft, 0, "an expired plan floors at zero days")
        Check.isTrue(!expired.isActive, "an expired plan is not active")
    }

    Check.suite("Remnawave /info") {
        let json = """
        {"response":{"user":{"username":"Luna","trafficLimit":107374182400,
        "expiresAt":"2027-01-01T00:00:00.000Z","hwidDeviceLimit":5},"devicesUsed":2}}
        """
        let info = try! SubscriptionInfo.fromRemnawaveInfo(Data(json.utf8))
        Check.equal(info.title, "Luna", "username")
        Check.equal(info.total, 107_374_182_400, "traffic limit")
        Check.equal(info.deviceLimit, 5, "hwid device limit")
        Check.equal(info.devicesUsed, 2, "devices used")
        Check.notNil(info.expire, "expiry parsed")
    }

    Check.suite("URL normalisation") {
        Check.equal(SubscriptionClient.normalize("panel.example/sub/abc")?.absoluteString,
                    "https://panel.example/sub/abc", "a bare host gains https")
        Check.equal(SubscriptionClient.normalize("https://panel.example/sub/abc/")?.absoluteString,
                    "https://panel.example/sub/abc",
                    "a trailing slash is trimmed so /mihomo does not become //mihomo")
        Check.isNil(SubscriptionClient.normalize("  "), "blank is not a URL")
        // A deep link must not be able to point the import flow at something
        // that is not a subscription endpoint.
        Check.isNil(SubscriptionClient.normalize("file:///etc/passwd"), "file: is refused")
        Check.isNil(SubscriptionClient.normalize("vless://uuid@host:443"), "a node link is not a subscription")

        Check.isTrue(SubscriptionClient.looksLikeClashConfig("proxies:\n  - name: a\n"),
                     "a clash config is detected by content")
        Check.isTrue(SubscriptionClient.looksLikeClashConfig("port: 7890\nproxies:\n"),
                     "proxies need not be the first key")
        Check.isTrue(!SubscriptionClient.looksLikeClashConfig("dmxlc3M6Ly9hYmM="),
                     "base64 is not mistaken for a config")
    }
}
