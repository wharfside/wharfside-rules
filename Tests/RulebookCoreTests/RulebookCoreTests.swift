import Crypto
import Foundation
import Testing
@testable import RulebookCore

// MARK: - Seed rules used across tests (mirrors the planned rulebook v0.1.0)

private let stopEscalationPrecheck = Rule.precheck(PrecheckRule(
    id: "precheck.stop-escalation",
    criteria: MatchCriteria(
        exitCodes: [137],
        logPatterns: [
            #"sending signal 15 to process"#,
            #"sending signal 9 to process"#,
        ]
    ),
    emitsFact: "TERMINATION: SIGTERM escalated to SIGKILL within stop grace period (stop request, not a crash)",
    suppressesCategories: ["outOfMemory", "crash"]
))

private let vminitdNoise = Rule.noise(NoiseRule(
    id: "noise.vminitd-memory-threshold",
    criteria: .always,
    linePattern: #"vminitd memory threshold exceeded"#
))

private let oomEvidence = Rule.validator(ValidatorRule(
    id: "validator.oom-needs-kernel-evidence",
    criteria: .always,
    category: "outOfMemory",
    requiredEvidence: [#"oom-kill"#, #"Out of memory: Killed process"#, #"oom_reaper"#]
))

private let stopHintPrompt = Rule.prompt(PromptRule(
    id: "prompt.exit-137-stop-hint",
    criteria: MatchCriteria(exitCodes: [137]),
    text: "Exit code 137 preceded by SIGTERM and lacking kernel oom-kill lines indicates a requested stop that escalated to SIGKILL, not an out-of-memory kill.",
    priority: 10
))

/// The log window from the report2.md misdiagnosis (2026-07-09, container "hello").
private let report2Context = MatchContext(
    image: "docker.io/library/alpine:latest",
    exitCode: 137,
    source: "bootLogOnly",
    logLines: [
        "2026-07-09T05:54:30.774Z warning vminitd: current_bytes: 83759104, high_events_total: 55, threshold_bytes: 83886080 vminitd memory threshold exceeded",
        "2026-07-09T05:54:30.776Z info vminitd: id: hello, pid: 109 started managed process",
        "2026-07-09T05:54:47.329Z info vminitd: id: hello sending signal 15 to process 109",
        "2026-07-09T05:54:57.792Z info vminitd: id: hello sending signal 9 to process 109",
        "2026-07-09T05:54:57.794Z info vminitd: id: hello, status: 137 managed process exit",
    ]
)

private func seedRulebook() -> Rulebook {
    Rulebook(
        version: "0.1.0",
        minAppVersion: "1.0.0",
        rules: [stopEscalationPrecheck, vminitdNoise, oomEvidence, stopHintPrompt]
    )
}

// MARK: - The regression that motivated all of this

@Test func report2ScenarioIsClassifiedAsStopNotOOM() {
    let eval = RuleEngine.evaluate(seedRulebook(), context: report2Context)

    // Precheck fired: digest gets a hard termination fact...
    #expect(eval.facts.count == 1)
    #expect(eval.facts[0].contains("SIGTERM escalated to SIGKILL"))
    // ...and outOfMemory is suppressed before the model ever answers.
    #expect(eval.suppressedCategories.contains("outOfMemory"))

    // The misleading vminitd warning is flagged as noise.
    #expect(eval.noisePatterns.contains(#"vminitd memory threshold exceeded"#))

    // Even without the precheck, the validator would reject outOfMemory:
    // no kernel OOM evidence exists in this window.
    let oomRules = eval.evidenceRequirements["outOfMemory"] ?? []
    #expect(oomRules.count == 1)
    let anyEvidence = oomRules[0].requiredEvidence.contains {
        RuleEngine.anyLineMatches($0, lines: report2Context.logLines)
    }
    #expect(!anyEvidence)

    // The stop-hint prompt rule matched (exit 137).
    #expect(eval.promptRules.map(\.id) == ["prompt.exit-137-stop-hint"])
}

@Test func precheckDoesNotFireOnGenuineOOM() {
    // Same exit code, but kernel OOM evidence and no SIGTERM prelude.
    let context = MatchContext(
        image: "docker.io/library/postgres:16",
        exitCode: 137,
        source: "stdio",
        logLines: [
            "kernel: Out of memory: Killed process 109 (postgres)",
            "kernel: oom_reaper: reaped process 109",
        ]
    )
    let eval = RuleEngine.evaluate(seedRulebook(), context: context)
    #expect(eval.facts.isEmpty)  // no SIGTERM lines → precheck must not match
    #expect(!eval.suppressedCategories.contains("outOfMemory"))

    let oomRules = eval.evidenceRequirements["outOfMemory"] ?? []
    let anyEvidence = oomRules.first.map { rule in
        rule.requiredEvidence.contains {
            RuleEngine.anyLineMatches($0, lines: context.logLines)
        }
    } ?? false
    #expect(anyEvidence)  // validator would accept outOfMemory here
}

// MARK: - Coding

@Test func rulebookRoundTripsThroughJSON() throws {
    let original = seedRulebook()
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Rulebook.self, from: data)
    #expect(decoded == original)
}

@Test func unknownRuleKindsAreSkippedNotFatal() throws {
    let json = """
    {
      "schemaVersion": 1,
      "version": "0.2.0",
      "minAppVersion": "1.0.0",
      "rules": [
        { "kind": "hologram", "payload": { "future": true } },
        { "kind": "noise", "id": "n1", "criteria": {},
          "linePattern": "Bridge firewalling registered" }
      ]
    }
    """
    let book = try JSONDecoder().decode(Rulebook.self, from: Data(json.utf8))
    #expect(book.rules.count == 1)
    #expect(book.skippedUnknownKinds == ["hologram"])
}

@Test func newerSchemaVersionIsRejected() {
    let json = """
    { "schemaVersion": 99, "version": "9.0.0", "minAppVersion": "1.0.0", "rules": [] }
    """
    #expect(throws: RulebookError.unsupportedSchemaVersion(99)) {
        _ = try JSONDecoder().decode(Rulebook.self, from: Data(json.utf8))
    }
}

// MARK: - Matching & selection details

@Test func allCriteriaAreConjunctive() {
    let criteria = MatchCriteria(
        imagePrefix: "docker.io/library/alpine",
        exitCodes: [137],
        sources: ["bootLogOnly"]
    )
    #expect(RuleEngine.matches(criteria, context: report2Context))

    let wrongSource = MatchContext(
        image: report2Context.image, exitCode: 137,
        source: "stdio", logLines: report2Context.logLines
    )
    #expect(!RuleEngine.matches(criteria, context: wrongSource))
}

@Test func exitCodeCriterionFailsWhenExitCodeIsNil() {
    // report2.md's actual condition: container.exitCode was nil at diagnosis
    // time. A rule requiring exit 137 must not match on missing data.
    let criteria = MatchCriteria(exitCodes: [137])
    let noExit = MatchContext(
        image: report2Context.image, exitCode: nil,
        source: "bootLogOnly", logLines: report2Context.logLines
    )
    #expect(!RuleEngine.matches(criteria, context: noExit))
}

@Test func malformedRegexFailsClosed() {
    #expect(!RuleEngine.anyLineMatches("([unclosed", lines: ["([unclosed"]))
}

@Test func budgetSelectionIsGreedyByPriorityAndStable() {
    func rule(_ id: String, priority: Int, chars: Int) -> PromptRule {
        PromptRule(id: id, criteria: .always,
                   text: String(repeating: "a", count: chars), priority: priority)
    }
    let sorted = [
        rule("a", priority: 1, chars: 400),   // 100 tokens
        rule("b", priority: 2, chars: 400),   // 100 tokens — won't fit
        rule("c", priority: 3, chars: 80),    // 20 tokens — still admitted
    ]
    let selected = RuleEngine.selectPromptRules(sorted, tokenBudget: 130)
    #expect(selected.map(\.id) == ["a", "c"])
}

// MARK: - Verification

@Test func signatureVerificationAcceptsValidRejectsTampered() throws {
    let key = Curve25519.Signing.PrivateKey()
    let document = try JSONEncoder().encode(seedRulebook())
    let signature = try key.signature(for: document)

    let loaded = try RulebookLoader.loadVerified(
        document: document, signature: signature, publicKey: key.publicKey)
    #expect(loaded.version == "0.1.0")

    var tampered = document
    tampered.append(contentsOf: [0x20])
    #expect(throws: RulebookError.invalidSignature) {
        _ = try RulebookLoader.loadVerified(
            document: tampered, signature: signature, publicKey: key.publicKey)
    }
}

@Test func minAppVersionGating() {
    #expect(RulebookLoader.appVersion("1.2.0", satisfies: "1.0.0"))
    #expect(RulebookLoader.appVersion("1.0.0", satisfies: "1.0.0"))
    #expect(!RulebookLoader.appVersion("0.9.9", satisfies: "1.0.0"))
    #expect(RulebookLoader.appVersion("1.10.0", satisfies: "1.9.0"))  // numeric, not lexical
}
