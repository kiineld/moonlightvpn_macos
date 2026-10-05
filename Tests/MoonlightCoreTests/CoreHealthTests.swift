import Foundation
import MoonlightCore

/// A TCP listener on loopback, standing in for whatever else on the machine
/// already has the port the core wants.
final class Squatter {
    private let fd: Int32
    let port: Int

    /// Listens on `port`, or on any free port when it is 0. Nil if it is taken.
    init?(port: Int = 0) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            close(fd)
            return nil
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(fd, $0, &length)
            }
        }
        self.fd = fd
        self.port = Int(in_port_t(bigEndian: actual.sin_port))
    }

    func leave() { close(fd) }
}

func coreHealthTests() {
    Check.suite("LocalPort · free and taken") {
        guard let squatter = Squatter() else {
            Check.isTrue(false, "a listener could be opened for the test")
            return
        }
        let port = squatter.port
        Check.isTrue(!LocalPort.isFree(port), "a port something listens on is not free")
        // The next free one, which is not the taken one — and not the one the
        // core's other listener is about to take either.
        let next = LocalPort.firstFree(from: port)
        Check.isTrue(next != nil && next != port, "the search moves past a taken port")
        if let next {
            let third = LocalPort.firstFree(from: port, avoiding: [next])
            Check.isTrue(third != nil && third != next && third != port,
                         "and past the port set aside for the other listener")
        }
        squatter.leave()
        Check.isTrue(LocalPort.isFree(port), "the port is free again once the listener has gone")
        Check.equal(LocalPort.firstFree(from: port), port, "a free port is its own answer")

        Check.isTrue(!LocalPort.isFree(0) && !LocalPort.isFree(70_000), "a number that is no port is not free")
    }

    Check.suite("RestartBudget · gives up on a core that keeps dying") {
        var budget = RestartBudget(limit: 3, window: 120)
        let start = Date(timeIntervalSince1970: 1_000_000)
        Check.isTrue(budget.spend(at: start), "the first restart is allowed")
        Check.isTrue(budget.spend(at: start.addingTimeInterval(10)), "and the second")
        Check.isTrue(budget.spend(at: start.addingTimeInterval(20)), "and the third")
        Check.isTrue(!budget.spend(at: start.addingTimeInterval(30)), "the fourth in two minutes is not")
        Check.isTrue(!budget.spend(at: start.addingTimeInterval(119)), "nor one just inside the window")
        // The refusals above took nothing from the budget, so it reopens as the
        // first three age out, not two minutes after the last attempt.
        Check.isTrue(budget.spend(at: start.addingTimeInterval(121)),
                     "a core that then runs for a while has its restarts back")
    }

    Check.suite("MihomoAPI · a core that is not there") {
        guard let squatter = Squatter() else {
            Check.isTrue(false, "a listener could be opened for the test")
            return
        }
        // A port nothing listens on: taken and released, so it is known free.
        let port = squatter.port
        squatter.leave()
        let api = MihomoAPI(port: port, secret: "none")
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            let asked = Date()
            let answered = await api.answers()
            Check.isTrue(!answered, "nothing answering reads as not answering")
            Check.isTrue(Date().timeIntervalSince(asked) < 3, "and is found out at once, not after a timeout")

            // With nothing alive to wait for, the wait ends on the first look
            // rather than running out its thirty seconds.
            let began = Date()
            let ready = await api.waitUntilReady(timeout: 30, while: { false })
            Check.isTrue(!ready, "a dead core is never ready")
            Check.isTrue(Date().timeIntervalSince(began) < 3, "and the wait for it stops as soon as it is known dead")
        }
        _ = semaphore.wait(timeout: .now() + 20)
    }
}
