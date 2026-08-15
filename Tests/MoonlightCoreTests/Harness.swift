import Foundation

/// A minimal assertion harness.
///
/// XCTest ships with Xcode, not with the Command Line Tools, and this package
/// builds with the Tools alone — so the suite is an ordinary executable that
/// exits non-zero on failure. CI runs it the same way a developer does:
///
///     swift run moonlight-tests
enum Check {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var currentSuite = ""

    static func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        do {
            try body()
        } catch {
            failures.append("\(name): threw \(error)")
        }
    }

    static func equal<T: Equatable>(
        _ actual: T, _ expected: T, _ what: String,
        file: StaticString = #file, line: UInt = #line
    ) {
        checks += 1
        guard actual != expected else { return }
        failures.append("""
            \(currentSuite) › \(what)
              expected: \(expected)
              actual:   \(actual)
              at \(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line)
            """)
    }

    static func close(
        _ actual: Double, _ expected: Double, _ tolerance: Double, _ what: String,
        file: StaticString = #file, line: UInt = #line
    ) {
        checks += 1
        guard abs(actual - expected) > tolerance else { return }
        failures.append("\(currentSuite) › \(what): expected ~\(expected), got \(actual)")
    }

    static func isTrue(
        _ value: Bool, _ what: String,
        file: StaticString = #file, line: UInt = #line
    ) {
        equal(value, true, what, file: file, line: line)
    }

    static func isNil<T>(
        _ value: T?, _ what: String,
        file: StaticString = #file, line: UInt = #line
    ) {
        checks += 1
        guard value != nil else { return }
        failures.append("\(currentSuite) › \(what): expected nil, got \(value!)")
    }

    static func notNil<T>(
        _ value: T?, _ what: String,
        file: StaticString = #file, line: UInt = #line
    ) {
        checks += 1
        guard value == nil else { return }
        failures.append("\(currentSuite) › \(what): expected a value, got nil")
    }

    static func report() -> Never {
        if failures.isEmpty {
            print("✓ \(checks) checks passed")
            exit(0)
        }
        print("✗ \(failures.count) of \(checks) checks failed\n")
        for failure in failures { print(failure, "\n") }
        exit(1)
    }
}
