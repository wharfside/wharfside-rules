import Foundation

/// The result of evaluating a rulebook against one container's context.
/// Everything downstream (digest builder, prompt renderer, validator)
/// consumes this — the engine itself never touches the model.
public struct RuleEvaluation: Sendable, Equatable {
    /// Facts to append verbatim to the digest (from matched prechecks).
    public let facts: [String]
    /// Categories the validator must reject (union of matched prechecks).
    public let suppressedCategories: Set<String>
    /// Regexes identifying noise lines (from matched noise rules).
    public let noisePatterns: [String]
    /// Prompt rules that matched, sorted by (priority, id) — stable order.
    public let promptRules: [PromptRule]
    /// Validator evidence requirements that matched, keyed by category.
    public let evidenceRequirements: [String: [ValidatorRule]]
    /// IDs of every rule that matched (for report transparency).
    public let matchedRuleIDs: [String]
}

public enum RuleEngine {

    /// Evaluate all rules against a context. Pure and deterministic:
    /// same rulebook + same context → identical result.
    public static func evaluate(_ rulebook: Rulebook, context: MatchContext) -> RuleEvaluation {
        var facts: [String] = []
        var suppressed: Set<String> = []
        var noise: [String] = []
        var prompts: [PromptRule] = []
        var evidence: [String: [ValidatorRule]] = [:]
        var matched: [String] = []

        for rule in rulebook.rules {
            guard matches(rule.criteria, context: context) else { continue }
            matched.append(rule.id)
            switch rule {
            case .precheck(let r):
                facts.append(r.emitsFact)
                suppressed.formUnion(r.suppressesCategories)
            case .noise(let r):
                noise.append(r.linePattern)
            case .prompt(let r):
                prompts.append(r)
            case .validator(let r):
                evidence[r.category, default: []].append(r)
            }
        }

        prompts.sort { ($0.priority, $0.id) < ($1.priority, $1.id) }

        return RuleEvaluation(
            facts: facts,
            suppressedCategories: suppressed,
            noisePatterns: noise,
            promptRules: prompts,
            evidenceRequirements: evidence,
            matchedRuleIDs: matched
        )
    }

    /// Greedy budget fill in priority order: a rule that doesn't fit is
    /// skipped, but lower-priority rules that do fit are still admitted.
    /// Token estimate is chars/4 — crude, but only a safety margin;
    /// callers should budget conservatively.
    public static func selectPromptRules(
        _ rules: [PromptRule], tokenBudget: Int
    ) -> [PromptRule] {
        var remaining = tokenBudget
        var selected: [PromptRule] = []
        for rule in rules {
            let cost = estimatedTokens(rule.text)
            if cost <= remaining {
                selected.append(rule)
                remaining -= cost
            }
        }
        return selected
    }

    public static func estimatedTokens(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }

    // MARK: - Matching

    static func matches(_ criteria: MatchCriteria, context: MatchContext) -> Bool {
        if let prefix = criteria.imagePrefix, !context.image.hasPrefix(prefix) {
            return false
        }
        if let codes = criteria.exitCodes {
            guard let exit = context.exitCode, codes.contains(exit) else { return false }
        }
        if let sources = criteria.sources, !sources.contains(context.source) {
            return false
        }
        if let patterns = criteria.logPatterns {
            for pattern in patterns {
                guard anyLineMatches(pattern, lines: context.logLines) else { return false }
            }
        }
        return true
    }

    static func anyLineMatches(_ pattern: String, lines: [String]) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            // A malformed regex in a rulebook must fail closed (no match),
            // never crash the pipeline. Release CI on the rules repo should
            // catch these before they ship.
            return false
        }
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, range: range) != nil { return true }
        }
        return false
    }
}
