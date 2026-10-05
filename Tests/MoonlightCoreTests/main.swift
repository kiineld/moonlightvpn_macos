import Foundation

// One entry point for the whole suite. Each file contributes a function rather
// than a test class, because there is no XCTest here to discover them.
formatTests()
timeLeftTests()
subscriptionInfoTests()
remnawaveTests()
shareLinkTests()
configTests()
routingRuleTests()
deepLinkTests()
tunFailureTests()
nodePresentationTests()
autoPickerTests()
updaterTests()
geodataTests()
coreIntegrationTests()

Check.report()
