import Foundation

// MARK: - Wire format
//
// Rules are encoded as { "kind": "...", ...payload }. Decoding an unknown
// kind must not fail the whole document: old app versions skip rules they
// don't understand and record the kind in `skippedUnknownKinds`.

extension Rulebook: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, version, minAppVersion, rules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion <= Rulebook.currentSchemaVersion else {
            throw RulebookError.unsupportedSchemaVersion(schemaVersion)
        }

        var rulesContainer = try c.nestedUnkeyedContainer(forKey: .rules)
        var rules: [Rule] = []
        var skipped: [String] = []
        while !rulesContainer.isAtEnd {
            let wire = try rulesContainer.decode(WireRule.self)
            if let rule = wire.rule {
                rules.append(rule)
            } else {
                skipped.append(wire.kind)
            }
        }

        self.init(
            schemaVersion: schemaVersion,
            version: try c.decode(String.self, forKey: .version),
            minAppVersion: try c.decode(String.self, forKey: .minAppVersion),
            rules: rules,
            skippedUnknownKinds: skipped
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(version, forKey: .version)
        try c.encode(minAppVersion, forKey: .minAppVersion)
        try c.encode(rules.map(WireRule.init), forKey: .rules)
    }
}

public enum RulebookError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidSignature
    case malformedDocument
}

/// Intermediate representation that tolerates unknown kinds.
private struct WireRule: Codable {
    let kind: String
    let rule: Rule?

    init(_ rule: Rule) {
        self.rule = rule
        self.kind = switch rule {
        case .precheck: "precheck"
        case .noise: "noise"
        case .prompt: "prompt"
        case .validator: "validator"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try c.decode(String.self, forKey: .kind)
        self.rule = switch kind {
        case "precheck": .precheck(try PrecheckRule(from: decoder))
        case "noise": .noise(try NoiseRule(from: decoder))
        case "prompt": .prompt(try PromptRule(from: decoder))
        case "validator": .validator(try ValidatorRule(from: decoder))
        default: nil  // forward compatibility: skip, don't fail
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch rule {
        case .precheck(let r): try r.encode(to: encoder)
        case .noise(let r): try r.encode(to: encoder)
        case .prompt(let r): try r.encode(to: encoder)
        case .validator(let r): try r.encode(to: encoder)
        case nil: throw RulebookError.malformedDocument
        }
    }
}