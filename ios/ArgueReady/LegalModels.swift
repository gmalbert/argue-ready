import Foundation
import SwiftUI

func legalRequirementCandidates(from text: String) -> [String] {
    var seen = Set<String>()
    return text.components(separatedBy: .newlines).compactMap { line in
        var candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = candidate.replacingOccurrences(of: #"^\s*#{1,6}\s*"#, with: "", options: .regularExpression)
        candidate = candidate.replacingOccurrences(of: #"^\s*(?:[-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression)
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count >= 4, candidate.count <= 180 else { return nil }
        let key = candidate.lowercased()
        guard seen.insert(key).inserted else { return nil }
        return candidate
    }
    .prefix(24)
    .map { $0 }
}

struct LegalRequirement: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var detail: String
    var isRequired: Bool
    var children: [LegalRequirement]

    init(id: UUID = UUID(), title: String, detail: String = "", isRequired: Bool = true, children: [LegalRequirement] = []) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isRequired = isRequired
        self.children = children
    }

    var leafRequirements: [LegalRequirement] {
        children.isEmpty ? [self] : children.flatMap(\.leafRequirements)
    }

    func path(to requirementID: UUID) -> [LegalRequirement]? {
        if id == requirementID { return [self] }
        for child in children {
            if let path = child.path(to: requirementID) { return [self] + path }
        }
        return nil
    }

    var cue: Cue {
        Cue(id: id, title: title, detail: detail, isRequired: isRequired, coverageMode: .strict)
    }
}

func legalNextRequirementID(requirements: [LegalRequirement], results: [CueResult]) -> UUID? {
    let unfinished = requirements.filter { requirement in
        guard let result = results.first(where: { $0.cueID == requirement.id }) else { return true }
        return result.status == .open || result.status == .emerging
    }
    return (unfinished.first(where: \.isRequired) ?? unfinished.first)?.id
}

struct AuthorityCard: Identifiable, Codable, Hashable {
    let id: UUID
    var citation: String
    var proposition: String
    var caution: String

    init(id: UUID = UUID(), citation: String, proposition: String, caution: String = "") {
        self.id = id
        self.citation = citation
        self.proposition = proposition
        self.caution = caution
    }
}

struct RecordCitationCard: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var citation: String
    var proposition: String

    init(id: UUID = UUID(), label: String, citation: String, proposition: String) {
        self.id = id
        self.label = label
        self.citation = citation
        self.proposition = proposition
    }
}

struct PreparedQuestion: Identifiable, Codable, Hashable {
    let id: UUID
    var question: String
    var topic: String
    var response: String

    init(id: UUID = UUID(), question: String, topic: String, response: String) {
        self.id = id
        self.question = question
        self.topic = topic
        self.response = response
    }
}

enum LegalContextCardKind: String, Codable, CaseIterable, Identifiable {
    case proceduralHistory
    case factualCorrection
    case danger
    case remedy
    case transition

    var id: String { rawValue }

    var title: String {
        switch self {
        case .proceduralHistory: return "Procedural history"
        case .factualCorrection: return "Factual correction"
        case .danger: return "Do not concede"
        case .remedy: return "Remedy"
        case .transition: return "Transition"
        }
    }

    var icon: String {
        switch self {
        case .proceduralHistory: return "arrow.triangle.branch"
        case .factualCorrection: return "exclamationmark.circle"
        case .danger: return "exclamationmark.triangle"
        case .remedy: return "arrow.uturn.right"
        case .transition: return "arrow.right"
        }
    }
}

struct LegalContextCard: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: LegalContextCardKind
    var title: String
    var body: String
    var source: String

    init(id: UUID = UUID(), kind: LegalContextCardKind, title: String, body: String, source: String = "") {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.source = source
    }
}

struct LegalIssue: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var shortLabel: String
    var requirements: [LegalRequirement]
    var authorities: [AuthorityCard]
    var recordCitations: [RecordCitationCard]
    var likelyQuestions: [PreparedQuestion]
    var contextCards: [LegalContextCard]

    private enum CodingKeys: String, CodingKey {
        case id, title, shortLabel, requirements, authorities, recordCitations, likelyQuestions, contextCards
    }

    init(
        id: UUID = UUID(),
        title: String,
        shortLabel: String,
        requirements: [LegalRequirement],
        authorities: [AuthorityCard] = [],
        recordCitations: [RecordCitationCard] = [],
        likelyQuestions: [PreparedQuestion] = [],
        contextCards: [LegalContextCard] = []
    ) {
        self.id = id
        self.title = title
        self.shortLabel = shortLabel
        self.requirements = requirements
        self.authorities = authorities
        self.recordCitations = recordCitations
        self.likelyQuestions = likelyQuestions
        self.contextCards = contextCards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        shortLabel = try container.decode(String.self, forKey: .shortLabel)
        requirements = try container.decodeIfPresent([LegalRequirement].self, forKey: .requirements) ?? []
        authorities = try container.decodeIfPresent([AuthorityCard].self, forKey: .authorities) ?? []
        recordCitations = try container.decodeIfPresent([RecordCitationCard].self, forKey: .recordCitations) ?? []
        likelyQuestions = try container.decodeIfPresent([PreparedQuestion].self, forKey: .likelyQuestions) ?? []
        contextCards = try container.decodeIfPresent([LegalContextCard].self, forKey: .contextCards) ?? []
    }

    var leafRequirements: [LegalRequirement] { requirements.flatMap(\.leafRequirements) }
}

struct LegalSessionPreferences: Codable, Hashable {
    var recognitionLocale: SpeechLocale? = nil
    var sensitivity: String? = nil
    var analysisMode: AnalysisPrivacyMode? = nil
    var hapticsEnabled: Bool? = nil
    var keepScreenAwake: Bool? = nil
    var showTranscript: Bool? = nil
    var saveTranscript: Bool? = nil
}

struct LegalMatter: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var court: String
    var docketNumber: String
    var role: String
    var totalMinutes: Int
    var rebuttalMinutes: Int
    var standardOfReview: String
    var proceduralHistory: String
    var requestedRelief: String
    var issues: [LegalIssue]
    var sessionPreferences: LegalSessionPreferences
    var practiceSourceRunID: UUID?
    var isPracticeDrill: Bool { practiceSourceRunID != nil }

    private enum CodingKeys: String, CodingKey {
        case id, title, court, docketNumber, role, totalMinutes, rebuttalMinutes, standardOfReview, proceduralHistory, requestedRelief, issues, sessionPreferences, practiceSourceRunID
    }

    init(
        id: UUID = UUID(),
        title: String,
        court: String,
        docketNumber: String,
        role: String,
        totalMinutes: Int,
        rebuttalMinutes: Int,
        standardOfReview: String = "",
        proceduralHistory: String = "",
        requestedRelief: String = "",
        issues: [LegalIssue],
        sessionPreferences: LegalSessionPreferences = LegalSessionPreferences()
    ) {
        self.id = id
        self.title = title
        self.court = court
        self.docketNumber = docketNumber
        self.role = role
        self.totalMinutes = totalMinutes
        self.rebuttalMinutes = rebuttalMinutes
        self.standardOfReview = standardOfReview
        self.proceduralHistory = proceduralHistory
        self.requestedRelief = requestedRelief
        self.issues = issues
        self.sessionPreferences = sessionPreferences
        self.practiceSourceRunID = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        court = try container.decodeIfPresent(String.self, forKey: .court) ?? ""
        docketNumber = try container.decodeIfPresent(String.self, forKey: .docketNumber) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        totalMinutes = try container.decodeIfPresent(Int.self, forKey: .totalMinutes) ?? 20
        rebuttalMinutes = try container.decodeIfPresent(Int.self, forKey: .rebuttalMinutes) ?? 3
        standardOfReview = try container.decodeIfPresent(String.self, forKey: .standardOfReview) ?? ""
        proceduralHistory = try container.decodeIfPresent(String.self, forKey: .proceduralHistory) ?? ""
        requestedRelief = try container.decodeIfPresent(String.self, forKey: .requestedRelief) ?? ""
        issues = try container.decodeIfPresent([LegalIssue].self, forKey: .issues) ?? []
        sessionPreferences = try container.decodeIfPresent(LegalSessionPreferences.self, forKey: .sessionPreferences) ?? LegalSessionPreferences()
        practiceSourceRunID = try container.decodeIfPresent(UUID.self, forKey: .practiceSourceRunID)
    }

    func unfinishedPractice(results: [CueResult], sourceRunID: UUID) -> LegalMatter? {
        let completed = Set(results.filter {
            $0.status == .covered || $0.status == .manual
        }.map(\.cueID))
        func prune(_ requirement: LegalRequirement) -> LegalRequirement? {
            if requirement.children.isEmpty {
                return requirement.isRequired && !completed.contains(requirement.id) ? requirement : nil
            }
            var group = requirement
            group.children = requirement.children.compactMap(prune)
            return group.children.isEmpty ? nil : group
        }
        var drill = self
        drill.issues = issues.compactMap { issue in
            var selected = issue
            selected.requirements = issue.requirements.compactMap(prune)
            return selected.requirements.isEmpty ? nil : selected
        }
        guard !drill.issues.isEmpty else { return nil }
        drill.practiceSourceRunID = sourceRunID
        return drill
    }

    var leafRequirements: [LegalRequirement] { issues.flatMap(\.leafRequirements) }
    var requiredLeafRequirements: [LegalRequirement] { leafRequirements.filter(\.isRequired) }
    var authorities: [AuthorityCard] { issues.flatMap(\.authorities) }
    var recordCitations: [RecordCitationCard] { issues.flatMap(\.recordCitations) }
    var likelyQuestions: [PreparedQuestion] { issues.flatMap(\.likelyQuestions) }
    var contextCards: [LegalContextCard] { issues.flatMap(\.contextCards) }

    var sessionPresentation: Presentation {
        Presentation(id: id, title: title, audience: court, targetDurationSeconds: totalMinutes * 60,
                     cues: leafRequirements.map(\.cue), recognitionLocale: sessionPreferences.recognitionLocale ?? .englishUS,
                     coverageSensitivity: sessionPreferences.sensitivity ?? "Global",
                     analysisModeOverride: .onDeviceOnly,
                     hapticsEnabledOverride: sessionPreferences.hapticsEnabled,
                     keepScreenAwakeOverride: sessionPreferences.keepScreenAwake,
                     showTranscriptOverride: sessionPreferences.showTranscript,
                     saveTranscriptOverride: sessionPreferences.saveTranscript)
    }

    func configuration(global: AppSettings) -> PresentationSessionConfiguration {
        PresentationSessionConfiguration(presentation: sessionPresentation, global: global)
    }

    static let seed = LegalMatter(
        id: UUID(uuidString: "B6F7B5B5-7C9B-4D77-9F1D-7C2C5D0F6B1A")!,
        title: "Acme v. Northstar — Oral Argument",
        court: "State Court of Appeals",
        docketNumber: "A-2026-0142",
        role: "Appellant",
        totalMinutes: 20,
        rebuttalMinutes: 3,
        standardOfReview: "Abuse of discretion",
        proceduralHistory: "The trial court excluded the business record after applying an extra certification requirement.",
        requestedRelief: "Reverse and remand for a new trial.",
        issues: [
            LegalIssue(
                title: "Evidentiary error",
                shortLabel: "Issue I",
                requirements: [
                    LegalRequirement(
                        title: "Establish reversible error",
                        detail: "The court used the wrong legal standard and the error mattered.",
                        children: [
                            LegalRequirement(title: "State the standard of review", detail: "Begin by naming the standard: abuse of discretion. Explain how your challenge concerns the legal standard used to exclude the business record. Then move to the extra certification requirement the trial court imposed."),
                            LegalRequirement(title: "Explain the legal error", detail: "Identify the extra certification requirement imposed below. Compare it with your prepared proposition under Rule 803(6). Use Exhibit 12 and Tr. 142:7–18 to anchor the ruling in the record. Keep authentication distinct from the extra requirement."),
                            LegalRequirement(title: "Explain prejudice", detail: "Explain what the excluded record would have shown, why that fact mattered to the disputed issue, and how its exclusion affected the outcome. Supply the specific facts and record cites from your brief before rehearsing; the example matter does not include those facts. Then connect the harm to the relief you seek."),
                            LegalRequirement(title: "Request the remedy", detail: "Close with the specific request: reverse and remand for a new trial. Tie that request back to the evidentiary error and the prejudice you just explained. Finish with a clear statement of the action you want the court to take.")
                        ]
                    )
                ],
                authorities: [
                    AuthorityCard(citation: "Rule 803(6)", proposition: "The business-record exception does not require the extra certification imposed below.", caution: "Do not concede that the record was never authenticated.")
                ],
                recordCitations: [
                    RecordCitationCard(label: "Exhibit 12", citation: "Tr. 142:7–18", proposition: "The court excluded the record after applying the wrong requirement.")
                ],
                likelyQuestions: [
                    PreparedQuestion(question: "Where was this preserved below?", topic: "Preservation", response: "The objection appears at Tr. 142:7–18 and was renewed at Tr. 167:2–9.")
                ],
                contextCards: [
                    LegalContextCard(kind: .danger, title: "Authentication concession", body: "Do not concede that the record was never authenticated.", source: "Counsel guardrail"),
                    LegalContextCard(kind: .proceduralHistory, title: "Preservation", body: "The objection appears at Tr. 142:7–18 and was renewed at Tr. 167:2–9.", source: "Record")
                ]
            )
        ]
    )
}

struct LegalRehearsalRun: Identifiable, Codable, Hashable {
    let id: UUID
    let matterID: UUID
    let startedAt: Date
    let durationSeconds: Int
    var results: [CueResult]
    var transcript: String?
    let matterSnapshot: LegalMatter?
    let wordCount: Int?
    let fillerCount: Int?
    var isPracticeDrill: Bool { matterSnapshot?.isPracticeDrill == true }

    init(id: UUID = UUID(), matterID: UUID, startedAt: Date, durationSeconds: Int, results: [CueResult],
         transcript: String? = nil, matterSnapshot: LegalMatter? = nil, wordCount: Int? = nil, fillerCount: Int? = nil) {
        self.id = id
        self.matterID = matterID
        self.startedAt = startedAt
        self.durationSeconds = max(0, durationSeconds)
        self.results = results
        self.transcript = transcript
        self.matterSnapshot = matterSnapshot
        self.wordCount = wordCount
        self.fillerCount = fillerCount
    }

    var coveredCount: Int { results.filter { $0.status == .covered || $0.status == .manual }.count }
    var manualCount: Int { results.filter(\.wasManualOverride).count }
    var wordsPerMinute: Int {
        guard durationSeconds > 0, let wordCount else { return 0 }
        return Int((Double(wordCount) * 60 / Double(durationSeconds)).rounded())
    }

    func requiredCoveredCount(for matter: LegalMatter) -> Int {
        let requiredIDs = Set(matter.requiredLeafRequirements.map(\.id))
        return results.filter { requiredIDs.contains($0.cueID) && ($0.status == .covered || $0.status == .manual) }.count
    }

    var replayRun: SessionRun {
        SessionRun(id: id, presentationID: matterID, startedAt: startedAt, durationSeconds: durationSeconds,
                   results: results, transcript: transcript, mode: .practice)
    }
}

struct LegalDataExport: Codable {
    let exportedAt: Date
    let matters: [LegalMatter]
    let runs: [LegalRehearsalRun]
    let settings: AppSettings
}

func legalDataExportText(matters: [LegalMatter], runs: [LegalRehearsalRun], settings: AppSettings) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(LegalDataExport(exportedAt: .now, matters: matters, runs: runs, settings: settings)),
          let text = String(data: data, encoding: .utf8) else { return "ArgueReady data export unavailable." }
    return text
}

struct LegalSessionCheckpoint: Identifiable, Codable, Hashable {
    let id: UUID
    let matterID: UUID
    let startedAt: Date
    let elapsed: Int
    let isQuestionMode: Bool
    let bookmarkedRequirement: UUID?
    let results: [CueResult]
    let updatedAt: Date
    let matterSnapshot: LegalMatter?

    init(
        id: UUID = UUID(),
        matterID: UUID,
        startedAt: Date,
        elapsed: Int,
        isQuestionMode: Bool,
        bookmarkedRequirement: UUID?,
        results: [CueResult],
        updatedAt: Date = .now,
        matterSnapshot: LegalMatter? = nil
    ) {
        self.id = id
        self.matterID = matterID
        self.startedAt = startedAt
        self.elapsed = max(0, elapsed)
        self.isQuestionMode = isQuestionMode
        self.bookmarkedRequirement = bookmarkedRequirement
        self.results = results
        self.updatedAt = updatedAt
        self.matterSnapshot = matterSnapshot
    }
}

func legalRehearsalReportText(matter: LegalMatter, results: [CueResult], durationSeconds: Int) -> String {
    let requirements = matter.leafRequirements
    let results = requirements.map { requirement in
        results.first(where: { $0.cueID == requirement.id }) ?? CueResult(cueID: requirement.id)
    }
    let requiredIndexes = requirements.indices.filter { requirements[$0].isRequired && $0 < results.count }
    let coveredCount = requiredIndexes.filter { results[$0].status == .covered || results[$0].status == .manual }.count
    var lines = [
        matter.isPracticeDrill ? "ArgueReady focused practice report" : "ArgueReady rehearsal report",
        matter.title,
        "Court: \(matter.court)",
        "Role: \(matter.role)",
        "Duration: \(durationSeconds / 60):\(String(format: "%02d", durationSeconds % 60))",
        "Required covered: \(coveredCount)/\(requiredIndexes.count)",
        "Manual corrections: \(results.filter(\.wasManualOverride).count)",
        "",
        "Requirements:"
    ]
    for index in requiredIndexes {
        let result = results[index]
        let status: String
        switch result.status {
        case .open: status = "Not addressed"
        case .emerging: status = "Partial"
        case .covered: status = result.wasManualOverride ? "Manually confirmed" : "Satisfied"
        case .manual: status = "Manual"
        }
        lines.append("- \(requirements[index].title): \(status)")
        if let note = result.semanticNote { lines.append("  Review: \(note)") }
        if let evidenceSnippet = result.evidenceSnippet {
            lines.append("  Evidence: \(evidenceSnippet)")
        }
    }
    return lines.joined(separator: "\n")
}

@MainActor
final class LegalMatterStore: ObservableObject {
    @Published var matters: [LegalMatter] { didSet { save() } }
    @Published var runs: [LegalRehearsalRun] { didSet { saveRuns() } }
    @Published var settings: AppSettings { didSet { saveSettings() } }
    @Published private(set) var sessionCheckpoint: LegalSessionCheckpoint? {
        didSet { saveCheckpoint() }
    }

    private let fileURL: URL?
    private let settingsFileURL: URL?
    private let runsFileURL: URL?
    private let checkpointFileURL: URL?
    private let checkpointBackupURL: URL?
    private let checkpointDefaultsKey: String

    init(directory customDirectory: URL? = nil) {
        let fileManager = FileManager.default
        checkpointDefaultsKey = customDirectory.map { "argueready.test-checkpoint.\($0.lastPathComponent)" } ?? "argueready.session-checkpoint"
        let directory = customDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("ArgueReady", isDirectory: true)
        if let directory { try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
        fileURL = directory?.appendingPathComponent("matters.json")
        runsFileURL = directory?.appendingPathComponent("rehearsals.json")
        settingsFileURL = directory?.appendingPathComponent("settings.json")
        checkpointFileURL = directory?.appendingPathComponent("active-rehearsal.json")
        checkpointBackupURL = customDirectory == nil ? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("active-rehearsal.json") : nil

        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([LegalMatter].self, from: data) {
            matters = saved
        } else {
            matters = [.seed]
        }

        if let runsFileURL,
           let data = try? Data(contentsOf: runsFileURL),
           let saved = try? JSONDecoder().decode([LegalRehearsalRun].self, from: data) {
            runs = saved
        } else {
            runs = []
        }

        if let settingsFileURL, let data = try? Data(contentsOf: settingsFileURL),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings(sensitivity: "Conservative")
        }

        if let checkpointFileURL,
           let data = try? Data(contentsOf: checkpointFileURL),
           let saved = try? JSONDecoder().decode(LegalSessionCheckpoint.self, from: data) {
            sessionCheckpoint = saved
        } else if let checkpointBackupURL,
                  let data = try? Data(contentsOf: checkpointBackupURL),
                  let saved = try? JSONDecoder().decode(LegalSessionCheckpoint.self, from: data) {
            sessionCheckpoint = saved
        } else if let data = UserDefaults.standard.data(forKey: checkpointDefaultsKey),
                  let saved = try? JSONDecoder().decode(LegalSessionCheckpoint.self, from: data) {
            sessionCheckpoint = saved
        } else {
            sessionCheckpoint = nil
        }
    }

    func upsert(_ matter: LegalMatter) {
        if let index = matters.firstIndex(where: { $0.id == matter.id }) {
            matters[index] = matter
        } else {
            matters.insert(matter, at: 0)
        }
    }

    func addRun(_ run: LegalRehearsalRun) {
        runs.insert(run, at: 0)
    }

    func updateRun(_ run: LegalRehearsalRun) {
        guard let index = runs.firstIndex(where: { $0.id == run.id }) else { return }
        runs[index] = run
    }

    func deleteAllRuns() { runs.removeAll() }

    func deleteSavedTranscripts() {
        if let sessionCheckpoint { saveSessionCheckpoint(sessionCheckpoint) }
        runs = runs.map { run in
            var clean = run
            clean.transcript = nil
            clean.results = clean.results.map { result in
                var cleanResult = result
                cleanResult.evidenceSnippet = nil
                return cleanResult
            }
            return clean
        }
    }

    func delete(_ matter: LegalMatter) {
        matters.removeAll { $0.id == matter.id }
        if sessionCheckpoint?.matterID == matter.id { clearSessionCheckpoint() }
    }

    func duplicate(_ matter: LegalMatter) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(matter),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        json["id"] = UUID().uuidString
        json["title"] = "\(matter.title) Copy"
        guard let copyData = try? JSONSerialization.data(withJSONObject: json),
              let copy = try? JSONDecoder().decode(LegalMatter.self, from: copyData) else { return }
        upsert(copy)
    }

    func exportDataText() -> String {
        legalDataExportText(matters: matters, runs: runs, settings: settings)
    }

    private func saveSettings() {
        guard let settingsFileURL, let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFileURL, options: [.atomic, .completeFileProtection])
    }

    func saveSessionCheckpoint(_ checkpoint: LegalSessionCheckpoint) {
        let clean = LegalSessionCheckpoint(id: checkpoint.id, matterID: checkpoint.matterID,
                                           startedAt: checkpoint.startedAt, elapsed: checkpoint.elapsed,
                                           isQuestionMode: checkpoint.isQuestionMode,
                                           bookmarkedRequirement: checkpoint.bookmarkedRequirement,
                                           results: checkpoint.results.map { result in
                                               var clean = result
                                               clean.evidenceSnippet = nil
                                               return clean
                                           }, updatedAt: checkpoint.updatedAt,
                                           matterSnapshot: checkpoint.matterSnapshot)
        sessionCheckpoint = clean
        if let data = try? JSONEncoder().encode(clean) {
            UserDefaults.standard.set(data, forKey: checkpointDefaultsKey)
            UserDefaults.standard.synchronize()
        }
    }

    func clearSessionCheckpoint() {
        sessionCheckpoint = nil
        UserDefaults.standard.removeObject(forKey: checkpointDefaultsKey)
        UserDefaults.standard.synchronize()
    }

    func runs(for matter: LegalMatter) -> [LegalRehearsalRun] {
        runs.filter { $0.matterID == matter.id }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(matters) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func saveRuns() {
        guard let runsFileURL, let data = try? JSONEncoder().encode(runs) else { return }
        try? data.write(to: runsFileURL, options: [.atomic, .completeFileProtection])
    }

    private func saveCheckpoint() {
        if let sessionCheckpoint, let data = try? JSONEncoder().encode(sessionCheckpoint) {
            if let checkpointFileURL {
                try? data.write(to: checkpointFileURL, options: [.atomic, .completeFileProtection])
            }
            if let checkpointBackupURL {
                try? data.write(to: checkpointBackupURL, options: [.atomic, .completeFileProtection])
            }
            // Keep a tiny local metadata fallback for simulator/runtime environments
            // where protected Application Support writes can be unavailable.
            UserDefaults.standard.set(data, forKey: checkpointDefaultsKey)
        } else {
            if let checkpointFileURL {
                try? FileManager.default.removeItem(at: checkpointFileURL)
            }
            if let checkpointBackupURL {
                try? FileManager.default.removeItem(at: checkpointBackupURL)
            }
            UserDefaults.standard.removeObject(forKey: checkpointDefaultsKey)
        }
    }
}
