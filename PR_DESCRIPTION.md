## Summary

- add structured provenance references to every rule kind
- preserve unknown reference kinds when decoding, while rejecting them in the authoring lint
- lint the repository's seed rulebook and preserve a verified pre-references fixture
- backfill the production 0.1.0 rules without changing rule bodies

## Maintainer handoff

- Replace `TODO(maintainer-url)` for “The runtime stop sequence sends SIGTERM, waits for the stop timeout, then sends SIGKILL” with a real citation.
- Replace `TODO(maintainer-url)` for “containerWait exit status is available only during the stopping window” with a real citation.
- Sync the app's bundled rulebook to the new schema and re-sign with the production key.
- Confirm the reported types and files matched the brief assumptions: `Rule`, its four payload structs, `Rulebook`, `WireRule`, `RulebookLoader`, `Sources/RulebookCore/Resources/Rulebook.json`, and Swift Testing files under `Tests/RulebookCoreTests`.

After syncing the JSON into the app repository, the maintainer can produce the
required `keyId` + `signature` JSON envelope with the app repo's existing tool:

```sh
swift run rulebook-tool sign --key <private.b64> --document Rulebook.json --out Rulebook.json.sig
```

The private key and signature committed under `Tests/RulebookCoreTests/Fixtures`
are fresh test-only material. They are unrelated to, and must never be used as,
the production signing identity.

## Verification

- `swift build`
- `swift test`
