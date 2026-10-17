import Foundation
import SwiftUI

func transcriptExportFilename(title: String, fileExtension: String = "txt") -> String {
    let stem = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }.joined(separator: "-")
    return "\(stem.isEmpty ? "Session" : String(stem.prefix(80)))-transcript.\(fileExtension)"
}

func fillerWordCount(in transcript: String) -> Int {
    let words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    guard !words.isEmpty else { return 0 }

    let phrases = [["you", "know"], ["sort", "of"], ["kind", "of"]]
    let singleWords: Set<String> = ["um", "uh", "erm", "basically", "actually"]
    var count = 0
    var index = 0
    while index < words.count {
        if let phrase = phrases.first(where: { phrase in
            words.indices.contains(index + phrase.count - 1) && Array(words[index..<(index + phrase.count)]) == phrase
        }) {
            count += 1
            index += phrase.count
        } else {
            if singleWords.contains(words[index]) { count += 1 }
            index += 1
        }
    }
    return count
}

func cueSetExportText(for presentation: Presentation) -> String {
    var lines = ["# \(presentation.title)"]
    if !presentation.audience.isEmpty { lines.append("Audience: \(presentation.audience)") }
    if !presentation.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append(contentsOf: ["", "Notes:", presentation.notes])
    }
    lines.append("")

    func append(_ cue: Cue, indent: String) {
        lines.append("\(indent)- \(cue.title)")
        if !cue.detail.isEmpty { lines.append("\(indent)  \(cue.detail)") }
        cue.completionRequirements.forEach { lines.append("\(indent)  Required meaning: \($0)") }
        cue.children.forEach { append($0, indent: indent + "  ") }
    }
    presentation.cues.forEach { append($0, indent: "") }
    return lines.joined(separator: "\n")
}

enum CueCompletionRule: String, Codable, CaseIterable, Identifiable {
    case single
    case allChildren
    case anyChild
    case countChildren

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return "Single cue"
        case .allChildren: return "All sub-cues"
        case .anyChild: return "Any sub-cue"
        case .countChildren: return "Minimum count"
        }
    }

    var detail: String {
        switch self {
        case .single: return "Match this talking point directly."
        case .allChildren: return "Every required sub-cue must be covered."
        case .anyChild: return "At least one sub-cue must be covered."
        case .countChildren: return "A minimum number of sub-cues must be covered."
        }
    }
}

enum CueCoverageMode: String, Codable, CaseIterable, Identifiable {
    case balanced
    case strict
    case mentionOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .strict: return "Strict"
        case .mentionOnly: return "Mention only"
        }
    }

    var detail: String {
        switch self {
        case .balanced: return "Recognize the required meaning, including paraphrases."
        case .strict: return "Require stronger evidence before checking off."
        case .mentionOnly: return "A clear mention is enough."
        }
    }
}

enum CueTimingRule: String, Codable, CaseIterable, Identifiable {
    case anyOrder
    case opening
    case closing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyOrder: return "Any order"
        case .opening: return "Opening"
        case .closing: return "Closing"
        }
    }

    var detail: String {
        switch self {
        case .anyOrder: return "This cue can be covered whenever it fits."
        case .opening: return "Aim to cover this in the first quarter."
        case .closing: return "Aim to cover this in the final quarter."
        }
    }
}

struct Cue: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var detail: String
    var isRequired: Bool
    var keywords: [String]
    var coverageMode: CueCoverageMode
    var timingRule: CueTimingRule
    var children: [Cue]
    var completionRule: CueCompletionRule
    var minimumChildCount: Int
    var completionRequirements: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case isRequired
        case keywords
        case coverageMode
        case timingRule
        case children
        case completionRule
        case minimumChildCount
        case completionRequirements
    }

    init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        isRequired: Bool = true,
        keywords: [String] = [],
        coverageMode: CueCoverageMode = .balanced,
        timingRule: CueTimingRule = .anyOrder,
        children: [Cue] = [],
        completionRule: CueCompletionRule = .single,
        minimumChildCount: Int = 1,
        completionRequirements: [String] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isRequired = isRequired
        self.keywords = keywords
        self.coverageMode = coverageMode
        self.timingRule = timingRule
        self.children = children
        self.completionRule = completionRule
        self.minimumChildCount = max(1, minimumChildCount)
        self.completionRequirements = completionRequirements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? true
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        coverageMode = try container.decodeIfPresent(CueCoverageMode.self, forKey: .coverageMode) ?? .balanced
        timingRule = try container.decodeIfPresent(CueTimingRule.self, forKey: .timingRule) ?? .anyOrder
        children = try container.decodeIfPresent([Cue].self, forKey: .children) ?? []
        completionRule = try container.decodeIfPresent(CueCompletionRule.self, forKey: .completionRule) ?? (children.isEmpty ? .single : .allChildren)
        minimumChildCount = max(1, try container.decodeIfPresent(Int.self, forKey: .minimumChildCount) ?? 1)
        completionRequirements = try container.decodeIfPresent([String].self, forKey: .completionRequirements) ?? []
    }

    var isGroup: Bool { !children.isEmpty }

    var leafCues: [Cue] {
        children.isEmpty ? [self] : children.flatMap(\.leafCues)
    }

    func cleaned() -> Cue? {
        let cleanedChildren = children.compactMap { $0.cleaned() }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return nil }
        return Cue(
            id: id,
            title: cleanedTitle,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            isRequired: isRequired,
            keywords: keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            coverageMode: coverageMode,
            timingRule: timingRule,
            children: cleanedChildren,
            completionRule: cleanedChildren.isEmpty ? .single : completionRule,
            minimumChildCount: minimumChildCount,
            completionRequirements: completionRequirements.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
    }
}

struct PresentationSlide: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var notes: String

    init(id: UUID = UUID(), title: String, notes: String = "") {
        self.id = id
        self.title = title
        self.notes = notes
    }
}

enum SpeechLocale: String, Codable, CaseIterable, Identifiable {
    case englishUS = "en-US"
    case englishUK = "en-GB"
    case englishAustralia = "en-AU"
    case spanishSpain = "es-ES"
    case frenchFrance = "fr-FR"
    case germanGermany = "de-DE"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .englishUS: return "English (US)"
        case .englishUK: return "English (UK)"
        case .englishAustralia: return "English (Australia)"
        case .spanishSpain: return "Spanish (Spain)"
        case .frenchFrance: return "French (France)"
        case .germanGermany: return "German (Germany)"
        }
    }
}

struct Presentation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var audience: String
    var notes: String
    var targetDurationSeconds: Int
    var cues: [Cue]
    var slides: [PresentationSlide]
    var recognitionLocale: SpeechLocale
    var preferredSessionMode: SessionMode
    var coverageSensitivity: String
    var analysisModeOverride: AnalysisPrivacyMode?
    var hapticsEnabledOverride: Bool?
    var keepScreenAwakeOverride: Bool?
    var showTranscriptOverride: Bool?
    var saveTranscriptOverride: Bool?
    var updatedAt: Date
    var practiceSourceRunID: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case audience
        case notes
        case targetDurationSeconds
        case cues
        case slides
        case recognitionLocale
        case preferredSessionMode
        case coverageSensitivity
        case analysisModeOverride
        case hapticsEnabledOverride
        case keepScreenAwakeOverride
        case showTranscriptOverride
        case saveTranscriptOverride
        case updatedAt
        case practiceSourceRunID
    }

    init(
        id: UUID = UUID(),
        title: String,
        audience: String = "",
        notes: String = "",
        targetDurationSeconds: Int = 12 * 60,
        cues: [Cue],
        slides: [PresentationSlide] = [],
        recognitionLocale: SpeechLocale = .englishUS,
        preferredSessionMode: SessionMode = .live,
        coverageSensitivity: String = "Global",
        analysisModeOverride: AnalysisPrivacyMode? = nil,
        hapticsEnabledOverride: Bool? = nil,
        keepScreenAwakeOverride: Bool? = nil,
        showTranscriptOverride: Bool? = nil,
        saveTranscriptOverride: Bool? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.audience = audience
        self.notes = notes
        self.targetDurationSeconds = targetDurationSeconds
        self.cues = cues
        self.slides = slides
        self.recognitionLocale = recognitionLocale
        self.preferredSessionMode = preferredSessionMode
        self.coverageSensitivity = coverageSensitivity
        self.analysisModeOverride = analysisModeOverride
        self.hapticsEnabledOverride = hapticsEnabledOverride
        self.keepScreenAwakeOverride = keepScreenAwakeOverride
        self.showTranscriptOverride = showTranscriptOverride
        self.saveTranscriptOverride = saveTranscriptOverride
        self.updatedAt = updatedAt
        self.practiceSourceRunID = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        audience = try container.decodeIfPresent(String.self, forKey: .audience) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        targetDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .targetDurationSeconds) ?? 12 * 60
        cues = try container.decodeIfPresent([Cue].self, forKey: .cues) ?? []
        slides = try container.decodeIfPresent([PresentationSlide].self, forKey: .slides) ?? []
        recognitionLocale = try container.decodeIfPresent(SpeechLocale.self, forKey: .recognitionLocale) ?? .englishUS
        preferredSessionMode = try container.decodeIfPresent(SessionMode.self, forKey: .preferredSessionMode) ?? .live
        coverageSensitivity = try container.decodeIfPresent(String.self, forKey: .coverageSensitivity) ?? "Global"
        analysisModeOverride = try container.decodeIfPresent(AnalysisPrivacyMode.self, forKey: .analysisModeOverride)
        hapticsEnabledOverride = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabledOverride)
        keepScreenAwakeOverride = try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwakeOverride)
        showTranscriptOverride = try container.decodeIfPresent(Bool.self, forKey: .showTranscriptOverride)
        saveTranscriptOverride = try container.decodeIfPresent(Bool.self, forKey: .saveTranscriptOverride)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        practiceSourceRunID = try container.decodeIfPresent(UUID.self, forKey: .practiceSourceRunID)
    }

    var leafCues: [Cue] { cues.flatMap(\.leafCues) }
    var isPracticeDrill: Bool { practiceSourceRunID != nil }

    /// Prune the tree, retaining ancestor notes and completion rules. Never
    /// replace the library plan: a drill is an isolated, report-owned snapshot.
    func unfinishedPractice(results: [CueResult], sourceRunID: UUID) -> Presentation? {
        let completed = Set(results.filter {
            $0.status == .covered || $0.status == .manual
        }.map(\.cueID))
        func prune(_ cue: Cue) -> Cue? {
            if cue.children.isEmpty {
                return cue.isRequired && !completed.contains(cue.id) ? cue : nil
            }
            var group = cue
            group.children = cue.children.compactMap(prune)
            return group.children.isEmpty ? nil : group
        }
        var drill = self
        drill.cues = cues.compactMap(prune)
        guard !drill.cues.isEmpty else { return nil }
        drill.practiceSourceRunID = sourceRunID
        drill.preferredSessionMode = .practice
        drill.slides = []
        return drill
    }
    var requiredCueCount: Int { leafCues.filter(\.isRequired).count }
    var durationLabel: String {
        let minutes = targetDurationSeconds / 60
        return "\(minutes) min target"
    }
}

func timingViolation(for cue: Cue, completionSeconds: Int?, targetDurationSeconds: Int) -> Bool {
    guard let completionSeconds, targetDurationSeconds > 0 else { return false }
    switch cue.timingRule {
    case .anyOrder:
        return false
    case .opening:
        return completionSeconds > Int(Double(targetDurationSeconds) * 0.25)
    case .closing:
        return completionSeconds < Int(Double(targetDurationSeconds) * 0.75)
    }
}

enum CueStatus: String, Codable, Hashable {
    case open
    case emerging
    case covered
    case manual

    var label: String {
        switch self {
        case .open: return "Open"
        case .emerging: return "Emerging"
        case .covered: return "Covered"
        case .manual: return "Manual"
        }
    }
}

enum SessionMode: String, Codable, CaseIterable, Identifiable {
    case live
    case practice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return "Live"
        case .practice: return "Practice"
        }
    }

    var detail: String {
        switch self {
        case .live:
            return "A focused checklist for a real presentation."
        case .practice:
            return "Rehearse freely and review the same coverage report afterward."
        }
    }
}

struct CueResult: Identifiable, Codable, Hashable {
    let id: UUID
    let cueID: UUID
    var status: CueStatus
    var firstMentionSeconds: Int?
    var depthScore: Double?
    var evidenceSnippet: String?
    var completionSeconds: Int?
    var wasManualOverride: Bool
    var semanticNote: String?
    var coverageMethod: String?

    init(cueID: UUID, status: CueStatus = .open, firstMentionSeconds: Int? = nil, depthScore: Double? = nil, evidenceSnippet: String? = nil, completionSeconds: Int? = nil, wasManualOverride: Bool = false) {
        self.id = cueID
        self.cueID = cueID
        self.status = status
        self.firstMentionSeconds = firstMentionSeconds
        self.depthScore = depthScore
        self.evidenceSnippet = evidenceSnippet
        self.completionSeconds = completionSeconds
        self.wasManualOverride = wasManualOverride
    }
}

struct SessionCheckpoint: Identifiable, Codable, Hashable {
    let id: UUID
    let presentationID: UUID
    let startedAt: Date
    let elapsed: Int
    let mode: SessionMode
    let slideAware: Bool
    let activeSlideIndex: Int
    let results: [CueResult]
    let updatedAt: Date
    let presentationSnapshot: Presentation?

    init(
        id: UUID = UUID(),
        presentationID: UUID,
        startedAt: Date,
        elapsed: Int,
        mode: SessionMode,
        slideAware: Bool,
        activeSlideIndex: Int = 0,
        results: [CueResult],
        updatedAt: Date = .now,
        presentationSnapshot: Presentation? = nil
    ) {
        self.id = id
        self.presentationID = presentationID
        self.startedAt = startedAt
        self.elapsed = max(0, elapsed)
        self.mode = mode
        self.slideAware = slideAware
        self.activeSlideIndex = max(0, activeSlideIndex)
        self.results = results
        self.updatedAt = updatedAt
        self.presentationSnapshot = presentationSnapshot
    }
}

enum PauseMetricSource: String, Codable, Hashable {
    case recognitionUpdates
    case microphoneLevel

    var longestLabel: String {
        self == .microphoneLevel ? "longest quiet" : "longest recognition gap"
    }

    var countLabel: String {
        self == .microphoneLevel ? "quiet stretches" : "recognition gaps"
    }
}

struct SessionRun: Identifiable, Codable, Hashable {
    let id: UUID
    let presentationID: UUID
    let startedAt: Date
    let durationSeconds: Int
    let wordCount: Int
    let fillerWordCount: Int
    let longestSilenceSeconds: Int
    let longSilenceCount: Int
    let pauseMetricSource: PauseMetricSource
    let requiredCoveredCount: Int
    let hasRequiredCoverageMetadata: Bool
    let results: [CueResult]
    let transcript: String?
    let mode: SessionMode
    let slideAware: Bool
    let presentationSnapshot: Presentation?
    var isPracticeDrill: Bool { presentationSnapshot?.isPracticeDrill == true }

    private enum CodingKeys: String, CodingKey {
        case id
        case presentationID
        case startedAt
        case durationSeconds
        case wordCount
        case fillerWordCount
        case longestSilenceSeconds
        case longSilenceCount
        case pauseMetricSource
        case requiredCoveredCount
        case results
        case transcript
        case mode
        case slideAware
        case presentationSnapshot
    }

    init(
        id: UUID,
        presentationID: UUID,
        startedAt: Date,
        durationSeconds: Int,
        wordCount: Int = 0,
        fillerWordCount: Int = 0,
        longestSilenceSeconds: Int = 0,
        longSilenceCount: Int = 0,
        pauseMetricSource: PauseMetricSource = .recognitionUpdates,
        requiredCoveredCount: Int = 0,
        hasRequiredCoverageMetadata: Bool = true,
        results: [CueResult],
        transcript: String? = nil,
        mode: SessionMode = .live,
        slideAware: Bool = false,
        presentationSnapshot: Presentation? = nil
    ) {
        self.id = id
        self.presentationID = presentationID
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.wordCount = max(0, wordCount)
        self.fillerWordCount = max(0, fillerWordCount)
        self.longestSilenceSeconds = max(0, longestSilenceSeconds)
        self.longSilenceCount = max(0, longSilenceCount)
        self.pauseMetricSource = pauseMetricSource
        self.requiredCoveredCount = max(0, requiredCoveredCount)
        self.hasRequiredCoverageMetadata = hasRequiredCoverageMetadata
        self.results = results
        self.transcript = transcript
        self.mode = mode
        self.slideAware = slideAware
        self.presentationSnapshot = presentationSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        presentationID = try container.decode(UUID.self, forKey: .presentationID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        wordCount = max(0, try container.decodeIfPresent(Int.self, forKey: .wordCount) ?? 0)
        fillerWordCount = max(0, try container.decodeIfPresent(Int.self, forKey: .fillerWordCount) ?? 0)
        longestSilenceSeconds = max(0, try container.decodeIfPresent(Int.self, forKey: .longestSilenceSeconds) ?? 0)
        longSilenceCount = max(0, try container.decodeIfPresent(Int.self, forKey: .longSilenceCount) ?? 0)
        pauseMetricSource = try container.decodeIfPresent(PauseMetricSource.self, forKey: .pauseMetricSource) ?? .recognitionUpdates
        results = try container.decode([CueResult].self, forKey: .results)
        requiredCoveredCount = max(0, try container.decodeIfPresent(Int.self, forKey: .requiredCoveredCount) ?? results.filter { $0.status == .covered || $0.status == .manual }.count)
        hasRequiredCoverageMetadata = container.contains(.requiredCoveredCount)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        mode = try container.decodeIfPresent(SessionMode.self, forKey: .mode) ?? .live
        slideAware = try container.decodeIfPresent(Bool.self, forKey: .slideAware) ?? false
        presentationSnapshot = try container.decodeIfPresent(Presentation.self, forKey: .presentationSnapshot)
    }

    var coveredCount: Int { results.filter { $0.status == .covered || $0.status == .manual }.count }
    var requiredCoverageCount: Int { hasRequiredCoverageMetadata ? requiredCoveredCount : coveredCount }
    var manualCount: Int { results.filter(\.wasManualOverride).count }
    var wordsPerMinute: Int {
        guard durationSeconds > 0, wordCount > 0 else { return 0 }
        return Int((Double(wordCount) * 60 / Double(durationSeconds)).rounded())
    }
}

struct PresentationTrendSummary: Hashable {
    let runCount: Int
    let averageCoverage: Double
    let bestCoverage: Double
    let averageWordsPerMinute: Int
    let recentCoverageDelta: Double?
}

func presentationTrendSummary(presentation: Presentation, runs: [SessionRun]) -> PresentationTrendSummary {
    let runs = runs.filter { !$0.isPracticeDrill }
    guard !runs.isEmpty else {
        return PresentationTrendSummary(runCount: 0, averageCoverage: 0, bestCoverage: 0, averageWordsPerMinute: 0, recentCoverageDelta: nil)
    }
    let coverageValues = runs.map { run in
        let plan = run.presentationSnapshot ?? presentation
        guard plan.requiredCueCount > 0 else { return 0.0 }
        return min(1, Double(run.requiredCoverageCount) / Double(plan.requiredCueCount))
    }
    let paceValues = runs.map(\.wordsPerMinute).filter { $0 > 0 }
    return PresentationTrendSummary(
        runCount: runs.count,
        averageCoverage: coverageValues.reduce(0, +) / Double(coverageValues.count),
        bestCoverage: coverageValues.max() ?? 0,
        averageWordsPerMinute: paceValues.isEmpty ? 0 : Int((Double(paceValues.reduce(0, +)) / Double(paceValues.count)).rounded()),
        recentCoverageDelta: runs.count > 1 ? coverageValues[0] - coverageValues[1] : nil
    )
}

enum AnalysisPrivacyMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case onDeviceOnly
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDeviceOnly: return "On-device only"
        case .hybrid: return "Hybrid"
        }
    }

    var label: String { title }

    var detail: String {
        switch self {
        case .onDeviceOnly:
            return "Checks this device and language before each session. If unavailable, speech stops instead of using the network; audio and transcript stay on this device."
        case .hybrid:
            return "Explicitly allows Apple’s network-assisted speech recognition when on-device recognition is unavailable."
        }
    }
}

struct AppSettings: Codable {
    var hapticsEnabled = true
    var keepScreenAwake = true
    var showTranscript = false
    var saveTranscript = false
    var sensitivity = "Balanced"
    var analysisMode: AnalysisPrivacyMode = .onDeviceOnly

    private enum CodingKeys: String, CodingKey {
        case hapticsEnabled
        case keepScreenAwake
        case showTranscript
        case saveTranscript
        case sensitivity
        case analysisMode
    }

    init(
        hapticsEnabled: Bool = true,
        keepScreenAwake: Bool = true,
        showTranscript: Bool = false,
        saveTranscript: Bool = false,
        sensitivity: String = "Balanced",
        analysisMode: AnalysisPrivacyMode = .onDeviceOnly
    ) {
        self.hapticsEnabled = hapticsEnabled
        self.keepScreenAwake = keepScreenAwake
        self.showTranscript = showTranscript
        self.saveTranscript = saveTranscript
        self.sensitivity = sensitivity
        self.analysisMode = analysisMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        keepScreenAwake = try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? true
        showTranscript = try container.decodeIfPresent(Bool.self, forKey: .showTranscript) ?? false
        saveTranscript = try container.decodeIfPresent(Bool.self, forKey: .saveTranscript) ?? false
        sensitivity = try container.decodeIfPresent(String.self, forKey: .sensitivity) ?? "Balanced"
        analysisMode = try container.decodeIfPresent(AnalysisPrivacyMode.self, forKey: .analysisMode) ?? .onDeviceOnly
    }
}

struct PresentationSessionConfiguration: Hashable {
    let analysisMode: AnalysisPrivacyMode
    let hapticsEnabled: Bool
    let keepScreenAwake: Bool
    let showTranscript: Bool
    let saveTranscript: Bool

    init(presentation: Presentation, global: AppSettings) {
        analysisMode = presentation.analysisModeOverride ?? global.analysisMode
        hapticsEnabled = presentation.hapticsEnabledOverride ?? global.hapticsEnabled
        keepScreenAwake = presentation.keepScreenAwakeOverride ?? global.keepScreenAwake
        showTranscript = presentation.showTranscriptOverride ?? global.showTranscript
        saveTranscript = presentation.saveTranscriptOverride ?? global.saveTranscript
    }
}

struct CueCompleteDataExport: Codable {
    let exportedAt: Date
    let presentations: [Presentation]
    let runs: [SessionRun]
    let settings: AppSettings
}

func cueCompleteDataExportText(presentations: [Presentation], runs: [SessionRun], settings: AppSettings) -> String {
    let export = CueCompleteDataExport(exportedAt: .now, presentations: presentations, runs: runs, settings: settings)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(export), let text = String(data: data, encoding: .utf8) else {
        return "Cue Complete data export unavailable."
    }
    return text
}

enum Brand {
    static let navy = Color(red: 0.035, green: 0.075, blue: 0.17)
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.22)
    static let slate = Color(red: 0.38, green: 0.43, blue: 0.53)
    static let mist = Color(red: 0.95, green: 0.97, blue: 1.0)
    static let cyan = Color(red: 0.0, green: 0.70, blue: 0.78)
    static let blue = Color(red: 0.12, green: 0.38, blue: 0.98)
    static let mint = Color(red: 0.16, green: 0.86, blue: 0.66)
    static let warning = Color(red: 0.95, green: 0.56, blue: 0.24)
    static let cloud = Color(red: 0.975, green: 0.98, blue: 0.99)
}
