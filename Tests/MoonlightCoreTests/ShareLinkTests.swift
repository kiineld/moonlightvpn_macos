import Foundation
import MoonlightCore

/// Share links are the *fallback* path, and the cases that matter are the ones
/// that silently produce a config mihomo will refuse: a Reality node with no
/// public key, a ws node whose Host header defaults to a bare IP, a name with
/// emoji that makes `URLComponents` fail to parse the whole URL.
func shareLinkTests() {
    Check.suite("ShareLink · vless") {
        let link = "vless://11111111-2222-3333-4444-555555555555@example.com:443" +
                   "?security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBKEY&sid=ab12" +
                   "&flow=xtls-rprx-vision&type=tcp#%F0%9F%87%B3%F0%9F%87%B1%20Amsterdam"
        guard let proxy = ShareLink.mihomoProxy(link) else {
            Check.isTrue(false, "vless reality parses"); return
        }
        Check.equal(proxy["type"] as? String, "vless", "type")
        Check.equal(proxy["server"] as? String, "example.com", "server")
        Check.equal(proxy["port"] as? Int, 443, "port")
        Check.equal(proxy["uuid"] as? String, "11111111-2222-3333-4444-555555555555", "uuid")
        Check.equal(proxy["servername"] as? String, "www.microsoft.com", "sni")
        Check.equal(proxy["flow"] as? String, "xtls-rprx-vision", "flow")
        Check.equal(proxy["tls"] as? Bool, true, "reality implies tls")
        // The fragment is the display name and is routinely unescaped UTF-8 with
        // emoji — which is why URLComponents is not used to parse these.
        Check.equal(proxy["name"] as? String, "🇳🇱 Amsterdam", "percent-encoded emoji name")
        let reality = proxy["reality-opts"] as? [String: Any]
        Check.equal(reality?["public-key"] as? String, "PUBKEY", "reality public key")
        Check.equal(reality?["short-id"] as? String, "ab12", "reality short id")

        // Reality without a public key cannot work, and mihomo refuses the whole
        // config rather than skipping the node — so it is dropped here instead.
        let noKey = "vless://uuid@example.com:443?security=reality&sni=a.com#x"
        Check.isNil(ShareLink.mihomoProxy(noKey), "reality without pbk is dropped")

        let ws = "vless://uuid@1.2.3.4:443?security=tls&type=ws&path=%2Fws&host=cdn.example.com&sni=cdn.example.com#ws"
        let wsProxy = ShareLink.mihomoProxy(ws)
        Check.equal(wsProxy?["network"] as? String, "ws", "ws network")
        let wsOpts = wsProxy?["ws-opts"] as? [String: Any]
        Check.equal(wsOpts?["path"] as? String, "/ws", "ws path is percent-decoded")
        // Sending the dial IP as the Host header is what breaks CDN-fronted nodes.
        Check.equal((wsOpts?["headers"] as? [String: String])?["Host"], "cdn.example.com", "ws Host header")
    }

    Check.suite("ShareLink · other schemes") {
        let trojan = "trojan://password@example.com:443?sni=example.com&alpn=h2,http/1.1#TJ"
        let tj = ShareLink.mihomoProxy(trojan)
        Check.equal(tj?["type"] as? String, "trojan", "trojan type")
        Check.equal(tj?["password"] as? String, "password", "trojan password")
        Check.equal((tj?["alpn"] as? [String])?.count, 2, "alpn splits on comma")

        let ss = "ss://" + Data("aes-256-gcm:secret".utf8).base64EncodedString() + "@1.2.3.4:8388#SS"
        let shadow = ShareLink.mihomoProxy(ss)
        Check.equal(shadow?["type"] as? String, "ss", "ss type")
        Check.equal(shadow?["cipher"] as? String, "aes-256-gcm", "ss cipher from base64 userinfo")
        Check.equal(shadow?["password"] as? String, "secret", "ss password")

        let plainSS = "ss://aes-128-gcm:pw@1.2.3.4:8388#SS2"
        Check.equal(ShareLink.mihomoProxy(plainSS)?["cipher"] as? String, "aes-128-gcm",
                    "ss also accepts plain userinfo")

        let vmessJSON = #"{"v":"2","ps":"VM","add":"1.2.3.4","port":"443","id":"uuid","aid":"0","net":"ws","path":"/p","host":"h.example","tls":"tls"}"#
        let vmess = "vmess://" + Data(vmessJSON.utf8).base64EncodedString()
        let vm = ShareLink.mihomoProxy(vmess)
        Check.equal(vm?["type"] as? String, "vmess", "vmess type")
        Check.equal(vm?["port"] as? Int, 443, "vmess port is a string in the payload")
        Check.equal(vm?["name"] as? String, "VM", "vmess name")
        Check.equal(vm?["network"] as? String, "ws", "vmess ws")

        Check.isNil(ShareLink.mihomoProxy("hysteria2://x@y:443#z"),
                    "an unsupported scheme is dropped rather than half-built")
    }

    Check.suite("ShareLink · subscription bodies") {
        let links = "vless://a@h:443#one\nvless://b@h:443#two"
        Check.equal(ShareLink.decodeList(links).count, 2, "plain body")
        Check.equal(ShareLink.decodeList(Data(links.utf8).base64EncodedString()).count, 2,
                    "base64 body")
        // Panels strip padding and use the URL-safe alphabet interchangeably.
        let unpadded = Data(links.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        Check.equal(ShareLink.decodeList(unpadded).count, 2, "unpadded url-safe base64")
        Check.equal(ShareLink.decodeList("").count, 0, "empty body")
        Check.equal(ShareLink.decodeList("not a subscription").count, 0, "garbage body")
    }

    Check.suite("URIParts") {
        // The userinfo separator is the last @: a password may contain one.
        let parts = URIParts("trojan://pa@ss@example.com:443#n")
        Check.equal(parts?.user, "pa@ss", "password containing @")
        Check.equal(parts?.host, "example.com", "host after the last @")

        let v6 = URIParts("vless://uuid@[2001:db8::1]:443#n")
        Check.equal(v6?.host, "2001:db8::1", "bracketed IPv6 literal")
        Check.equal(v6?.port, 443, "IPv6 port")

        Check.isNil(URIParts("vless://uuid@example.com#n"), "a missing port is refused")
        Check.isNil(URIParts("vless://uuid@example.com:0#n"), "port 0 is refused")
        Check.isNil(URIParts("vless://uuid@example.com:99999#n"), "an out-of-range port is refused")
        Check.equal(URIParts("vless://uuid@example.com:443")?.name, "example.com:443",
                    "a nameless link falls back to host:port")
    }
}
