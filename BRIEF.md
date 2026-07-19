# B8-Codex v2 — Rule `references` Field (Build Week)

**Change from v1:** decoder posture corrected to match the package's existing
forward-compatibility principle ("unknown rule kinds are skipped, not fatal").
Unknown reference types are now TOLERATED at decode time and REJECTED at lint
time. Strictness at publication, tolerance at consumption.

**Agent:** OpenAI Codex · **Repo:** `wharfside/wharfside-rules` (public)
**Branch:** `feature/b8-rule-references` · **Timebox:** 1 session + review

---

## Context (self-contained)

`RulebookCore` is a pure Swift package: a deterministic rule engine for
AI-assisted container crash diagnosis. Facts you must respect:

1. Rules ship in a versioned, signed JSON rulebook. Downloaded rulebooks
   require Ed25519 verification BEFORE decoding (`RulebookLoader.loadVerified`);
   the bundled rulebook loads via `RulebookLoader.loadBundled`. Changing
   bundled rule content changes the signed payload → re-signing is required
   (maintainer-only; see Handoffs).
2. Rule kinds: `precheck`, `noise`, `prompt`, `validator`. Evaluation
   (`RuleEngine.evaluate`) is a pure function: value types, `Sendable`
   throughout, no actors.
3. **Forward compatibility is a stated design principle:** unknown rule kinds
   are skipped, not fatal. Malformed regexes match nothing. Your changes must
   follow the same philosophy.
4. Platforms: macOS 15+ and Linux. Dependencies: Foundation + swift-crypto
   only. Do not add dependencies. `swift build && swift test` must pass on
   both platforms; treat warnings as errors.
5. Layout: `Sources/RulebookCore`, `Tests/RulebookCoreTests`. Orientation
   step: locate the rule model type, the rulebook container, the bundled
   rulebook JSON, loader code, and test conventions. Report actual names
   before editing; substitute them for placeholders below.

## Goal

Optional structured `references` (provenance/citations) on every rule; CI
lint enforcing citation policy; backfill of bundled rules. References are
inert metadata — zero effect on evaluation.

## Specification

### 1. `RuleReference`

```swift
public struct RuleReference: Codable, Sendable, Equatable {
    public struct Kind: RawRepresentable, Codable, Sendable, Equatable {
        public let rawValue: String
        // Known values as static constants:
        public static let runtimeSource   = Kind(rawValue: "runtime-source")
        public static let runtimeBehavior = Kind(rawValue: "runtime-behavior")
        public static let issue           = Kind(rawValue: "issue")
        public static let releaseNote     = Kind(rawValue: "release-note")
        public static let documentation   = Kind(rawValue: "documentation")
        public static let observed        = Kind(rawValue: "observed")
    }
    public let type: Kind
    public let title: String              // one-line claim supported
    public let url: String?               // plain String (Linux Codable simplicity)
    public let runtimeVersions: [String]? // container versions claim holds for
}
```

- `Kind` is a RawRepresentable string wrapper, NOT a closed enum: an unknown
  type value ("security-advisory" from a future schema) decodes and is
  preserved verbatim. **Do not use a closed `enum` here — that was v1's
  error; it would make older apps reject newer rulebooks over metadata.**
  (If the codebase already has an idiomatic pattern for open string-backed
  values, mirror it instead.)
- Structurally malformed references (wrong JSON shape, missing `type` or
  `title`) still fail decode normally.

### 2. Rule model

- `references: [RuleReference]` on the rule model, decoding to `[]` when the
  key is absent, so existing signed rulebooks remain loadable byte-for-byte.
- References must not appear in any evaluation/selection code path.

### 3. Citation lint — where ALL strictness lives

Test target (or existing CI-check pattern if one exists) named
`CitationPolicyTests`, run by `swift test`, evaluating the BUNDLED rulebook:

- FAIL if any reference `type` is outside the six known kinds (unknown types
  are a lint error at authoring time, though tolerated by the decoder).
- FAIL if any `precheck` rule has zero references.
- FAIL if an `observed` reference lacks a meaningful `title`.
- FAIL if a non-`observed` reference lacks a `url`.
- FAIL on placeholder URLs (any url containing `TODO`) — real citations only.
- WARN (report, don't fail) if a `prompt`/`validator` rule has no references.
- `noise` rules: exempt unless they declare `runtimeVersions`.

### 4. Backfill bundled rules

- Orderly-stop precheck rule: (a) SIGTERM→timeout→SIGKILL stop sequence
  (`runtime-behavior` or `documentation`); (b) `containerWait` exit-status
  available only during the stopping window (`runtime-behavior`,
  `runtimeVersions: ["1.0.0"]`).
- vminitd boot-noise rule (`vminitd memory threshold exceeded` fires on every
  VM boot regardless of outcome): `observed`, title stating the observation
  and exit-outcome independence.
- Remaining bundled rules: cite where the maintainer supplies sources; leave
  uncited only where policy permits the kind. Lint must pass clean at merge
  (except deliberate TODO placeholders — see next line).
- URLs: insert `TODO(maintainer-url)` placeholders; NEVER fabricate URLs.
  Placeholders fail the lint by design; list every one in the PR description.

### 5. Re-signing handoff

Backfill changes the signed payload. Do NOT attempt to sign. End state:
updated rulebook JSON staged; legacy-compatibility test green (a fixture copy
of the pre-change rulebook still decodes and verifies); one-command re-sign
step documented for the maintainer.

## Tests (macOS + Linux)

1. Decode: full round-trip; absent key → `[]`; **unknown reference type
   decodes and preserves raw value**; malformed reference shape fails.
2. Lint: positive + negative case per policy branch above, including the
   unknown-type-fails-lint case.
3. Behavioral invariance: entire existing suite passes untouched. Any change
   to existing golden/expected outputs = STOP, brief violated.
4. Legacy fixture rulebook (pre-references copy) decodes and verifies.

## Commit plan

1. `Add RuleReference type preserving unknown reference kinds`
2. `Decode references field defaulting to empty for legacy rulebooks`
3. `Add citation policy lint strict at authoring time`
4. `Backfill references on bundled rules with maintainer-URL placeholders`

Also: add a "Built with Codex" section to README.md describing this feature's
implementation (Devpost requirement) — include in commit 4 or a fifth commit.

## Handoffs to maintainer (list in PR description)

- Real URLs for every `TODO(maintainer-url)`
- Re-sign bundled rulebook (private key never enters this session)
- Confirm reported type/file names matched brief assumptions

## Out of scope

UI rendering of references; URL fetching/validation; changes outside this
repo; any modification to evaluation semantics.