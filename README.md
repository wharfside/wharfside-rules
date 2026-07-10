# wharfside-rules

Deterministic rule engine for AI-assisted container diagnosis, built for
[Wharfside](https://wharfside.app) and Apple's FoundationModels framework —
but app-agnostic by design.

## What it does

On-device language models are small. The way to make their diagnoses reliable
is not to ask them to reason harder — it's to do the deterministic work
*before* the model is invoked, and to verify its claims *after*. This package
implements that sandwich as data-driven rules:

| Rule kind   | Runs      | Effect                                                        |
| ----------- | --------- | ------------------------------------------------------------- |
| `precheck`  | pre-model | Emits hard facts into the digest; suppresses categories        |
| `noise`     | pre-model | Demotes known-noise log lines so they can't masquerade as causes |
| `prompt`    | at render | Injects task-specific instruction snippets within a token budget |
| `validator` | post-model | Requires evidence for a category before a diagnosis is accepted |

Rules live in a versioned, signed JSON **rulebook** — data, not code — so
knowledge learned from one misdiagnosis can ship to every installation
without an app release.

## Design principles

- **Deterministic selection.** The host app decides which rules apply, using
  exact matching on image, exit code, source, and log patterns. The model is
  never asked to decide which knowledge it needs.
- **Pure functions, value types.** `RuleEngine.evaluate` is referentially
  transparent: same rulebook + same context → identical result. No actors,
  no shared state, `Sendable` throughout.
- **Fail closed.** Malformed regexes match nothing. Unknown rule kinds are
  skipped, not fatal (forward compatibility). Unverified downloads are
  rejected in favor of the bundled rulebook.
- **Untrusted-input posture.** Prompt-rule text reaches model instructions,
  which makes a hostile rulebook a prompt-injection vector. Downloaded
  rulebooks therefore require a valid Ed25519 signature against a key pinned
  in the host app. Rule text is static authored content — never interpolated
  with log-derived strings.

## Usage

```swift
import RulebookCore

let rulebook = try RulebookLoader.loadBundled(bundledData)

let context = MatchContext(
    image: "docker.io/library/alpine:latest",
    exitCode: 137,
    source: "bootLogOnly",
    logLines: lines
)

let eval = RuleEngine.evaluate(rulebook, context: context)
// eval.facts                → append to digest
// eval.noisePatterns        → demote before clustering
// eval.suppressedCategories → hand to validator
// eval.promptRules          → RuleEngine.selectPromptRules(_:tokenBudget:)
// eval.evidenceRequirements → validator evidence checks
```

For downloaded rulebooks:

```swift
let rulebook = try RulebookLoader.loadVerified(
    document: data, signature: sig, publicKey: pinnedKey)
```

## Platforms

`RulebookCore` depends only on Foundation and
[swift-crypto](https://github.com/apple/swift-crypto), so it builds and tests
on macOS 15+ and Linux. FoundationModels integration lives in the host app
(or a future `RulebookFoundationModels` target), keeping this core testable
in plain CI runners.

## Status

Pre-1.0. Schema version 1. Expect the schema to evolve while the seed
rulebook is being written; semver discipline begins at `1.0.0`.
