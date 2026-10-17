import Foundation

struct CoverageAssessment {
    let status: CueStatus
    let matchedTerms: [String]
    let requiredTerms: [String]
    let numericRequirementMet: Bool
    let isLimited: Bool

    static let empty = CoverageAssessment(status: .open, matchedTerms: [], requiredTerms: [], numericRequirementMet: true, isLimited: true)
}

protocol CoverageProvider {
    var displayName: String { get }
    func assess(cue: Cue, transcript: String, currentStatus: CueStatus) -> CoverageAssessment
}

struct LocalCoverageProvider: CoverageProvider {
    let displayName = "Limited matching"
    let sensitivity: String

    init(sensitivity: String = "Balanced") {
        self.sensitivity = sensitivity
    }

    func assess(cue: Cue, transcript: String, currentStatus: CueStatus) -> CoverageAssessment {
        CoverageEngine.assess(cue: cue, transcript: transcript, currentStatus: currentStatus, sensitivity: sensitivity)
    }
}

struct CoverageLabFixture: Identifiable, Hashable {
    let id: String
    let title: String
    let cue: Cue
    let transcript: String
    let expectedCovered: Bool
}

struct CoverageLabResult: Identifiable, Hashable {
    let id: String
    let fixture: CoverageLabFixture
    let actualStatus: CueStatus
    let matchedTerms: [String]

    var isCorrect: Bool { (actualStatus == .covered) == fixture.expectedCovered }
    var isFalseCompletion: Bool { actualStatus == .covered && !fixture.expectedCovered }
}

struct CoverageLabSummary: Hashable {
    let sensitivity: String
    let results: [CoverageLabResult]

    var truePositives: Int { results.filter { $0.fixture.expectedCovered && $0.actualStatus == .covered }.count }
    var falsePositives: Int { results.filter(\.isFalseCompletion).count }
    var falseNegatives: Int { results.filter { $0.fixture.expectedCovered && $0.actualStatus != .covered }.count }
    var trueNegatives: Int { results.filter { !$0.fixture.expectedCovered && $0.actualStatus == .open }.count }
    var precision: Double {
        let denominator = truePositives + falsePositives
        return denominator == 0 ? 0 : Double(truePositives) / Double(denominator)
    }
    var recall: Double {
        let denominator = truePositives + falseNegatives
        return denominator == 0 ? 0 : Double(truePositives) / Double(denominator)
    }
    var falseCompletionRate: Double {
        let denominator = falsePositives + trueNegatives
        return denominator == 0 ? 0 : Double(falsePositives) / Double(denominator)
    }
}

struct CoverageReplayResult: Identifiable, Hashable {
    let id: UUID
    let cue: Cue
    let originalStatus: CueStatus
    let replayStatus: CueStatus
    let matchedTerms: [String]
}

func coverageLabFixtures() -> [CoverageLabFixture] {
    [
        CoverageLabFixture(
            id: "clear-migration",
            title: "Clear migration timeline",
            cue: Cue(title: "Migration timeline", detail: "Describe the three phases over six weeks.", keywords: ["phases", "weeks"]),
            transcript: "The migration timeline has three phases and will take six weeks.",
            expectedCovered: true
        ),
        CoverageLabFixture(
            id: "mention-only",
            title: "Topic named without substance",
            cue: Cue(title: "Migration timeline", detail: "Describe the three phases over six weeks.", keywords: ["phases", "weeks"], coverageMode: .strict),
            transcript: "I want to mention the migration timeline.",
            expectedCovered: false
        ),
        CoverageLabFixture(
            id: "future-promise",
            title: "Promise to discuss later",
            cue: Cue(title: "Approval ask", detail: "Ask for approval to pilot.", keywords: ["pilot"], coverageMode: .strict),
            transcript: "I will discuss the approval ask and pilot later.",
            expectedCovered: false
        ),
        CoverageLabFixture(
            id: "negated-requirement",
            title: "Negated security claim",
            cue: Cue(title: "Encryption at rest", coverageMode: .strict),
            transcript: "We do not use encryption at rest in this prototype.",
            expectedCovered: false
        ),
        CoverageLabFixture(
            id: "correct-number",
            title: "Correct numeric fact",
            cue: Cue(title: "Expected savings: 20–30%", coverageMode: .strict),
            transcript: "Expected savings are 20 to 30 percent.",
            expectedCovered: true
        ),
        CoverageLabFixture(
            id: "wrong-number",
            title: "Incorrect numeric fact",
            cue: Cue(title: "Expected savings: 20–30%", coverageMode: .strict),
            transcript: "Expected savings are ten to fifteen percent.",
            expectedCovered: false
        ),
        CoverageLabFixture(
            id: "keyword-support",
            title: "Keyword-supported cue",
            cue: Cue(title: "Architecture", detail: "Explain the system flow.", keywords: ["GraphQL"], coverageMode: .mentionOnly),
            transcript: "The GraphQL layer handles the system flow.",
            expectedCovered: true
        ),
        CoverageLabFixture(
            id: "unrelated-speech",
            title: "Unrelated speech",
            cue: Cue(title: "Customer approval", coverageMode: .strict),
            transcript: "The team finished the internal testing and documentation.",
            expectedCovered: false
        )
    ]
}

func coverageLabSummary(sensitivity: String) -> CoverageLabSummary {
    let provider = LocalCoverageProvider(sensitivity: sensitivity)
    let results = coverageLabFixtures().map { fixture in
        let assessment = provider.assess(cue: fixture.cue, transcript: fixture.transcript, currentStatus: .open)
        return CoverageLabResult(id: fixture.id, fixture: fixture, actualStatus: assessment.status, matchedTerms: assessment.matchedTerms)
    }
    return CoverageLabSummary(sensitivity: sensitivity, results: results)
}

func coverageReplayResults(presentation: Presentation, run: SessionRun, sensitivity: String) -> [CoverageReplayResult] {
    guard let transcript = run.transcript, !transcript.isEmpty else { return [] }
    let provider = LocalCoverageProvider(sensitivity: sensitivity)
    return presentation.leafCues.enumerated().map { index, cue in
        let originalStatus = run.results.first(where: { $0.cueID == cue.id })?.status ?? .open
        let assessment = provider.assess(cue: cue, transcript: transcript, currentStatus: .open)
        return CoverageReplayResult(id: cue.id, cue: cue, originalStatus: originalStatus, replayStatus: assessment.status, matchedTerms: assessment.matchedTerms)
    }
}

enum CoverageEngine {
    private static let stopWords: Set<String> = [
        "a", "about", "after", "all", "an", "and", "are", "as", "at", "be", "before", "by", "can", "do", "for", "from", "give", "how", "in", "into", "is", "it", "must", "of", "on", "or", "that", "the", "their", "then", "this", "to", "what", "when", "with", "you"
    ]

    private static let promisePhrases = [
        "will discuss", "discuss later", "cover later", "come back to", "return to", "get to that", "address that later"
    ]

    private static let negationWords: Set<String> = ["not", "never", "no", "didnt", "didn't", "doesnt", "doesn't", "without"]
    private static let spokenNumbers: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "hundred": 100, "thousand": 1_000, "million": 1_000_000
    ]

    static func assess(cue: Cue, transcript: String, currentStatus: CueStatus, sensitivity: String = "Balanced") -> CoverageAssessment {
        guard !transcript.isEmpty else { return .empty }
        if currentStatus == .covered || currentStatus == .manual {
            return CoverageAssessment(status: currentStatus, matchedTerms: [], requiredTerms: [], numericRequirementMet: true, isLimited: true)
        }

        let cueText = "\(cue.title) \(cue.detail) \(cue.keywords.joined(separator: " "))"
        let requiredTerms = terms(in: cueText)
        let transcriptTokens = tokens(in: transcript)
        let matchedTerms = requiredTerms.filter { term in
            transcriptTokens.contains { equivalent($0, term) }
        }
        let expectedNumbers = numberValues(in: cueText)
        let observedNumbers = numberValues(in: transcript)
        let numericRequirementMet = expectedNumbers.isEmpty || expectedNumbers.allSatisfy { expected in
            observedNumbers.contains { abs($0 - expected) <= max(1, expected * 0.02) }
        }
        let hasPromise = promisePhrases.contains { transcript.lowercased().contains($0) }
        let hasNegatedMatch = matchedTerms.contains { term in
            containsNegationNear(term: term, transcriptTokens: transcriptTokens)
        }
        let threshold: Int
        switch cue.coverageMode {
        case .balanced:
            threshold = max(1, Int(ceil(Double(requiredTerms.count) * adjustedRatio(0.45, sensitivity: sensitivity))))
        case .strict:
            threshold = max(1, Int(ceil(Double(requiredTerms.count) * adjustedRatio(0.7, sensitivity: sensitivity))))
        case .mentionOnly:
            threshold = 1
        }
        let enoughEvidence = matchedTerms.count >= threshold

        let status: CueStatus
        if enoughEvidence && numericRequirementMet && !hasPromise && !hasNegatedMatch {
            status = .covered
        } else if !matchedTerms.isEmpty {
            status = .emerging
        } else {
            status = .open
        }

        return CoverageAssessment(
            status: status,
            matchedTerms: matchedTerms,
            requiredTerms: requiredTerms,
            numericRequirementMet: numericRequirementMet,
            isLimited: true
        )
    }

    static func evidenceSnippet(transcript: String, matchingTerms: [String], maxLength: Int = 180) -> String? {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty, !matchingTerms.isEmpty, maxLength > 0 else { return nil }

        let candidates = trimmedTranscript.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let match = candidates.first(where: { sentence in
            let sentenceTokens = tokens(in: sentence)
            return matchingTerms.contains { term in
                sentenceTokens.contains { equivalent($0, term) }
            }
        }) else {
            return nil
        }

        let clipped = String(match.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped.isEmpty ? nil : (match.count > maxLength ? "(clipped)…" : clipped)
    }

    private static func terms(in text: String) -> [String] {
        var result: [String] = []
        for token in tokens(in: text) where (token.count > 3 || token.contains(where: { $0.isNumber })) && !stopWords.contains(token) {
            if !result.contains(token) { result.append(token) }
        }
        return result
    }

    private static func tokens(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map(String.init)
            .map { $0.replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty }
    }

    private static func equivalent(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs.count > 2, rhs.count > 2 else { return lhs == rhs }
        let left = root(lhs)
        let right = root(rhs)
        return left == right || left.hasPrefix(right) || right.hasPrefix(left)
    }

    private static func root(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ing"), word.count > 5 { return String(word.dropLast(3)) }
        if word.hasSuffix("ed"), word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("es"), word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), word.count > 3 { return String(word.dropLast()) }
        return word
    }

    private static func numberValues(in text: String) -> [Double] {
        text.lowercased()
            .split { !$0.isNumber && !$0.isLetter && $0 != "." && $0 != "," }
            .compactMap { token in
                let value = String(token).replacingOccurrences(of: ",", with: "")
                return Double(value) ?? spokenNumbers[value]
            }
    }

    private static func containsNegationNear(term: String, transcriptTokens: [String]) -> Bool {
        for index in transcriptTokens.indices where equivalent(transcriptTokens[index], term) {
            let lowerBound = max(transcriptTokens.startIndex, index - 3)
            let upperBound = min(transcriptTokens.index(before: transcriptTokens.endIndex), index + 3)
            if transcriptTokens[lowerBound...upperBound].contains(where: { negationWords.contains($0) }) {
                return true
            }
        }
        return false
    }

    private static func adjustedRatio(_ ratio: Double, sensitivity: String) -> Double {
        switch sensitivity {
        case "Conservative": return min(0.95, ratio + 0.15)
        case "Fast": return max(0.2, ratio - 0.15)
        default: return ratio
        }
    }
}
