import SwiftUI

enum LegalDestination: String, CaseIterable, Identifiable {
    case today = "Today", matters = "Matters", history = "History", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .matters: return "briefcase"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct LegalRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var watchConnectivity = WatchConnectivityBridge.shared
    @State private var destination: LegalDestination = .today

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    List {
                        ForEach(LegalDestination.allCases) { item in
                            Button { destination = item } label: {
                                Label(item.rawValue, systemImage: item.icon)
                                    .foregroundStyle(destination == item ? Color.blue : Color.primary)
                            }
                        }
                    }
                    .navigationTitle("ArgueReady")
                    .navigationSplitViewColumnWidth(min: 220, ideal: 250)
                } detail: {
                    destinationView(destination)
                }
            } else {
                TabView(selection: $destination) {
                    ForEach(LegalDestination.allCases) { item in
                        destinationView(item)
                            .tabItem { Label(item.rawValue, systemImage: item.icon) }
                            .tag(item)
                    }
                }
            }
        }
        .tint(.blue)
        .onAppear { watchConnectivity.activate() }
        .onChange(of: watchConnectivity.pendingCommand) { _, command in
            if command == .start { destination = .matters }
        }
    }

    @ViewBuilder private func destinationView(_ item: LegalDestination) -> some View {
        switch item {
        case .today: LegalTodayView(destination: $destination)
        case .matters: LegalMatterLibraryView()
        case .history: LegalHistoryView()
        case .settings: LegalSettingsView()
        }
    }
}

struct LegalTodayView: View {
    @EnvironmentObject private var store: LegalMatterStore
    @Binding var destination: LegalDestination
    @State private var selectedMatter: LegalMatter?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Every point. Ready for the bench.").font(.title2.bold())
                        Text("Prepare your argument, rehearse the requirements, and review your coverage.")
                            .foregroundStyle(.secondary)
                        Button("Choose a matter") { destination = .matters }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 8)
                }
                if let checkpoint = store.sessionCheckpoint {
                    Section("Interrupted rehearsal") {
                        Button { destination = .matters } label: {
                            Label("Resume rehearsal · \(formatLegalTime(checkpoint.elapsed)) elapsed", systemImage: "arrow.clockwise")
                        }
                    }
                }
                Section("Recent matters") {
                    if store.matters.isEmpty {
                        Text("Create your first matter in Matters.").foregroundStyle(.secondary)
                    }
                    ForEach(store.matters.prefix(3)) { matter in
                        Button { selectedMatter = matter } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(matter.title).font(.headline).foregroundStyle(.primary)
                                Text("\(matter.court) · \(matter.totalMinutes) min").font(.caption).foregroundStyle(.secondary)
                                if let run = store.runs(for: matter).first {
                                    let original = run.matterSnapshot ?? matter
                                    Text("\(run.isPracticeDrill ? "Last focused practice" : "Last rehearsal"): \(run.requiredCoveredCount(for: original))/\(original.requiredLeafRequirements.count) required covered")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section("Rehearsal insights") {
                    LabeledContent("Full rehearsals", value: "\(store.runs.filter { !$0.isPracticeDrill }.count)")
                    LabeledContent("Focused practices", value: "\(store.runs.filter(\.isPracticeDrill).count)")
                    if let latest = store.runs.first(where: { !$0.isPracticeDrill }) {
                        LabeledContent("Last rehearsal", value: latest.startedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Duration", value: formatLegalTime(latest.durationSeconds))
                    }
                    Button("Review history") { destination = .history }
                }
            }
            .navigationTitle("Today")
            .sheet(item: $selectedMatter) { matter in LegalMatterHomeView(matter: matter) }
        }
    }
}

struct LegalSettingsView: View {
    @EnvironmentObject private var store: LegalMatterStore

    private var replays: [CoreCoverageReplay] {
        store.runs.compactMap { run in
            guard let matter = run.matterSnapshot ?? store.matters.first(where: { $0.id == run.matterID }),
                  let transcript = run.transcript, !transcript.isEmpty else { return nil }
            return CoreCoverageReplay(presentation: matter.sessionPresentation, run: run.replayRun)
        }
    }

    var body: some View {
        CoreSettingsView(settings: $store.settings, productName: "ArgueReady",
                         tagline: "Every point. Ready for the bench.", collectionName: "matters",
                         exportText: store.exportDataText(), replayCandidates: replays,
                         deleteHistory: store.deleteAllRuns, deleteTranscripts: store.deleteSavedTranscripts, localOnly: true)
    }
}

struct LegalHistoryView: View {
    @EnvironmentObject private var store: LegalMatterStore
    @State private var selectedRun: LegalRehearsalRun?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.runs) { run in
                    if let matter = run.matterSnapshot ?? store.matters.first(where: { $0.id == run.matterID }) {
                        Button { selectedRun = run } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(matter.title).font(.headline).foregroundStyle(.primary)
                                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(run.isPracticeDrill ? "Focused practice · " : "")\(run.requiredCoveredCount(for: matter))/\(matter.requiredLeafRequirements.count) required covered · \(formatLegalTime(run.durationSeconds))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        VStack(alignment: .leading) {
                            Text("Archived matter")
                            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            Text("The original matter is unavailable for this older report.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if store.runs.isEmpty {
                    ContentUnavailableView("No rehearsals yet", systemImage: "clock", description: Text("Completed rehearsals and reports appear here."))
                }
            }
            .navigationTitle("History")
            .sheet(item: $selectedRun) { run in
                if let matter = run.matterSnapshot ?? store.matters.first(where: { $0.id == run.matterID }) {
                    LegalRehearsalReportView(matter: matter, run: run) { selectedRun = nil }
                }
            }
        }
    }
}

struct LegalSessionDefaultsSection: View {
    @Binding var preferences: LegalSessionPreferences

    var body: some View {
        Section("Session defaults") {
            Picker("Recognition language", selection: $preferences.recognitionLocale) {
                Text("English (US) default").tag(nil as SpeechLocale?)
                ForEach(SpeechLocale.allCases) { locale in Text(locale.title).tag(Optional(locale)) }
            }
            Label("On-device speech and semantic coverage", systemImage: "lock.shield")
            LegalOptionalBoolPicker(title: "Haptic feedback", value: $preferences.hapticsEnabled)
            LegalOptionalBoolPicker(title: "Keep screen awake", value: $preferences.keepScreenAwake)
            LegalOptionalBoolPicker(title: "Transcript preview", value: $preferences.showTranscript)
            LegalOptionalBoolPicker(title: "Save transcript locally", value: $preferences.saveTranscript)
            Text("Use Settings follows your global defaults. Overrides apply only to this matter and future sessions.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LegalOptionalBoolPicker: View {
    let title: String
    @Binding var value: Bool?
    var body: some View {
        Picker(title, selection: $value) {
            Text("Use Settings").tag(nil as Bool?)
            Text("On").tag(Optional(true))
            Text("Off").tag(Optional(false))
        }
    }
}
