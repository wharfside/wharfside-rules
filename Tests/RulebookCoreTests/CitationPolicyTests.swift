import Foundation
import Testing
@testable import RulebookCore

private struct CitationPolicyReport: Equatable {
    var errors: [String] = []
    var warnings: [String] = []
}

private enum CitationPolicy {
    private static let knownKinds: [RuleReference.Kind] = [
        .runtimeSource,
        .runtimeBehavior,
        .issue,
        .releaseNote,
        .documentation,
        .observed,
    ]

    static func lint(_ rulebook: Rulebook) -> CitationPolicyReport {
        var report = CitationPolicyReport()

        for rule in rulebook.rules {
            let references: [RuleReference]
            switch rule {
            case .precheck(let precheck):
                references = precheck.references
                if references.isEmpty {
                    report.errors.append("\(precheck.id): precheck rules require a reference")
                }
            case .noise(let noise):
                references = noise.references
            case .prompt(let prompt):
                references = prompt.references
                if references.isEmpty {
                    report.warnings.append("\(prompt.id): prompt rule has no references")
                }
            case .validator(let validator):
                references = validator.references
                if references.isEmpty {
                    report.warnings.append("\(validator.id): validator rule has no references")
                }
            }

            for reference in references {
                if !knownKinds.contains(reference.type) {
                    report.errors.append(
                        "\(rule.id): unknown reference type \(reference.type.rawValue)"
                    )
                }

                let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if reference.type == .observed {
                    if title.isEmpty {
                        report.errors.append("\(rule.id): observed reference requires a meaningful title")
                    }
                } else if reference.url == nil {
                    report.errors.append(
                        "\(rule.id): \(reference.type.rawValue) reference requires a URL"
                    )
                }

                if reference.url?.contains("TODO") == true {
                    report.errors.append("\(rule.id): reference URL is a placeholder")
                }
            }
        }

        return report
    }
}

private func policyRulebook(_ rules: [Rule]) -> Rulebook {
    Rulebook(version: "test", minAppVersion: "test", rules: rules)
}

private func policyNoise(
    id: String = "noise.test",
    references: [RuleReference] = []
) -> Rule {
    .noise(NoiseRule(
        id: id,
        criteria: .always,
        linePattern: "noise",
        references: references
    ))
}

private func policyPrecheck(references: [RuleReference]) -> Rule {
    .precheck(PrecheckRule(
        id: "precheck.test",
        criteria: .always,
        emitsFact: "fact",
        references: references
    ))
}

@Test func citationPolicyAcceptsEveryKnownReferenceType() {
    let kinds: [RuleReference.Kind] = [
        .runtimeSource, .runtimeBehavior, .issue, .releaseNote, .documentation,
    ]
    var references = kinds.map {
        RuleReference(type: $0, title: "Supported claim", url: "https://example.com/source")
    }
    references.append(RuleReference(type: .observed, title: "Observed during testing"))

    let report = CitationPolicy.lint(policyRulebook([policyPrecheck(references: references)]))
    #expect(report.errors.isEmpty)
    #expect(report.warnings.isEmpty)
}

@Test func citationPolicyRejectsUnknownReferenceType() {
    let reference = RuleReference(
        type: .init(rawValue: "security-advisory"),
        title: "Future source",
        url: "https://example.com/source"
    )

    let report = CitationPolicy.lint(policyRulebook([policyNoise(references: [reference])]))
    #expect(report.errors.contains { $0.contains("unknown reference type security-advisory") })
}

@Test func citationPolicyRequiresPrecheckReference() {
    let report = CitationPolicy.lint(policyRulebook([policyPrecheck(references: [])]))
    #expect(report.errors.contains { $0.contains("precheck rules require a reference") })
}

@Test func citationPolicyRequiresMeaningfulObservedTitle() {
    let reference = RuleReference(type: .observed, title: " \n\t ")
    let report = CitationPolicy.lint(policyRulebook([policyNoise(references: [reference])]))
    #expect(report.errors.contains { $0.contains("meaningful title") })
}

@Test func citationPolicyRequiresURLForNonObservedReference() {
    let reference = RuleReference(type: .documentation, title: "Documented behavior")
    let report = CitationPolicy.lint(policyRulebook([policyNoise(references: [reference])]))
    #expect(report.errors.contains { $0.contains("requires a URL") })
}

@Test func citationPolicyRejectsPlaceholderURL() {
    let reference = RuleReference(
        type: .documentation,
        title: "Documented behavior",
        url: "TODO(maintainer-url)"
    )
    let report = CitationPolicy.lint(policyRulebook([policyNoise(references: [reference])]))
    #expect(report.errors.contains { $0.contains("placeholder") })
}

@Test func citationPolicyWarnsForUncitedPromptAndValidator() {
    let prompt = Rule.prompt(PromptRule(id: "prompt.test", criteria: .always, text: "text"))
    let validator = Rule.validator(ValidatorRule(
        id: "validator.test",
        criteria: .always,
        category: "crash",
        requiredEvidence: ["evidence"]
    ))

    let report = CitationPolicy.lint(policyRulebook([prompt, validator]))
    #expect(report.errors.isEmpty)
    #expect(report.warnings.count == 2)
}

@Test func citationPolicyExemptsUnreferencedNoiseRule() {
    let report = CitationPolicy.lint(policyRulebook([policyNoise()]))
    #expect(report.errors.isEmpty)
    #expect(report.warnings.isEmpty)
}

@Test func citationPolicyChecksRuntimeVersionedNoiseReference() {
    let reference = RuleReference(
        type: .runtimeBehavior,
        title: "Version-specific behavior",
        runtimeVersions: ["1.0.0"]
    )

    let report = CitationPolicy.lint(policyRulebook([policyNoise(references: [reference])]))
    #expect(report.errors.contains { $0.contains("requires a URL") })
}

@Test func seedRulebookPassesCitationPolicy() throws {
    let report = CitationPolicy.lint(try RulebookLoader.loadSeed())
    #expect(report.warnings.isEmpty)
    #expect(report.errors.isEmpty)
}
