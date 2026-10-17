import SwiftUI
import UIKit

struct SemanticCoverageLabView: View {
    var productName = "Cue Complete"
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = OnDeviceCoverageService()
    @State private var rows: [SemanticLabResult] = []
    @State private var worker: Task<Void, Never>?
    @State private var running = false
    @State private var airplaneModeConfirmed = false
    @State private var transcript = ""
    @State private var assessment: SemanticCueAssessment?
    @State private var failure: String?

    private var cue: Cue { SemanticCoverageFixture.examples[0].cue }
    private var completed: [SemanticLabResult] { rows.filter { $0.covered != nil } }
    private var falseCompletions: Int { completed.filter { $0.covered == true && !$0.expected }.count }
    private var missedCompletions: Int { completed.filter { $0.covered == false && $0.expected }.count }
    private var report: String {
        (["\(productName) — on-device semantic evaluation",
          "Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)",
          "Airplane mode: \(airplaneModeConfirmed ? "user confirmed" : "not confirmed")",
          "Completed cases: \(completed.count)/\(SemanticCoverageFixture.examples.count)",
          "False completions: \(falseCompletions); missed completions: \(missedCompletions)",
          "These small fixtures are diagnostic, not proof of production accuracy."] + rows.map {
            "\($0.title): expected \($0.expected ? "covered" : "unfinished"), actual \($0.covered.map { $0 ? "covered" : "unfinished" } ?? "evaluation failed"), \(String(format: "%.2f", $0.duration))s"
        }).joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section("Local model") {
                Label(service.readiness.label, systemImage: "lock.shield")
                Text(service.readiness.explanation).font(.caption)
                Button("Check local model again") { Task { await service.prepare() } }
                    .disabled(running || service.readiness == .checking)
                Text("This lab calls the real local model. Simulator checklist progression is never used as a test result. Nothing entered here is saved by the lab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Airplane-mode check") {
                Toggle("I enabled airplane mode and turned Wi-Fi off", isOn: $airplaneModeConfirmed)
                Text("This records your confirmation; the app does not infer airplane mode. Prepare the model first, disable connectivity, then check the model again and run the cases.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Evaluation cases") {
                Button(running ? "Running local checks…" : "Run semantic cases") { runFixtures() }
                    .disabled(running || !service.readiness.canEvaluate)
                if running { ProgressView() }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.title)
                            Spacer()
                            Text(row.covered == nil ? "Failed" : (row.covered == row.expected ? "Pass" : "Mismatch"))
                                .foregroundStyle(row.covered == row.expected ? .green : .orange)
                        }
                        Text("\(String(format: "%.2f", row.duration)) seconds · \(row.note)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !rows.isEmpty {
                    Text("\(completed.count) evaluated · \(falseCompletions) false completions · \(missedCompletions) missed completions")
                    ShareLink("Share evaluation results", item: report)
                }
            }
            Section("Try your own phrasing") {
                Text("Cue: \(cue.title)")
                ForEach(cue.semanticRequirements, id: \.self) { Text($0).font(.caption) }
                TextEditor(text: $transcript).frame(minHeight: 120)
                    .accessibilityLabel("Test transcript")
                Button("Evaluate locally") { evaluateInput() }
                    .disabled(running || !service.readiness.canEvaluate || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Clear retained evidence") { assessment = nil }
                    .disabled(running)
                if let assessment {
                    Text(assessment.status == .covered ? "Covered" : "Unfinished")
                    Text(assessment.note).font(.caption)
                    ForEach(assessment.evidence.keys.sorted(), id: \.self) { index in
                        Text((assessment.evidence[index] ?? []).joined(separator: "\n")).font(.caption)
                    }
                }
                Text("Append speech in stages to check accumulation. Editing away earlier speech invalidates its evidence.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let failure { Section("Evaluation unavailable") { Text(failure) } }
        }
        .navigationTitle("On-device coverage lab")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await service.prepare() }
        .onDisappear { worker?.cancel() }
    }

    private func runFixtures() {
        rows = []
        failure = nil
        running = true
        worker = Task { @MainActor in
            defer { running = false }
            for fixture in SemanticCoverageFixture.examples {
                guard !Task.isCancelled else { return }
                let start = Date()
                do {
                    let result = try await service.evaluate(cue: fixture.cue, transcript: fixture.transcript)
                    try Task.checkCancellation()
                    rows.append(SemanticLabResult(title: fixture.id, expected: fixture.expectedCovered,
                        covered: result.status == .covered, duration: Date().timeIntervalSince(start), note: result.note + "\n" + (service.lastDiagnostic ?? "")))
                } catch is CancellationError { return }
                catch {
                    rows.append(SemanticLabResult(title: fixture.id, expected: fixture.expectedCovered,
                        covered: nil, duration: Date().timeIntervalSince(start), note: "Local evaluation failed; no accuracy result."))
                }
            }
        }
    }

    private func evaluateInput() {
        running = true
        failure = nil
        let input = transcript
        let previous = assessment?.evidence ?? [:]
        let previousMentions = assessment?.mentionedEvidence ?? [:]
        worker = Task { @MainActor in
            defer { running = false }
            do {
                let result = try await service.evaluate(cue: cue, transcript: input, previous: previous, previousMentions: previousMentions)
                try Task.checkCancellation()
                assessment = result
            } catch is CancellationError { return }
            catch { failure = (error as? SemanticServiceError)?.errorDescription ?? "The local model could not evaluate this input. No result was invented." }
        }
    }
}

private struct SemanticLabResult: Identifiable {
    var id: String { title }
    let title: String
    let expected: Bool
    let covered: Bool?
    let duration: TimeInterval
    let note: String
}
