import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Shared by both report screens. Unsaved speech stays in memory until the
/// report closes; sharing is always an explicit user action.
struct SessionTranscriptSection: View {
    let transcript: String?
    let isSaved: Bool
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NavigationLink {
                    SessionTranscriptView(transcript: transcript, title: title, isSaved: isSaved)
                } label: {
                    Label("View transcript", systemImage: "doc.text")
                        .font(.headline)
                }
                .accessibilityIdentifier("viewTranscript")
                Text(isSaved ? "Read, select, or share the transcript as PDF or text."
                     : "Available until this report closes. Share as PDF or text; transcript saving is off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("No transcript available", systemImage: "doc.text")
                    .font(.headline)
                Text("No speech text was retained for this report. Enable Save transcript locally before a future session to keep it in history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SessionTranscriptView: View {
    let transcript: String
    let title: String
    let isSaved: Bool
    @State private var shareItem: TranscriptShareItem?
    @State private var shareError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.title2.bold())
                if !isSaved {
                    Text("This transcript is available for this report only. Share it as PDF or text before closing.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text(transcript)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("transcriptText")
            }
            .padding(20)
        }
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    shareActions
                } label: {
                    Label("Share transcript", systemImage: "square.and.arrow.up")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Menu {
                shareActions
            } label: {
                Label("Share transcript", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("shareTranscript")
            .padding()
            .background(.bar)
        }
        .sheet(item: $shareItem) { item in
            TranscriptShareSheet(item: item)
        }
        .alert("Unable to share transcript", isPresented: Binding(
            get: { shareError != nil }, set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: { Text(shareError ?? "Please try again.") }
    }

    @ViewBuilder
    private var shareActions: some View {
        Button {
            prepareShare(.pdf)
        } label: {
            Label("PDF (.pdf)", systemImage: "doc.richtext")
        }
        .accessibilityIdentifier("shareTranscriptPDF")
        Button {
            prepareShare(.text)
        } label: {
            Label("Text (.txt)", systemImage: "doc.plaintext")
        }
        .accessibilityIdentifier("shareTranscriptText")
    }

    private func prepareShare(_ format: TranscriptExportFormat) {
        do {
            shareItem = try format.shareItem(transcript: transcript, title: title)
        } catch {
            shareError = error.localizedDescription
        }
    }
}

struct CoreCoverageReplay: Identifiable {
    let presentation: Presentation
    let run: SessionRun
    var id: UUID { run.id }
}

struct CoreSettingsView: View {
    @Binding var settings: AppSettings
    let productName: String
    let tagline: String
    let collectionName: String
    let exportText: String
    let replayCandidates: [CoreCoverageReplay]
    let deleteHistory: () -> Void
    let deleteTranscripts: () -> Void
    var localOnly = false
    @State private var showingDeleteHistoryConfirmation = false
    @State private var showingDeleteTranscriptConfirmation = false
    @State private var showingCoverageLab = false
    @State private var showingSemanticLab = false
    @State private var showingIssueReport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(productName)
                                .font(.headline)
                            Text(tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Live session") {
                    Toggle("Haptic feedback", isOn: Binding(get: { settings.hapticsEnabled }, set: { settings.hapticsEnabled = $0 }))
                    Toggle("Keep screen awake", isOn: Binding(get: { settings.keepScreenAwake }, set: { settings.keepScreenAwake = $0 }))
                    Toggle("Show transcript preview", isOn: Binding(get: { settings.showTranscript }, set: { settings.showTranscript = $0 }))
                }

                Section("Coverage") {
                    if localOnly {
                        Label("On-device semantic coverage", systemImage: "brain")
                        Text("The local model checks meaning against your authored requirements and grounded speech evidence. Manual checks remain available when the model cannot run.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open on-device semantic lab") { showingSemanticLab = true }
                    }
                    if !localOnly {
                    Picker("Sensitivity", selection: Binding(get: { settings.sensitivity }, set: { settings.sensitivity = $0 })) {
                        Text("Conservative").tag("Conservative")
                        Text("Balanced").tag("Balanced")
                        Text("Fast").tag("Fast")
                    }
                    }
                    Label("A cue becomes complete only after enough evidence accumulates.", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        showingCoverageLab = true
                    } label: {
                        Label(localOnly ? "Legacy keyword diagnostics" : "Open coverage lab", systemImage: "flask")
                    }
                }

                Section("Privacy") {
                    Toggle("Save transcript locally", isOn: Binding(get: { settings.saveTranscript }, set: { settings.saveTranscript = $0 }))
                    Text("Off by default. When enabled, the completed transcript is saved with each session report on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if localOnly {
                        Label("On-device only", systemImage: "lock.shield")
                        Text("Speech and semantic coverage run locally. Unavailable models leave the checklist manual; there is no cloud fallback.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                    Picker("Processing", selection: Binding(get: { settings.analysisMode }, set: { settings.analysisMode = $0 })) {
                        ForEach(AnalysisPrivacyMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text(settings.analysisMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Label(localOnly ? "Audio, coverage and saved data stay on this device." : "Cue matching and saved session data stay local in both modes.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Audio behavior") {
                    Label("Live stream only", systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                    Text("While a session is listening, microphone audio is streamed to Apple’s active speech recognizer. \(productName) does not record raw audio to disk or upload it to a \(productName) server. Transcript text is saved only when you enable Save transcript locally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Apple Watch companion") {
                    Label("Checklist state only", systemImage: "applewatch")
                        .font(.subheadline.weight(.semibold))
                    Text("The Watch can show coverage, the next requirement, timing, and pause state so you can control a session from your wrist. It never receives microphone audio or transcript text. The iPhone remains the source of truth.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    ShareLink(item: exportText) {
                        Label("Export local data", systemImage: "square.and.arrow.up")
                    }
                    Text("Exports \(collectionName), reports, settings, and any transcript text you chose to save. The system share sheet controls where it goes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Delete saved transcripts", role: .destructive) {
                        showingDeleteTranscriptConfirmation = true
                    }
                    Text("Removes transcript text and evidence excerpts while preserving cue results, timing, and reports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Delete all session history", role: .destructive) {
                        showingDeleteHistoryConfirmation = true
                    }
                    Text("Removes saved reports, cue results, and any locally saved transcripts from this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Help") {
                    Button {
                        showingIssueReport = true
                    } label: {
                        Label("Report an issue", systemImage: "exclamationmark.bubble")
                    }
                    Text("Describe the problem and send it from the app. Your saved content and transcripts are not included automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingCoverageLab) {
                CoreCoverageLabView(sensitivity: $settings.sensitivity, replayCandidates: replayCandidates)
            }
            .sheet(isPresented: $showingSemanticLab) {
                NavigationStack { SemanticCoverageLabView(productName: productName) }
            }
            .sheet(isPresented: $showingIssueReport) {
                IssueReportView(productName: productName)
            }
            .alert("Delete all session history?", isPresented: $showingDeleteHistoryConfirmation) {
                Button("Delete all", role: .destructive) { deleteHistory() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes every saved report and transcript from this device. Your \(collectionName) will remain.")
            }
            .alert("Delete saved transcripts?", isPresented: $showingDeleteTranscriptConfirmation) {
                Button("Delete transcripts", role: .destructive) { deleteTranscripts() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Cue results and session history will remain, but saved transcript text and evidence excerpts cannot be recovered.")
            }
        }
    }
}

private struct IssueReportView: View {
    let productName: String
    @Environment(\.dismiss) private var dismiss
    @State private var problem = ""
    @State private var steps = ""
    @State private var expected = ""
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var submissionError: String?
    @State private var deliveryReady = false
    @State private var isCheckingDelivery = true

    private var report: IssueReport {
        IssueReport(
            product: productName,
            problem: problem.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: steps.trimmingCharacters(in: .whitespacesAndNewlines),
            expected: expected.trimmingCharacters(in: .whitespacesAndNewlines),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            device: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What went wrong?", text: $problem, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Steps to reproduce (optional)", text: $steps, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("What did you expect? (optional)", text: $expected, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Issue details")
                } footer: {
                    Text("Only these details and app/device versions will be sent. Do not include confidential matter details unless you choose to share them.")
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Label("Send report", systemImage: "paperplane")
                            if isSubmitting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(report.problem.isEmpty || isSubmitting || !deliveryReady)
                    if !deliveryReady {
                        Text(isCheckingDelivery ? "Checking report delivery…" : "Report delivery is unavailable. Check your connection and try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !isCheckingDelivery {
                            Button("Check again") { Task { await checkDelivery() } }
                        }
                    }
                }
            }
            .navigationTitle("Report an issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Report sent", isPresented: $didSubmit) {
                Button("Done") { dismiss() }
            } message: {
                Text("Thank you for reporting the issue.")
            }
            .alert("Could not send report", isPresented: Binding(
                get: { submissionError != nil },
                set: { if !$0 { submissionError = nil } }
            )) {
                Button("OK") { submissionError = nil }
            } message: {
                Text(submissionError ?? "Please try again.")
            }
            .task { await checkDelivery() }
        }
    }

    @MainActor private func checkDelivery() async {
        isCheckingDelivery = true
        deliveryReady = await IssueReportService.isAvailable()
        isCheckingDelivery = false
    }

    @MainActor private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await IssueReportService.submit(report)
            didSubmit = true
        } catch {
            submissionError = error.localizedDescription
        }
    }
}

private struct IssueReport: Encodable {
    let product: String
    let problem: String
    let steps: String
    let expected: String
    let appVersion: String
    let build: String
    let device: String
    let osVersion: String
}

private enum IssueReportService {
    static var endpointURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "IssueReportEndpoint") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    static func submit(_ report: IssueReport) async throws {
        guard let endpointURL else { throw SubmissionError.notConfigured }
        let body = try JSONEncoder().encode(report)
        guard body.count <= 12_000 else { throw SubmissionError.tooLong }
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw SubmissionError.rejected }
        switch httpResponse.statusCode {
        case 201:
            guard let receipt = try? JSONDecoder().decode(IssueReportReceipt.self, from: data),
                  UUID(uuidString: receipt.id) != nil else { throw SubmissionError.rejected }
            return
        case 429: throw SubmissionError.rateLimited
        default: throw SubmissionError.rejected
        }
    }

    static func isAvailable() async -> Bool {
        guard let endpointURL else { return false }
        var request = URLRequest(url: endpointURL)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let status = try? JSONDecoder().decode(IssueReportStatus.self, from: data) else { return false }
        return status.available
    }

    private struct IssueReportStatus: Decodable {
        let available: Bool
    }

    private struct IssueReportReceipt: Decodable {
        let id: String
    }

    private enum SubmissionError: LocalizedError {
        case notConfigured, tooLong, rateLimited, rejected

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Report delivery is not configured yet."
            case .tooLong: return "This report is too long to send. Please shorten the description or steps."
            case .rateLimited: return "Too many reports were sent from this network today. Please try again tomorrow."
            case .rejected: return "The report could not be accepted. Please try again later."
            }
        }
    }
}

struct CoreCoverageLabView: View {
    @Binding var sensitivity: String
    let replayCandidates: [CoreCoverageReplay]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReplayRunID: UUID?

    private var summary: CoverageLabSummary {
        coverageLabSummary(sensitivity: sensitivity)
    }

    private var selectedReplay: CoreCoverageReplay? {
        replayCandidates.first { $0.id == selectedReplayRunID }
    }

    private var replayResults: [CoverageReplayResult] {
        guard let selectedReplay else { return [] }
        return coverageReplayResults(presentation: selectedReplay.presentation, run: selectedReplay.run, sensitivity: sensitivity)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Local calibration") {
                    Picker("Sensitivity", selection: Binding(get: { sensitivity }, set: { sensitivity = $0 })) {
                        Text("Conservative").tag("Conservative")
                        Text("Balanced").tag("Balanced")
                        Text("Fast").tag("Fast")
                    }
                    Text("This setting affects future sessions. Historical reports are not rewritten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Precision", value: percent(summary.precision))
                    LabeledContent("Recall", value: percent(summary.recall))
                    LabeledContent("False completions", value: "\(summary.falsePositives) (\(percent(summary.falseCompletionRate)))")
                    LabeledContent("Fixture accuracy", value: "\(summary.results.filter(\.isCorrect).count)/\(summary.results.count)")
                }

                Section("Deterministic fixture results") {
                    ForEach(summary.results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(result.isCorrect ? Color.green : Color.orange)
                                Text(result.fixture.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(result.actualStatus.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(result.isCorrect ? Color.secondary : Color.orange)
                            }
                            Text("Expected \(result.fixture.expectedCovered ? "covered" : "not covered") · matched \(result.matchedTerms.isEmpty ? "none" : result.matchedTerms.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }

                Section("Replay a saved transcript") {
                    if replayCandidates.isEmpty {
                        Text("Enable Save transcript locally and complete a session to replay it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Saved run", selection: $selectedReplayRunID) {
                            ForEach(replayCandidates) { candidate in
                                Text("\(candidate.presentation.title) · \(candidate.run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .tag(Optional(candidate.id))
                            }
                        }
                        ForEach(replayResults) { result in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.cue.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Recorded: \(result.originalStatus.label) · Replayed: \(result.replayStatus.label)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if result.originalStatus != result.replayStatus {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundStyle(Color.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Coverage lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if selectedReplayRunID == nil {
                    selectedReplayRunID = replayCandidates.first?.id
                }
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}


enum SessionFeedback {
    static func cueCovered() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    static func manualChange() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}
