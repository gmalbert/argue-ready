import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PDFKit
import Speech

@main
struct ArgueReadyApp: App {
    @StateObject private var store = LegalMatterStore()

    var body: some Scene {
        WindowGroup {
            LegalRootView()
                .environmentObject(store)
        }
    }
}

struct LegalMatterLibraryView: View {
    @EnvironmentObject private var store: LegalMatterStore
    @ObservedObject private var watchConnectivity = WatchConnectivityBridge.shared
    @State private var selectedMatter: LegalMatter?
    @State private var newMatter: LegalMatter?
    @State private var searchText = ""
    @State private var matterToDelete: LegalMatter?
    @State private var recovery: LegalRecoveryLaunch?

    private var filteredMatters: [LegalMatter] {
        guard !searchText.isEmpty else { return store.matters }
        return store.matters.filter {
            "\($0.title) \($0.court) \($0.docketNumber)".localizedCaseInsensitiveContains(searchText)
        }
    }

    private var recoverableMatter: LegalMatter? {
        guard let checkpoint = store.sessionCheckpoint else { return nil }
        return checkpoint.matterSnapshot ?? store.matters.first(where: { $0.id == checkpoint.matterID }) ?? (store.matters.count == 1 ? store.matters[0] : nil)
    }

    var body: some View {
        NavigationStack {
            List {
                if let checkpoint = store.sessionCheckpoint,
                   let matter = recoverableMatter {
                    Section("Resume") {
                        LegalRecoveryCard(checkpoint: checkpoint, matter: matter) {
                            store.clearSessionCheckpoint()
                            recovery = LegalRecoveryLaunch(matter: matter, checkpoint: checkpoint)
                        } onDismiss: {
                            store.clearSessionCheckpoint()
                        }
                    }
                }
                Section("Matters") {
                    ForEach(filteredMatters) { matter in
                        Button {
                            selectedMatter = matter
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(matter.title).font(.headline).foregroundStyle(.primary)
                                Text("\(matter.court) · \(matter.role) · \(matter.totalMinutes) min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        .contextMenu {
                            Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(matter) }
                            Button("Delete", systemImage: "trash", role: .destructive) { matterToDelete = matter }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { matterToDelete = matter }
                        }
                    }
                }
            }
            .overlay {
                if store.matters.isEmpty {
                    ContentUnavailableView("No matters yet", systemImage: "briefcase", description: Text("Use + to create your first argument plan."))
                } else if filteredMatters.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, prompt: "Search matters, courts, or docket numbers")
            .navigationTitle("Matters")
            .alert("Delete matter?", isPresented: Binding(get: { matterToDelete != nil }, set: { if !$0 { matterToDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    if let matterToDelete { store.delete(matterToDelete) }
                    matterToDelete = nil
                }
                Button("Cancel", role: .cancel) { matterToDelete = nil }
            } message: {
                Text("This removes the matter and its interrupted session. Saved rehearsal reports remain in History.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newMatter = LegalMatter(title: "New matter", court: "", docketNumber: "", role: "Appellant", totalMinutes: 20, rebuttalMinutes: 3, issues: [])
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New matter")
                }
            }
            .sheet(item: $selectedMatter) { matter in
                LegalMatterHomeView(matter: matter)
            }
            .sheet(item: $newMatter) { matter in
                LegalMatterEditorView(matter: matter) { store.upsert($0) }
            }
            .fullScreenCover(item: $recovery) { launch in
                LegalRehearsalView(matter: launch.matter, checkpoint: launch.checkpoint)
            }
        }
        .onAppear {
            watchConnectivity.activate()
            handleWatchStart(watchConnectivity.pendingCommand)
        }
        .onChange(of: watchConnectivity.pendingCommand) { _, command in
            handleWatchStart(command)
        }
    }

    private func handleWatchStart(_ command: WatchSessionCommand?) {
            guard command == .start, selectedMatter == nil, recovery == nil,
                  let snapshot = watchConnectivity.latestSnapshot, snapshot.canStart,
                  let matterID = snapshot.presentationID.flatMap(UUID.init(uuidString:)),
                  let matter = store.matters.first(where: { $0.id == matterID }) else { return }
            // The matter screen handles the command once it appears, preserving
            // the existing iPhone privacy preflight before speech starts.
            selectedMatter = matter
    }
}

private struct LegalRecoveryLaunch: Identifiable {
    let id = UUID()
    let matter: LegalMatter
    let checkpoint: LegalSessionCheckpoint
}

private struct LegalRecoveryCard: View {
    let checkpoint: LegalSessionCheckpoint
    let matter: LegalMatter
    let resume: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Resume interrupted rehearsal", systemImage: "arrow.clockwise.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            Text("\(matter.title) · \(formatLegalTime(checkpoint.elapsed)) elapsed")
                .font(.subheadline.weight(.semibold))
            Text("Cue states and timing were saved locally. Audio and transcript text were not saved in the checkpoint.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Resume", action: resume)
                    .buttonStyle(.borderedProminent)
                Button("Discard", role: .destructive, action: onDismiss)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }
}

struct LegalMatterHomeView: View {
    @EnvironmentObject private var store: LegalMatterStore
    @ObservedObject private var watchConnectivity = WatchConnectivityBridge.shared
    private let initialMatter: LegalMatter
    @State private var showingPlan = false
    @State private var showingRehearsal = false
    @State private var showingEditor = false
    @State private var showingPrivacyPreflight = false
    @State private var showingHistory = false
    @State private var startAfterPreflight = false

    init(matter: LegalMatter) { initialMatter = matter }

    private var matter: LegalMatter {
        store.matters.first(where: { $0.id == initialMatter.id }) ?? initialMatter
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ArgueReady")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Requirements, not scripts.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(matter.title)
                            .font(.title3.weight(.bold))
                        Text("\(matter.court) · \(matter.role) · \(matter.docketNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Label("\(matter.totalMinutes) min", systemImage: "clock")
                            Spacer()
                            Label("\(matter.rebuttalMinutes) min rebuttal", systemImage: "arrow.uturn.backward")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    }
                    .padding(18)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(spacing: 10) {
                        Button("Review argument plan") { showingPlan = true }
                            .buttonStyle(.borderedProminent)
                        Button("Start private rehearsal") { showingPrivacyPreflight = true }
                            .buttonStyle(.bordered)
                        if !store.runs(for: matter).isEmpty {
                            Button("Rehearsal history") { showingHistory = true }
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Text("Prepared material stays visible and counsel-controlled. ArgueReady does not generate legal advice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Matter")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showingEditor = true }
                }
            }
            .sheet(isPresented: $showingPlan) { LegalPlanView(matter: matter) }
            .fullScreenCover(isPresented: $showingRehearsal, onDismiss: sendWatchReadySnapshot) {
                LegalRehearsalView(matter: store.matters.first(where: { $0.id == matter.id }) ?? matter)
            }
            .sheet(isPresented: $showingEditor) {
                LegalMatterEditorView(matter: matter) { store.upsert($0) }
            }
            .sheet(isPresented: $showingHistory) {
                LegalRehearsalHistoryView(matter: matter)
            }
            .sheet(isPresented: $showingPrivacyPreflight, onDismiss: {
                if startAfterPreflight {
                    startAfterPreflight = false
                    showingRehearsal = true
                }
            }) {
                LegalPrivacyPreflightView(matter: matter) {
                    startAfterPreflight = true
                }
            }
        }
        .onAppear {
            sendWatchReadySnapshot()
            handleWatchStart()
        }
        .onChange(of: watchConnectivity.pendingCommand) { _, _ in
            handleWatchStart()
        }
        .onChange(of: store.matters) { _, _ in
            if !showingRehearsal { sendWatchReadySnapshot() }
        }
    }

    private func sendWatchReadySnapshot() {
        let current = store.matters.first(where: { $0.id == matter.id }) ?? matter
        watchConnectivity.send(snapshot: current.watchSnapshot(canStart: true))
    }

    private func handleWatchStart() {
        guard watchConnectivity.pendingCommand == .start,
              watchConnectivity.latestSnapshot?.presentationID == matter.id.uuidString,
              watchConnectivity.latestSnapshot?.canStart == true,
              !showingRehearsal else { return }
        watchConnectivity.clearPendingCommand()
        showingPrivacyPreflight = true
    }
}

struct LegalPrivacyPreflightView: View {
    @EnvironmentObject private var store: LegalMatterStore
    @Environment(\.dismiss) private var dismiss
    let matter: LegalMatter
    let start: () -> Void
    var dismissBeforeStarting = true
    @StateObject private var semantic = OnDeviceCoverageService()
    private var configuration: PresentationSessionConfiguration { matter.configuration(global: store.settings) }

    private var onDeviceSupport: Bool? {
        guard configuration.analysisMode == .onDeviceOnly else { return nil }
        return SFSpeechRecognizer(locale: Locale(identifier: matter.sessionPresentation.recognitionLocale.rawValue))?.supportsOnDeviceRecognition
    }

    private var recognitionPrivacyNotice: String {
        switch configuration.analysisMode {
        case .onDeviceOnly:
            switch onDeviceSupport {
            case true:
                return "On-device only is available for this device and language. If Apple reports a different capability when rehearsal starts, ArgueReady will stop and explain; it will not switch to network processing."
            case false:
                return "On-device only is not available for this device and language. Speech recognition will not start in this mode. You can continue with manual checklist controls; no network fallback will be used."
            case nil:
                return "ArgueReady will check this device and language before recognition starts. If unavailable, it will stop instead of switching to network processing."
            }
        case .hybrid:
            return "Hybrid is an explicit privacy choice. If on-device recognition is unavailable, Apple’s network-assisted speech recognition may be used."
        }
    }

    private var recognitionPrivacyColor: Color {
        onDeviceSupport == false ? .orange : .blue
    }

    private var recognitionPrivacyIcon: String {
        onDeviceSupport == false ? "exclamationmark.triangle.fill" : "lock.shield.fill"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Before rehearsal") {
                    LabeledContent("Matter", value: matter.title)
                    if matter.isPracticeDrill {
                        Label("Focused practice · \(matter.requiredLeafRequirements.count) unfinished points", systemImage: "arrow.clockwise")
                    }
                    Label(configuration.analysisMode.title, systemImage: configuration.analysisMode == .onDeviceOnly ? "iphone" : "network")
                    Text(configuration.analysisMode.detail).font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Recognition language", value: matter.sessionPresentation.recognitionLocale.title)
                    LabeledContent("Transcript saving", value: configuration.saveTranscript ? "Saved locally with report" : "Off")
                    Label("No raw audio saved", systemImage: "waveform.slash")
                    Label("No recording by default", systemImage: "record.circle")
                    Label("Watch receives checklist state only", systemImage: "applewatch")
                    Label("Prepared material remains counsel-controlled", systemImage: "lock.shield")
                    Text("The Watch never receives audio, transcript text, authorities, or record citations. Rehearsal speech and any saved transcript remain governed by the iPhone privacy settings shown above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Recognition privacy check") {
                    Label("\(configuration.analysisMode.title) status", systemImage: recognitionPrivacyIcon)
                        .foregroundStyle(recognitionPrivacyColor)
                    Text(recognitionPrivacyNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Coverage readiness") {
                        Label(semantic.readiness.label, systemImage: "brain")
                        Text(semantic.readiness.explanation).font(.caption).foregroundStyle(.secondary)
                        Button("Check local model again") { Task { await semantic.prepare() } }
                            .disabled(semantic.readiness == .checking)
                    }
            }
            .task { await semantic.prepare() }
            .navigationTitle("Privacy preflight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        if dismissBeforeStarting { dismiss() }
                        start()
                    }
                    .disabled(semantic.readiness == .checking)
                }
            }
        }
    }
}

struct LegalMatterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let initialMatter: LegalMatter
    let saveMatter: (LegalMatter) -> Void
    @State private var title: String
    @State private var court: String
    @State private var docketNumber: String
    @State private var role: String
    @State private var totalMinutes: Int
    @State private var rebuttalMinutes: Int
    @State private var standardOfReview: String
    @State private var proceduralHistory: String
    @State private var requestedRelief: String
    @State private var issues: [LegalIssue]
    @State private var authorities: [AuthorityCard]
    @State private var recordCitations: [RecordCitationCard]
    @State private var likelyQuestions: [PreparedQuestion]
    @State private var contextCards: [LegalContextCard]
    @State private var preferences: LegalSessionPreferences
    @State private var importedRequirements: [String]
    @State private var showingDocumentImporter = false
    @State private var importError: String?

    init(matter: LegalMatter, saveMatter: @escaping (LegalMatter) -> Void) {
        initialMatter = matter
        self.saveMatter = saveMatter
        _title = State(initialValue: matter.title)
        _court = State(initialValue: matter.court)
        _docketNumber = State(initialValue: matter.docketNumber)
        _role = State(initialValue: matter.role)
        _totalMinutes = State(initialValue: matter.totalMinutes)
        _rebuttalMinutes = State(initialValue: matter.rebuttalMinutes)
        _standardOfReview = State(initialValue: matter.standardOfReview)
        _proceduralHistory = State(initialValue: matter.proceduralHistory)
        _requestedRelief = State(initialValue: matter.requestedRelief)
        _issues = State(initialValue: matter.issues.isEmpty
            ? [LegalIssue(title: "Primary issue", shortLabel: "Issue I", requirements: [LegalRequirement(title: "Primary proposition")])]
            : matter.issues)
        _authorities = State(initialValue: matter.issues.first?.authorities ?? [])
        _recordCitations = State(initialValue: matter.issues.first?.recordCitations ?? [])
        _likelyQuestions = State(initialValue: matter.issues.first?.likelyQuestions ?? [])
        _contextCards = State(initialValue: matter.issues.first?.contextCards ?? [])
        _preferences = State(initialValue: matter.sessionPreferences)
        _importedRequirements = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Matter") {
                    TextField("Matter title", text: $title)
                    TextField("Court", text: $court)
                    TextField("Docket number", text: $docketNumber)
                    TextField("Role", text: $role)
                }
                Section("Time") {
                    Stepper("Argument: \(totalMinutes) min", value: $totalMinutes, in: 1...180)
                    Stepper("Rebuttal reserve: \(rebuttalMinutes) min", value: $rebuttalMinutes, in: 0...totalMinutes)
                }
                Section("Argument context") {
                    TextField("Standard of review", text: $standardOfReview)
                    TextEditor(text: $proceduralHistory)
                        .frame(minHeight: 70)
                        .overlay(alignment: .topLeading) {
                            if proceduralHistory.isEmpty {
                                Text("Procedural history (optional)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                    TextEditor(text: $requestedRelief)
                        .frame(minHeight: 70)
                        .overlay(alignment: .topLeading) {
                            if requestedRelief.isEmpty {
                                Text("Requested relief (optional)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                ForEach($issues) { $issue in
                    Section("Argument points · " + issue.shortLabel) {
                        TextField("Issue title", text: $issue.title)
                        ForEach($issue.requirements) { $requirement in
                            LegalRequirementEditor(requirement: $requirement)
                        }
                        .onDelete { issue.requirements.remove(atOffsets: $0) }
                        Button {
                            issue.requirements.append(LegalRequirement(title: ""))
                        } label: {
                            Label("Add argument point", systemImage: "plus.circle")
                        }
                        Text("Write what you need to explain, the facts that support it, and how to move to the next point. These notes appear during rehearsal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Authorities") {
                    ForEach($authorities) { $authority in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Citation", text: $authority.citation)
                            TextField("Proposition", text: $authority.proposition, axis: .vertical)
                            TextField("Caution (optional)", text: $authority.caution, axis: .vertical)
                        }
                    }
                    .onDelete { authorities.remove(atOffsets: $0) }
                    Button { authorities.append(AuthorityCard(citation: "", proposition: "")) } label: {
                        Label("Add authority", systemImage: "plus.circle")
                    }
                }
                Section("Record citations") {
                    ForEach($recordCitations) { $citation in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Label", text: $citation.label)
                            TextField("Citation", text: $citation.citation)
                            TextField("Proposition", text: $citation.proposition, axis: .vertical)
                        }
                    }
                    .onDelete { recordCitations.remove(atOffsets: $0) }
                    Button { recordCitations.append(RecordCitationCard(label: "", citation: "", proposition: "")) } label: {
                        Label("Add record citation", systemImage: "plus.circle")
                    }
                }
                Section("Prepared questions") {
                    ForEach($likelyQuestions) { $question in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Topic", text: $question.topic)
                            TextField("Question", text: $question.question, axis: .vertical)
                            TextField("Prepared response", text: $question.response, axis: .vertical)
                        }
                    }
                    .onDelete { likelyQuestions.remove(atOffsets: $0) }
                    Button { likelyQuestions.append(PreparedQuestion(question: "", topic: "", response: "")) } label: {
                        Label("Add prepared question", systemImage: "plus.circle")
                    }
                }
                Section("Context and guardrails") {
                    ForEach($contextCards) { $card in
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Type", selection: $card.kind) {
                                ForEach(LegalContextCardKind.allCases) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }
                            TextField("Card title", text: $card.title)
                            TextField("Card text", text: $card.body, axis: .vertical)
                            TextField("Source (optional)", text: $card.source)
                        }
                    }
                    .onDelete { contextCards.remove(atOffsets: $0) }
                    Button { contextCards.append(LegalContextCard(kind: .transition, title: "", body: "")) } label: {
                        Label("Add context card", systemImage: "plus.circle")
                    }
                }
                LegalSessionDefaultsSection(preferences: $preferences)

                Section("Review imported requirements") {
                    Button {
                        showingDocumentImporter = true
                    } label: {
                        Label("Import brief or notes", systemImage: "doc.badge.plus")
                    }
                    ForEach($importedRequirements, id: \.self) { $candidate in
                        TextField("Candidate requirement", text: $candidate, axis: .vertical)
                    }
                    .onDelete { importedRequirements.remove(atOffsets: $0) }
                    if importedRequirements.isEmpty {
                        Text("Imported text appears here for review. Candidates are not added to the live plan until you save the matter.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit matter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || issues.flatMap(\.leafRequirements).contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
            }
            .fileImporter(
                isPresented: $showingDocumentImporter,
                allowedContentTypes: [.plainText, .pdf, UTType(filenameExtension: "md") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importRequirements(from: url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Could not import document", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "Try a plain-text or Markdown file.")
            }
        }
    }

    private func save() {
        var updatedIssues = issues
        if !updatedIssues.isEmpty {
            updatedIssues[0].authorities = authorities
            updatedIssues[0].recordCitations = recordCitations
            updatedIssues[0].likelyQuestions = likelyQuestions
            updatedIssues[0].contextCards = contextCards
            updatedIssues[0].requirements.append(contentsOf: importedRequirementModels)
        }
        let updated = LegalMatter(
            id: initialMatter.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            court: court,
            docketNumber: docketNumber,
            role: role,
            totalMinutes: totalMinutes,
            rebuttalMinutes: min(rebuttalMinutes, totalMinutes),
            standardOfReview: standardOfReview,
            proceduralHistory: proceduralHistory,
            requestedRelief: requestedRelief,
            issues: updatedIssues,
            sessionPreferences: preferences
        )
        saveMatter(updated)
        dismiss()
    }

    private var importedRequirementModels: [LegalRequirement] {
        importedRequirements.compactMap { value in
            let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : LegalRequirement(title: title)
        }
    }

    private func importRequirements(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text: String
            if url.pathExtension.lowercased() == "pdf" {
                guard let document = PDFDocument(url: url), let extracted = document.string else {
                    importError = "That PDF did not contain extractable text."
                    return
                }
                text = extracted
            } else {
                text = try String(contentsOf: url, encoding: .utf8)
            }
            let candidates = legalRequirementCandidates(from: text)
            guard !candidates.isEmpty else {
                importError = "No requirement-like lines were found in that document."
                return
            }
            importedRequirements.append(contentsOf: candidates)
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct LegalRequirementEditor: View {
    @Binding var requirement: LegalRequirement

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Point title", text: $requirement.title, axis: .vertical)
                .font(.headline)
            TextField("Speaking notes: what to explain and how to support it", text: $requirement.detail, axis: .vertical)
                .lineLimit(3...10)
            if requirement.children.isEmpty {
                Toggle("Required point", isOn: $requirement.isRequired)
            }
            if !requirement.children.isEmpty {
                DisclosureGroup("Supporting points (\(requirement.children.count))") {
                    ForEach($requirement.children) { $child in
                        LegalRequirementEditor(requirement: $child)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct LegalPlanView: View {
    let matter: LegalMatter

    var body: some View {
        NavigationStack {
            List {
                Section("Issue tree") {
                    ForEach(matter.issues) { issue in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(issue.shortLabel + " — " + issue.title)
                                .font(.headline)
                            ForEach(issue.requirements) { requirement in
                                LegalRequirementRow(requirement: requirement, level: 0)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                Section("Matter context") {
                    if !matter.standardOfReview.isEmpty {
                        LegalPlanFactRow(label: "Standard of review", value: matter.standardOfReview)
                    }
                    if !matter.proceduralHistory.isEmpty {
                        LegalPlanFactRow(label: "Procedural history", value: matter.proceduralHistory)
                    }
                    if !matter.requestedRelief.isEmpty {
                        LegalPlanFactRow(label: "Requested relief", value: matter.requestedRelief)
                    }
                    if matter.standardOfReview.isEmpty && matter.proceduralHistory.isEmpty && matter.requestedRelief.isEmpty {
                        Text("Add counsel-owned context in Edit matter.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Context cards") {
                    if matter.contextCards.isEmpty {
                        Text("No context cards have been prepared for this matter.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(matter.contextCards) { card in
                            VStack(alignment: .leading, spacing: 5) {
                                Label(card.title, systemImage: card.kind.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(card.kind == .danger ? .orange : .blue)
                                Text(card.body)
                                    .font(.caption)
                                if !card.source.isEmpty {
                                    Text(card.source)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                Section("Authorities") {
                    ForEach(matter.authorities) { authority in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authority.citation).font(.subheadline.weight(.bold))
                            Text(authority.proposition).font(.caption)
                            if !authority.caution.isEmpty { Text("⚠ " + authority.caution).font(.caption).foregroundStyle(.orange) }
                        }
                    }
                }
                Section("Record") {
                    ForEach(matter.recordCitations) { citation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(citation.label + " · " + citation.citation).font(.subheadline.weight(.bold))
                            Text(citation.proposition).font(.caption)
                        }
                    }
                }
                Section("Prepared questions") {
                    ForEach(matter.likelyQuestions) { question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.topic.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.blue)
                            Text(question.question).font(.subheadline.weight(.semibold))
                            Text(question.response).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Argument plan")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct LegalPlanFactRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.blue)
            Text(value)
                .font(.subheadline)
        }
    }
}

struct LegalRequirementRow: View {
    let requirement: LegalRequirement
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(requirement.title, systemImage: requirement.children.isEmpty ? "circle" : "chevron.down")
                .font(.subheadline.weight(requirement.children.isEmpty ? .regular : .semibold))
                .padding(.leading, CGFloat(level * 16))
            if !requirement.detail.isEmpty {
                Text(requirement.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, CGFloat(level * 16 + 24))
            }
            ForEach(requirement.children) { child in
                LegalRequirementRow(requirement: child, level: level + 1)
            }
        }
    }
}

struct LegalRehearsalView: View {
    @EnvironmentObject private var store: LegalMatterStore
    @Environment(\.dismiss) private var dismiss
    let matter: LegalMatter
    @StateObject private var speech = SpeechSession()
    @ObservedObject private var watchConnectivity = WatchConnectivityBridge.shared
    @State private var elapsed = 0
    @State private var isPaused = false
    @State private var isQuestionMode = false
    @State private var bookmarkedRequirement: UUID?
    @State private var selectedRequirementID: UUID?
    @State private var results: [CueResult]
    @State private var showingEndConfirmation = false
    @State private var showingReport = false
    @State private var sessionStartedAt: Date
    @State private var hasEnded = false
    @State private var configuration: PresentationSessionConfiguration?
    @StateObject private var semantic = OnDeviceCoverageService()
    @State private var semanticMemory: [UUID: [Int: [String]]] = [:]
    @State private var semanticMentions: [UUID: [Int: [String]]] = [:]
    @State private var liveEvidence: [UUID: String] = [:]
    @State private var restoredCoveredCueIDs = Set<UUID>()
    @State private var finisher = SemanticSessionFinisher()
    @State private var semanticTask: Task<Void, Never>?
    @State private var semanticGeneration = UUID()
    @State private var reviewSchedule = SemanticReviewSchedule()
    @State private var reviewDebounceTask: Task<Void, Never>?
    @State private var lastTranscriptChange = Date.distantPast
    @State private var lastLiveReviewStarted = Date.distantPast
    @State private var isFinishing = false
    @State private var warningHapticSent = false
    @State private var finishedRun: LegalRehearsalRun?


    init(matter: LegalMatter, checkpoint: LegalSessionCheckpoint? = nil) {
        let plan = checkpoint?.matterSnapshot ?? matter
        self.matter = plan
        _restoredCoveredCueIDs = State(initialValue: Set(checkpoint?.results.filter { $0.status == .covered && !$0.wasManualOverride }.map(\.cueID) ?? []))
        _elapsed = State(initialValue: checkpoint?.elapsed ?? 0)
        _isQuestionMode = State(initialValue: checkpoint?.isQuestionMode ?? false)
        _bookmarkedRequirement = State(initialValue: checkpoint?.bookmarkedRequirement)
        _selectedRequirementID = State(initialValue: checkpoint?.isQuestionMode == true ? checkpoint?.bookmarkedRequirement : nil)
        _sessionStartedAt = State(initialValue: checkpoint?.startedAt ?? .now)
        _results = State(initialValue: plan.leafRequirements.map { requirement in
            checkpoint?.results.first(where: { $0.cueID == requirement.id }) ?? CueResult(cueID: requirement.id)
        })
    }

    private var requirements: [LegalRequirement] { matter.leafRequirements }
    private var recommendedRequirementID: UUID? {
        legalNextRequirementID(requirements: requirements, results: results)
    }
    private var focusedRequirementID: UUID? { selectedRequirementID ?? recommendedRequirementID }
    private var focusedIndex: Int? { requirements.firstIndex { $0.id == focusedRequirementID } }
    private var requiredCount: Int { matter.requiredLeafRequirements.count }
    private var coveredCount: Int {
        results.enumerated().filter { index, result in
            index < requirements.count && requirements[index].isRequired && (result.status == .covered || result.status == .manual)
        }.count
    }
    private var rebuttalStartsAt: Int { max(0, matter.totalMinutes * 60 - matter.rebuttalMinutes * 60) }
    private var activeQuestion: PreparedQuestion? {
        matter.likelyQuestions.first { question in
            let words = question.topic.lowercased().split(separator: " ").map(String.init)
            return words.contains { speech.transcript.lowercased().contains($0) }
        } ?? matter.likelyQuestions.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Button { showingEndConfirmation = true } label: { Image(systemName: "xmark") }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(formatLegalTime(max(0, matter.totalMinutes * 60 - elapsed)))
                                .font(.title2.weight(.bold).monospacedDigit())
                            Text("argument time left")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(formatLegalTime(max(0, matter.rebuttalMinutes * 60 - max(0, elapsed - rebuttalStartsAt))))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.orange)
                            Text("rebuttal reserve")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)

                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(matter.title)
                                            .font(.headline)
                                    Text("\(coveredCount)/\(requiredCount) required satisfied")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(speech.isSimulator ? "Demo" : speech.state.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.blue)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Label(speech.isSimulator ? "Demo coverage" : semantic.readiness.label, systemImage: "brain")
                                    Text(speech.isSimulator ? "Simulator progression is a demo, not a model accuracy result." : semantic.readiness.explanation)
                                    if semantic.isEvaluating { ProgressView("Reviewing captured speech…") }
                                    if let failure = semantic.failureMessage { Text(failure).foregroundStyle(.orange) }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                                if isFinishing {
                                    ProgressView("Finishing local review…")
                                    Button("Save report now") { finisher.finishNow() }
                                }

                                if isQuestionMode, let activeQuestion {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label("Bench question · \(activeQuestion.topic)", systemImage: "questionmark.bubble.fill")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.blue)
                                        Text(activeQuestion.question)
                                            .font(.subheadline.weight(.semibold))
                                        Text(activeQuestion.response)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(14)
                                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                                }

                                if let focusedIndex {
                                    LegalArgumentGuideCard(
                                        matter: matter, requirement: requirements[focusedIndex],
                                        position: focusedIndex + 1, count: requirements.count,
                                        isRecommended: focusedRequirementID == recommendedRequirementID,
                                        hasUnaddressedPoints: recommendedRequirementID != nil,
                                        hasPrevious: focusedIndex > 0, hasNext: focusedIndex + 1 < requirements.count,
                                        previous: { moveGuidance(by: -1) }, next: { moveGuidance(by: 1) },
                                        followNext: { selectedRequirementID = nil }
                                    )
                                    .id("argument-guidance")
                                } else {
                                    Label(requirements.isEmpty ? "Add argument points in Edit matter to begin a guided rehearsal." : "All points addressed. Tap any point below to review its notes.", systemImage: requirements.isEmpty ? "text.badge.plus" : "checkmark.seal.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.green)
                                }

                                if speech.showsLowConfidenceWarning {
                                    Label("Speech confidence is low. Check recognition and use manual controls as needed.", systemImage: "waveform.badge.exclamationmark")
                                        .font(.caption).foregroundStyle(.orange)
                                }

                                if configuration?.showTranscript == true {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Transcript preview").font(.caption.weight(.semibold))
                                        Text(speech.transcript.isEmpty ? "Listening…" : String(speech.transcript.suffix(600)))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }

                                if let failureReason = speech.failureReason {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "mic.slash.fill")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(failureReason)
                                            Button("Try again") { Task { await restartSpeech() } }.disabled(isPaused || hasEnded)
                                                .font(.caption.weight(.bold))
                                        }
                                        Spacer()
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .padding(12)
                                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                }

                                if elapsed >= rebuttalStartsAt {
                                    Label("Rebuttal reserve is active", systemImage: "arrow.uturn.backward.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .padding(12)
                                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                }

                                if let bookmarkedRequirement,
                                   let bookmark = requirements.first(where: { $0.id == bookmarkedRequirement }) {
                                    Button {
                                        selectedRequirementID = bookmark.id
                                        isQuestionMode = false
                                        withAnimation { scrollProxy.scrollTo("argument-guidance", anchor: .top) }
                                    } label: {
                                        Label("Return to: \(bookmark.title)", systemImage: "bookmark.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.purple)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text("Argument points")
                                    .font(.headline)
                                Text("Tap a point for guidance. Use its circle to mark it addressed.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(Array(requirements.enumerated()), id: \.element.id) { index, requirement in
                                    LegalLiveRequirementRow(
                                        requirement: requirement, result: results[index],
                                        isSelected: requirement.id == focusedRequirementID,
                                        showGuidance: {
                                            selectedRequirementID = requirement.id
                                            withAnimation { scrollProxy.scrollTo("argument-guidance", anchor: .top) }
                                        },
                                        toggleCoverage: { toggle(index: index) }
                                    )
                                }
                            }
                            .padding(16)
                        }
                    }

                    HStack(spacing: 8) {
                        Button { togglePause() } label: {
                            Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        }
                        Button {
                            if !isQuestionMode {
                                bookmarkCurrent()
                                selectedRequirementID = bookmarkedRequirement
                            } else {
                                selectedRequirementID = bookmarkedRequirement
                            }
                            isQuestionMode.toggle()
                        } label: {
                            Label(isQuestionMode ? "Argument" : "Question", systemImage: "questionmark.bubble")
                        }
                        Button { bookmarkCurrent() } label: {
                            Label("Bookmark", systemImage: "bookmark")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .padding(12)
                }
            }
            .navigationTitle(matter.isPracticeDrill ? "Focused practice" : "Rehearsal")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("End rehearsal?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
                Button("End rehearsal") { endRehearsal() }
                Button("Keep speaking", role: .cancel) { }
            }
            .sheet(isPresented: $showingReport) {
                if let finishedRun {
                    LegalRehearsalReportView(matter: matter, run: finishedRun, transientTranscript: speech.transcript) {
                        showingReport = false
                        dismiss()
                    }
                }
            }
            .task {
                guard !hasEnded else { return }
                configuration = matter.configuration(global: store.settings)
                UIApplication.shared.isIdleTimerDisabled = configuration?.keepScreenAwake == true
                saveCheckpoint()
                sendWatchSnapshot()
                await semantic.prepare()
                guard !hasEnded else { return }
                await restartSpeech()
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                speech.stop()
                cancelSemanticWork()
                finisher.cancel()
                if !hasEnded { sendWatchSnapshot(isActive: false) }
            }
            .onChange(of: speech.transcript) { _, _ in
                lastTranscriptChange = .now
                scheduleLiveCoverage()
            }
            .onChange(of: speech.showsLowConfidenceWarning) { _, warning in
                if !warning, !isPaused { reviewSchedule.retry() }
            }
            .onChange(of: elapsed) { _, _ in sendWatchSnapshot() }
            .onChange(of: results) { oldResults, newResults in
                if !isQuestionMode, let selectedRequirementID,
                   let oldResult = oldResults.first(where: { $0.cueID == selectedRequirementID }),
                   let newResult = newResults.first(where: { $0.cueID == selectedRequirementID }),
                   oldResult.status != newResult.status,
                   newResult.status == .covered || newResult.status == .manual {
                    self.selectedRequirementID = nil
                }
                sendWatchSnapshot()
            }
            .onChange(of: isPaused) { _, _ in sendWatchSnapshot() }
            .onChange(of: watchConnectivity.pendingCommand) { _, command in
                guard !hasEnded, let command else { return }
                watchConnectivity.clearPendingCommand()
                switch command {
                case .start: break
                case .pause: if !isPaused { togglePause() }
                case .resume: if isPaused { togglePause() }
                case .end: endRehearsal()
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                guard !hasEnded else { return }
                if !speech.isSimulator {
                    let now = Date()
                    if isPaused || SemanticReviewSchedule.shouldReviewLive(
                        now: now, lastTranscriptChange: lastTranscriptChange,
                        lastReviewStarted: lastLiveReviewStarted) {
                        applyCoverage()
                    }
                }
                guard !isPaused else { return }
                elapsed += 1
                let previousCoveredCount = coveredCount
                if speech.isSimulator { simulateCoverage() }
                if configuration?.hapticsEnabled == true {
                    if coveredCount > previousCoveredCount { SessionFeedback.cueCovered() }
                    if elapsed >= rebuttalStartsAt, !warningHapticSent {
                        SessionFeedback.warning()
                        warningHapticSent = true
                    }
                }
                saveCheckpoint()
            }
        }
    }

    private func toggle(index: Int) {
        results[index].status = results[index].status == .manual || results[index].status == .covered ? .open : .manual
        results[index].wasManualOverride = true
        results[index].completionSeconds = results[index].status == .manual ? elapsed : nil
        semanticMemory[requirements[index].id] = nil
        semanticMentions[requirements[index].id] = nil
        liveEvidence[requirements[index].id] = nil
        restoredCoveredCueIDs.remove(requirements[index].id)
        results[index].evidenceSnippet = nil
        results[index].semanticNote = nil
        if configuration?.hapticsEnabled == true { SessionFeedback.manualChange() }
        saveCheckpoint()
    }

    private func togglePause() {
        guard !hasEnded else { return }
        isPaused.toggle()
        UIApplication.shared.isIdleTimerDisabled = !isPaused && configuration?.keepScreenAwake == true
        if isPaused {
            reviewSchedule.pause(lowConfidence: speech.showsLowConfidenceWarning)
            speech.stop()
            applyCoverage()
        } else {
            reviewSchedule.resume()
            Task { await restartSpeech() }
        }
        saveCheckpoint()
    }

    private func bookmarkCurrent() {
        bookmarkedRequirement = focusedRequirementID
        saveCheckpoint()
    }

    private func moveGuidance(by offset: Int) {
        guard let focusedIndex, requirements.indices.contains(focusedIndex + offset) else { return }
        selectedRequirementID = requirements[focusedIndex + offset].id
    }

    private func simulateCoverage() {
        guard let index = results.firstIndex(where: { $0.status == .open && !$0.wasManualOverride }), elapsed >= max(4, index * 4 + 4) else { return }
        results[index].status = .covered
        results[index].completionSeconds = elapsed
    }

    private func cancelSemanticWork() {
        reviewDebounceTask?.cancel()
        reviewDebounceTask = nil
        semanticGeneration = UUID()
        semanticTask?.cancel()
        semanticTask = nil
        // Cancellation does not guarantee that the model has already stopped. Do
        // not treat that snapshot as processed when listening resumes.
        reviewSchedule.retry()
    }

    private func scheduleLiveCoverage() {
        reviewDebounceTask?.cancel()
        guard !isPaused, !hasEnded else { return }
        reviewDebounceTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            if SemanticReviewSchedule.shouldReviewLive(now: .now, lastTranscriptChange: lastTranscriptChange,
                                                       lastReviewStarted: lastLiveReviewStarted) {
                applyCoverage()
            }
        }
    }

    private func applyCoverage() {
        guard results.contains(where: SemanticSessionCoverage.shouldEvaluate), !speech.isSimulator, let snapshot = reviewSchedule.next(transcript: speech.transcript,
            lowConfidence: speech.showsLowConfidenceWarning, canEvaluate: semantic.readiness.canEvaluate,
            busy: semanticTask != nil || semantic.isEvaluating, coolingDown: semantic.isCoolingDown,
            finishing: isFinishing) else { return }
        lastLiveReviewStarted = .now
        let generation = semanticGeneration
        semanticTask = Task { @MainActor in
            await evaluateSemanticCues(transcript: snapshot.transcript, generation: generation,
                lowConfidence: snapshot.lowConfidence)
            if semanticGeneration == generation {
                semanticTask = nil
                // Review the latest revision after an older in-flight check completes.
                // Cooldown and unchanged-snapshot guards prevent a busy retry loop.
                applyCoverage()
            }
        }
    }

    private func evaluateSemanticCues(transcript: String, generation: UUID, lowConfidence: Bool = false) async {
        for index in SemanticSessionCoverage.pendingIndices(in: results) {
            guard !Task.isCancelled, semanticGeneration == generation else { return }
            guard SemanticSessionCoverage.shouldEvaluate(results[index]) else { continue }
            let cue = requirements[index].cue
            do {
                let assessment = try await semantic.evaluate(cue: cue, transcript: transcript,
                    previous: semanticMemory[cue.id] ?? [:], previousMentions: semanticMentions[cue.id] ?? [:],
                    lowSpeechConfidence: lowConfidence || reviewSchedule.confidence(live: speech.showsLowConfidenceWarning))
                guard !Task.isCancelled, semanticGeneration == generation,
                      SemanticSessionCoverage.shouldEvaluate(results[index]) else { continue }
                let grounded = assessment.evidence.mapValues { quotes in
                    quotes.compactMap { SemanticEvidenceGate.groundedQuote($0, in: speech.transcript) }
                }.filter { !$0.value.isEmpty }
                let mentions = assessment.mentionedEvidence.mapValues { quotes in
                    quotes.compactMap { SemanticEvidenceGate.groundedQuote($0, in: speech.transcript) }
                }.filter { !$0.value.isEmpty }
                let evidenceChanged = assessment.evidence.contains { grounded[$0.key]?.count != $0.value.count }
                semanticMemory[cue.id] = grounded
                semanticMentions[cue.id] = mentions
                liveEvidence[cue.id] = Array(Set(grounded.values.flatMap { $0 } + mentions.values.flatMap { $0 })).sorted().joined(separator: "\n")
                let previousStatus = results[index].status
                let blocked = evidenceChanged || lowConfidence || reviewSchedule.confidence(live: speech.showsLowConfidenceWarning)
                let hasMention = !grounded.isEmpty || !mentions.isEmpty
                results[index].status = blocked ? (hasMention ? .emerging : .open)
                    : (assessment.status == .emerging && !hasMention ? .open : assessment.status)
                results[index].semanticNote = blocked ? "Speech evidence changed or is unclear; awaiting another local check." : assessment.note
                results[index].coverageMethod = "On-device semantic coverage"
                // Model scores are not calibrated confidence percentages.
                results[index].depthScore = nil
                results[index].evidenceSnippet = configuration?.saveTranscript == true ? liveEvidence[cue.id] : nil
                if results[index].status != .open, results[index].firstMentionSeconds == nil {
                    results[index].firstMentionSeconds = elapsed
                }
                if results[index].status == .covered {
                    if results[index].completionSeconds == nil { results[index].completionSeconds = elapsed }
                    if previousStatus != .covered, configuration?.hapticsEnabled == true { SessionFeedback.cueCovered() }
                } else {
                    results[index].completionSeconds = nil
                }
                saveCheckpoint()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, semanticGeneration == generation else { return }
                guard SemanticSessionCoverage.shouldEvaluate(results[index]) else { continue }
                results[index].semanticNote = (error as? SemanticServiceError)?.errorDescription
                    ?? "Local evaluation unavailable; this cue was not automatically updated."
                if semantic.isCoolingDown {
                    // Retry the latest speech when the deadline expires, even if
                    // the presenter says nothing else. Do not hammer other cues.
                    reviewSchedule.retry()
                    return
                }
            }
        }
    }

    private func endRehearsal() {
        guard !hasEnded else { return }
        hasEnded = true
        isFinishing = true
        isPaused = true
        let lowConfidence = reviewSchedule.confidence(live: speech.showsLowConfidenceWarning)
        speech.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        let pending = semanticTask
        cancelSemanticWork()
        let generation = semanticGeneration
        finisher.start(check: {
            await pending?.value
            guard !Task.isCancelled, semanticGeneration == generation else { return }
            if !speech.isSimulator, semantic.readiness.canEvaluate, !speech.transcript.isEmpty {
                await evaluateSemanticCues(transcript: speech.transcript, generation: generation, lowConfidence: lowConfidence)
            }
        }, completion: { interrupted in
            guard finishedRun == nil else { return }
            if interrupted {
                cancelSemanticWork()
                for index in SemanticSessionCoverage.pendingIndices(in: results) {
                    results[index].semanticNote = (results[index].semanticNote.map { $0 + " " } ?? "") + "Saved before final coverage review completed."
                }
            }
            saveFinishedRun()
        })
    }

    private func saveFinishedRun() {
        let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedResults = results.map { result in
            var saved = result
            if configuration?.saveTranscript != true { saved.evidenceSnippet = nil }
            return saved
        }
        let run = LegalRehearsalRun(matterID: matter.id, startedAt: sessionStartedAt, durationSeconds: elapsed,
                                   results: savedResults, transcript: configuration?.saveTranscript == true && !transcript.isEmpty ? transcript : nil,
                                   matterSnapshot: matter, wordCount: transcript.split(whereSeparator: { $0.isWhitespace }).count,
                                   fillerCount: fillerWordCount(in: transcript))
        finishedRun = run
        store.addRun(run)
        store.clearSessionCheckpoint()
        isFinishing = false
        showingReport = true
        sendWatchSnapshot(isActive: false)
    }

    private func sendWatchSnapshot(isActive: Bool = true) {
        watchConnectivity.send(snapshot: matter.watchSnapshot(
            results: results,
            elapsedSeconds: elapsed,
            isPaused: isPaused,
            isActive: isActive && !hasEnded
        ))
    }

    private func saveCheckpoint() {
        store.saveSessionCheckpoint(LegalSessionCheckpoint(
            matterID: matter.id,
            startedAt: sessionStartedAt,
            elapsed: elapsed,
            isQuestionMode: isQuestionMode,
            bookmarkedRequirement: bookmarkedRequirement,
            results: results.map { result in
                var checkpoint = result
                checkpoint.evidenceSnippet = nil
                return checkpoint
            },
            matterSnapshot: matter
        ))
    }

    private func restartSpeech() async {
        speech.stop()
        guard !isPaused, !hasEnded else { return }
        reviewSchedule.retry()
        await speech.start(mode: .onDeviceOnly,
                           locale: matter.sessionPresentation.recognitionLocale,
                           contextualStrings: SpeechVocabulary.phrases(keywords: matter.authorities.map(\.citation),
                               context: requirements.flatMap { [$0.title, $0.detail] }))
    }
}

private struct LegalRehearsalHistoryView: View {
    @EnvironmentObject private var store: LegalMatterStore
    @Environment(\.dismiss) private var dismiss
    let matter: LegalMatter
    @State private var selectedRun: LegalRehearsalRun?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.runs(for: matter)) { run in
                    Button {
                        selectedRun = run
                    } label: {
                        HStack(spacing: 12) {
                            ProgressView(value: (run.matterSnapshot ?? matter).requiredLeafRequirements.isEmpty ? 0 : Double(run.requiredCoveredCount(for: run.matterSnapshot ?? matter)) / Double((run.matterSnapshot ?? matter).requiredLeafRequirements.count))
                                .progressViewStyle(.circular)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(run.isPracticeDrill ? "Focused practice · " : "")\(run.requiredCoveredCount(for: run.matterSnapshot ?? matter))/\((run.matterSnapshot ?? matter).requiredLeafRequirements.count) required covered · \(formatLegalTime(run.durationSeconds))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Rehearsal history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedRun) { run in
                LegalRehearsalReportView(matter: run.matterSnapshot ?? matter, run: run) {
                    selectedRun = nil
                }
            }
        }
    }
}

private struct LegalArgumentGuideCard: View {
    let matter: LegalMatter
    let requirement: LegalRequirement
    let position: Int
    let count: Int
    let isRecommended: Bool
    let hasUnaddressedPoints: Bool
    let hasPrevious: Bool
    let hasNext: Bool
    let previous: () -> Void
    let next: () -> Void
    let followNext: () -> Void

    private var issue: LegalIssue? {
        matter.issues.first { $0.leafRequirements.contains { $0.id == requirement.id } }
    }
    private var ancestors: [LegalRequirement] {
        issue?.requirements.compactMap { $0.path(to: requirement.id) }.first.map { Array($0.dropLast()) } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(isRecommended ? "CURRENT POINT" : "REVIEWING POINT", systemImage: "text.bubble.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
                Spacer()
                Text("\(position) of \(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(requirement.title)
                .font(.title3.weight(.bold))
            if let issue {
                Text(issue.shortLabel + " · " + issue.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("What to explain").font(.subheadline.weight(.semibold))
                Text(requirement.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "State this point, explain why it matters, and connect it to your requested relief. Add your specific speaking notes in Edit matter → Argument points."
                     : requirement.detail)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ancestors.filter { !$0.detail.isEmpty }) { ancestor in
                LegalPlanFactRow(label: ancestor.title, value: ancestor.detail)
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 16) {
                    if !matter.standardOfReview.isEmpty {
                        LegalPlanFactRow(label: "Standard of review", value: matter.standardOfReview)
                    }
                    if !matter.proceduralHistory.isEmpty {
                        LegalPlanFactRow(label: "Procedural history", value: matter.proceduralHistory)
                    }
                    if !matter.requestedRelief.isEmpty {
                        LegalPlanFactRow(label: "Requested relief", value: matter.requestedRelief)
                    }
                    if let issue {
                        ForEach(issue.authorities) { authority in
                            LegalPlanFactRow(label: authority.citation, value: authority.proposition)
                            if !authority.caution.isEmpty {
                                Label(authority.caution, systemImage: "exclamationmark.triangle")
                                    .font(.subheadline).foregroundStyle(.orange)
                            }
                        }
                        ForEach(issue.recordCitations) { citation in
                            LegalPlanFactRow(label: citation.label + " · " + citation.citation, value: citation.proposition)
                        }
                        ForEach(issue.contextCards) { card in
                            VStack(alignment: .leading, spacing: 5) {
                                Label(card.title, systemImage: card.kind.icon).font(.subheadline.weight(.semibold))
                                Text(card.body).font(.subheadline)
                                if !card.source.isEmpty { Text(card.source).font(.caption).foregroundStyle(.secondary) }
                            }
                            .foregroundStyle(card.kind == .danger ? Color.orange : Color.primary)
                        }
                        if issue.authorities.isEmpty && issue.recordCitations.isEmpty && issue.contextCards.isEmpty {
                            Text("Add authorities, record citations, and guardrails in Edit matter to keep them at hand here.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 12)
            } label: {
                Label("Support for this issue", systemImage: "books.vertical")
                    .font(.subheadline.weight(.semibold))
            }
            if let issue, !issue.likelyQuestions.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(issue.likelyQuestions) { question in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(question.question).font(.subheadline.weight(.semibold))
                                Text(question.response).font(.subheadline)
                            }
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Label("If the bench asks…", systemImage: "questionmark.bubble")
                        .font(.subheadline.weight(.semibold))
                }
            }
            Divider()
            HStack {
                Button(action: previous) { Label("Previous", systemImage: "chevron.left") }
                    .disabled(!hasPrevious)
                Spacer()
                Button(action: next) { Label("Next point", systemImage: "chevron.right") }
                    .disabled(!hasNext)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            if !isRecommended && hasUnaddressedPoints {
                Button("Follow next unaddressed point", action: followNext)
                    .font(.caption.weight(.semibold))
            }
            Text("Guidance advances as points are addressed. Previous and Next only change the notes you see.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.blue.opacity(0.3), lineWidth: 1))
        .id(requirement.id)
    }
}

private struct LegalLiveRequirementRow: View {
    let requirement: LegalRequirement
    let result: CueResult
    let isSelected: Bool
    let showGuidance: () -> Void
    let toggleCoverage: () -> Void

    private var isAddressed: Bool { result.status == .covered || result.status == .manual }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleCoverage) {
                Image(systemName: isAddressed ? "checkmark.circle.fill" : result.status == .emerging ? "circle.lefthalf.filled" : "circle")
                    .font(.title3)
                    .foregroundStyle(result.status == .covered ? .green : result.status == .manual ? .purple : result.status == .emerging ? .orange : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("\(isAddressed ? "Mark unaddressed" : "Mark addressed"): \(requirement.title)")
            .accessibilityHint("Manually changes coverage for this point.")
            Button(action: showGuidance) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(requirement.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(statusLabel + (requirement.isRequired ? "" : " · Optional"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !requirement.detail.isEmpty {
                            Text(requirement.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Show guidance: \(requirement.title)")
            if result.wasManualOverride { Image(systemName: "hand.raised.fill").font(.caption).foregroundStyle(.purple) }
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? .blue.opacity(0.45) : .clear, lineWidth: 1))
    }

    private var statusLabel: String {
        switch result.status {
        case .open: return "Not addressed"
        case .emerging: return "Partial"
        case .covered: return result.wasManualOverride ? "Manually confirmed" : "Satisfied"
        case .manual: return "Manual"
        }
    }
}

private struct LegalFocusedPracticeView: View {
    let matter: LegalMatter
    @State private var isReady = false

    var body: some View {
        if isReady {
            LegalRehearsalView(matter: matter)
        } else {
            LegalPrivacyPreflightView(matter: matter, start: { isReady = true },
                                      dismissBeforeStarting: false)
        }
    }
}

struct LegalRehearsalReportView: View {
    @Environment(\.dismiss) private var dismiss
    let matter: LegalMatter
    @EnvironmentObject private var store: LegalMatterStore
    @State private var run: LegalRehearsalRun
    @State private var practicePlan: LegalMatter?
    let transientTranscript: String?
    let onDone: () -> Void

    init(matter: LegalMatter, run: LegalRehearsalRun, transientTranscript: String? = nil, onDone: @escaping () -> Void) {
        self.matter = run.matterSnapshot ?? matter
        _run = State(initialValue: run)
        self.transientTranscript = transientTranscript
        self.onDone = onDone
    }

    private var unfinishedPlan: LegalMatter? {
        matter.unfinishedPractice(results: results, sourceRunID: run.id)
    }

    private var results: [CueResult] {
        matter.leafRequirements.map { requirement in
            run.results.first(where: { $0.cueID == requirement.id }) ?? CueResult(cueID: requirement.id)
        }
    }
    private var duration: Int { run.durationSeconds }

    private var requirements: [LegalRequirement] { matter.leafRequirements }
    private var requiredCount: Int { matter.requiredLeafRequirements.count }
    private var coveredCount: Int {
        results.enumerated().filter { index, result in
            index < requirements.count && requirements[index].isRequired && (result.status == .covered || result.status == .manual)
        }.count
    }
    private var unresolvedIndexes: [Int] {
        requirements.indices.filter { index in
            guard index < results.count, requirements[index].isRequired else { return false }
            return results[index].status == .open || results[index].status == .emerging
        }
    }

    private var reportText: String {
        let text = legalRehearsalReportText(matter: matter, results: results, durationSeconds: duration)
        guard let transcript = run.transcript else { return text }
        return text + "\n\nSaved transcript:\n" + transcript
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(coveredCount)/\(requiredCount)")
                                .font(.title.bold())
                            Text("requirements satisfied")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(formatLegalTime(duration))
                                .font(.title2.monospacedDigit().bold())
                            Text("rehearsal duration")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section("Unresolved requirements") {
                    if unresolvedIndexes.isEmpty {
                        Label("Every requirement was addressed.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(unresolvedIndexes, id: \.self) { index in
                            Label(requirements[index].title, systemImage: results[index].status == .emerging ? "circle.lefthalf.filled" : "circle")
                                .foregroundStyle(results[index].status == .emerging ? .orange : .secondary)
                        }
                    }
                }
                Section("Focused practice") {
                    Button {
                        practicePlan = unfinishedPlan
                    } label: {
                        Label("Practice unfinished points", systemImage: "arrow.clockwise")
                    }
                    .disabled(unfinishedPlan == nil)
                    .accessibilityIdentifier("practiceUnfinishedPoints")
                    Text(unfinishedPlan.map { "Rehearse \($0.requiredLeafRequirements.count) missed or partial required points. This drill is saved separately from full rehearsals." }
                         ?? "All required points are covered. Correct a point below to practice it again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Coverage review") {
                    ForEach(results) { result in
                        if let note = result.semanticNote,
                           let requirement = requirements.first(where: { $0.id == result.cueID }) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(requirement.title).font(.subheadline.weight(.semibold))
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Evidence snippets") {
                    let evidence = requirements.indices.compactMap { index -> (String, String)? in
                        guard index < results.count, let snippet = results[index].evidenceSnippet else { return nil }
                        return (requirements[index].title, snippet)
                    }
                    if evidence.isEmpty {
                        Text("No local evidence snippets were captured.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.0).font(.subheadline.weight(.semibold))
                                Text(item.1).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Manual corrections") {
                    Text("\(results.filter(\.wasManualOverride).count) manual corrections").foregroundStyle(.secondary)
                    ForEach(Array(run.results.enumerated()), id: \.element.id) { index, result in
                        if let requirement = requirements.first(where: { $0.id == result.cueID }) {
                            Toggle(requirement.title, isOn: Binding(get: {
                                run.results[index].status == .covered || run.results[index].status == .manual
                            }, set: { complete in
                                run.results[index].status = complete ? .manual : .open
                                run.results[index].wasManualOverride = true
                                store.updateRun(run)
                            }))
                        }
                    }
                }
                if let words = run.wordCount, words > 0 {
                    Section("Speaking metrics") {
                        LabeledContent("Words", value: "\(words)")
                        LabeledContent("Average pace", value: "\(run.wordsPerMinute) words/min")
                        LabeledContent("Filler words", value: "\(run.fillerCount ?? 0)")
                    }
                }
                Section("Transcript") {
                    SessionTranscriptSection(transcript: run.transcript ?? transientTranscript,
                                             isSaved: run.transcript != nil, title: matter.title)
                }
            }
            .navigationTitle(run.isPracticeDrill ? "Focused practice report" : "Rehearsal report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: reportText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share rehearsal report")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        onDone()
                    }
                }
            }
        }
        .fullScreenCover(item: $practicePlan) { plan in
            LegalFocusedPracticeView(matter: plan)
        }
    }
}

func formatLegalTime(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}
