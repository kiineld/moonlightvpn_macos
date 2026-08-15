import Foundation

// One entry point for the whole suite. Each file contributes a function rather
// than a test class, because there is no XCTest here to discover them.
formatTests()
subscriptionInfoTests()
shareLinkTests()
configTests()
splitTunnelTests()
tunFailureTests()
nodePresentationTests()
coreIntegrationTests()

Check.report()
