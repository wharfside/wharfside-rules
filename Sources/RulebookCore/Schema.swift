import Foundation

// MARK: - Rulebook document

/// A versioned, signed collection of diagnosis rules.
/// The document is pure data: nothing in it is executed, and prompt text
/// reaches the model only through fixed templates (see `PromptRule`).
public struct Rulebook: Sendable, Equatable {
    /// Bumped only on breaking schema changes. Loaders reject documents
    /// with a schema version greater than they understand.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// Semver of the rulebook content, e.g. "0.1.0".
    public let version: String
    /// Minimum app version this rulebook is valid for (semver).
    public let minAppVersion: String
    public let rules: [Rule]
    /// Rule kinds present in the document that this build doesn't understand.
    /// Preserved so callers can surface "N rules skipped (update Wharfside)".
    public let skippedUnknownKinds: [String]

    public init(
        schemaVersion: Int = Rulebook.currentSchemaVersion,
        version: String,
        minAppVersion: String,
        rules: [Rule],
        skippedUnknownKinds: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.minAppVersion = minAppVersion
        self.rules = rules
        self.skippedUnknownKinds = skippedUnknownKinds
    }
}

// MARK: - Rules

public enum Rule: Sendable, Equatable {
    case precheck(PrecheckRule)
    case noise(NoiseRule)
    case prompt(PromptRule)
    case validator(ValidatorRule)

    public var id: String {
        switch self {
        case .precheck(let r): r.id
        case .noise(let r): r.id
        case .prompt(let r): r.id
        case .validator(let r): r.id
        }
    }

    public var criteria: MatchCriteria {
        switch self {
        case .precheck(let r): r.criteria
        case .noise(let r): r.criteria
        case .prompt(let r): r.criteria
        case .validator(let r): r.criteria
        }
    }
}

/// Deterministic pre-model check: when criteria match, the engine emits a
/// hard fact into the digest and optionally suppresses diagnosis categories.
public struct PrecheckRule: Sendable, Equatable, Codable {
    public let id: String
    public let criteria: MatchCriteria
    /// Fact line emitted into the digest, e.g.
    /// "TERMINATION: SIGTERM escalated to SIGKILL within stop grace period".
    /// Plain text authored in the rulebook; never interpolated with log content.
    public let emitsFact: String
    /// Categories the validator must reject if the model still picks them,
    /// e.g. ["outOfMemory"] for a detected stop escalation.
    public let suppressesCategories: [String]

    public init(id: String, criteria: MatchCriteria, emitsFact: String,
                suppressesCategories: [String] = []) {
        self.id = id
        self.criteria = criteria
        self.emitsFact = emitsFact
        self.suppressesCategories = suppressesCategories
    }
}

/// Marks log lines as known noise: demoted before clustering and barred
/// from LAST_LINES so they can't masquerade as a cause.
public struct NoiseRule: Sendable, Equatable, Codable {
    public let id: String
    public let criteria: MatchCriteria
    /// Regex applied per log line (anchored search, not full match).
    public let linePattern: String

    public init(id: String, criteria: MatchCriteria, linePattern: String) {
        self.id = id
        self.criteria = criteria
        self.linePattern = linePattern
    }
}

/// Instruction snippet injected into the rendered prompt when criteria match
/// and the token budget allows. Text is static rulebook content — the
/// renderer must never substitute log-derived strings into it.
public struct PromptRule: Sendable, Equatable, Codable {
    public let id: String
    public let criteria: MatchCriteria
    public let text: String
    /// Lower value = higher priority. Ties broken by id (stable ordering).
    public let priority: Int

    public init(id: String, criteria: MatchCriteria, text: String, priority: Int = 100) {
        self.id = id
        self.criteria = criteria
        self.text = text
        self.priority = priority
    }
}

/// Evidence requirement for a diagnosis category: if the model outputs
/// `category` but none of `requiredEvidence` patterns matched the logs,
/// the validator rejects the diagnosis.
public struct ValidatorRule: Sendable, Equatable, Codable {
    public let id: String
    public let criteria: MatchCriteria
    public let category: String
    /// Regexes; at least one must have matched somewhere in the log window.
    public let requiredEvidence: [String]

    public init(id: String, criteria: MatchCriteria, category: String,
                requiredEvidence: [String]) {
        self.id = id
        self.criteria = criteria
        self.category = category
        self.requiredEvidence = requiredEvidence
    }
}

// MARK: - Matching

/// Conjunctive criteria (all specified fields must match; nil = don't care).
public struct MatchCriteria: Sendable, Equatable, Codable {
    /// Prefix match on the image reference, e.g. "docker.io/library/postgres".
    public let imagePrefix: String?
    public let exitCodes: [Int]?
    /// Digest source kinds, e.g. ["bootLogOnly", "stdio"].
    public let sources: [String]?
    /// Regexes; each must match at least one line in the log window.
    public let logPatterns: [String]?

    public static let always = MatchCriteria()

    public init(imagePrefix: String? = nil, exitCodes: [Int]? = nil,
                sources: [String]? = nil, logPatterns: [String]? = nil) {
        self.imagePrefix = imagePrefix
        self.exitCodes = exitCodes
        self.sources = sources
        self.logPatterns = logPatterns
    }
}

/// What the engine matches against — a deliberately small projection of
/// Wharfside's ContainerContext so the package stays app-agnostic.
public struct MatchContext: Sendable {
    public let image: String
    public let exitCode: Int?
    public let source: String
    public let logLines: [String]

    public init(image: String, exitCode: Int?, source: String, logLines: [String]) {
        self.image = image
        self.exitCode = exitCode
        self.source = source
        self.logLines = logLines
    }
}
