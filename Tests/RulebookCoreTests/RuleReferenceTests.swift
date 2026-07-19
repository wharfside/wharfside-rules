import Foundation
import Testing
@testable import RulebookCore

@Test func ruleReferenceRoundTripsKnownKind() throws {
    let reference = RuleReference(
        type: .runtimeBehavior,
        title: "Runtime sends SIGTERM before SIGKILL",
        url: "https://example.invalid/runtime",
        runtimeVersions: ["1.0.0"]
    )

    let encoded = try JSONEncoder().encode(reference)
    let decoded = try JSONDecoder().decode(RuleReference.self, from: encoded)

    #expect(decoded == reference)
}

@Test func unknownRuleReferenceKindRoundTripsVerbatim() throws {
    let json = #"{"type":"security-advisory","title":"Future metadata"}"#

    let decoded = try JSONDecoder().decode(RuleReference.self, from: Data(json.utf8))
    #expect(decoded.type.rawValue == "security-advisory")

    let encoded = try JSONEncoder().encode(decoded)
    let roundTripped = try JSONDecoder().decode(RuleReference.self, from: encoded)
    #expect(roundTripped.type.rawValue == "security-advisory")
}
