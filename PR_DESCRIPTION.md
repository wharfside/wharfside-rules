## Summary

- Add structured provenance references to every rule kind (`RuleReference`:
  runtime-source / runtime-behavior / issue / release-note / documentation / observed)
- Preserve unknown reference kinds when decoding, while rejecting them in the
  authoring lint — forward compatibility at consumption, strictness at publication,
  matching the engine's existing "unknown rule kinds are skipped, not fatal" posture
- Add citation-policy lint (`CitationPolicyTests`), enforced by `swift test`:
  prechecks must cite ≥1 source; observed references require a reproduction-context
  title; non-observed references require a URL; placeholder URLs fail by design
- Add the seed rulebook as a package resource (`Sources/RulebookCore/Resources/
  Rulebook.json`) — production 0.1.0 rules, bodies unchanged, references added
- Add byte-exact legacy fixture (pre-references seed, SHA-256 pinned) signed with a
  fresh, clearly-labeled TEST-ONLY Ed25519 keypair, verifying the
  verify-before-decode path end-to-end
- Backfill citations on the bundled rules, including SHA-pinned permalinks into
  apple/container 1.0.0 source for the stop-escalation and containerWait
  stopping-window claims
- Remove a redundant `StrictConcurrency` swiftSetting rejected by the Swift 6.0
  Linux toolchain (found during cross-platform verification)

## Verification

- `swift build && swift test`: 28 tests, green on macOS (including
  `-Xswiftc -warnings-as-errors` variants)
- Linux: 28 tests green in `swift:6.0` — run inside apple/container:
  `container run --rm --volume "$PWD":/src --workdir /src swift:6.0 swift test`
- Behavioral invariance: `jq 'del(.rules[].references)'` on the seed reproduces the
  pre-references baseline; no changes to `RuleEngine` or any existing
  golden/regression tests (`report2ScenarioIsClassifiedAsStopNotOOM` untouched)
- Seed passes the citation lint with zero errors and zero warnings

## Built with Codex

Implemented with OpenAI Codex (GPT-5.6 Sol) from a self-contained brief
(`BRIEF.md`) across four behavior-named commits, plus a Linux-compatibility fix.
Codex session / feedback thread ID: `019f7b25-b13c-7b52-909a-179062caa8e3`.
The production signing key never entered the agent session; test fixtures use a
fresh TEST-ONLY identity generated in-session and labeled as such.

## Maintainer handoff (post-merge)

- [ ] App repo: sync vendored `RulebookCore` sources and bundled
      `Rulebook.json` to the references schema, re-sign with the production key
      (`rulebook-tool sign`), and verify the app loads `source: bundled`
- [ ] Define long-term sync direction between the three rulebook copies
      (this repo's seed ⇄ app vendored package resource ⇄ `SeedRulebook.make()`)
- [ ] Optional follow-up: lint currently allows empty titles on non-observed
      references (URL is required, title emptiness only checked for observed)

## Notes

- The private key and signature under `Tests/RulebookCoreTests/Fixtures` are
  fresh TEST-ONLY material, unrelated to and never usable as the production
  signing identity.
- `BRIEF.md` in the repo root is the agent brief this PR was executed from,
  kept as provenance.