import SwiftUI

struct WatchAppLabels {
    var appName = "Cue Complete"
    var nextCue = "Next cue"
    var allCovered = "All required cues covered"
    var ready = "Ready to present"
    var waiting = "Ready for a session"
    var waitingDetail = "Open a presentation on your iPhone. You can start and control it here."
    var startHint: String?
    var privacyNote = "Checklist state only — no audio or transcript on Watch."
}

struct WatchRootView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityBridge
    @Environment(\.scenePhase) private var scenePhase
    var labels = WatchAppLabels()

    var body: some View {
        Group {
            if let snapshot = connectivity.snapshot, snapshot.isActive {
                ActiveWatchSessionView(snapshot: snapshot, labels: labels, send: connectivity.send(command:))
            } else if let snapshot = connectivity.snapshot, snapshot.canStart {
                WatchReadyView(snapshot: snapshot, labels: labels, send: connectivity.send(command:))
            } else {
                WatchWaitingView(labels: labels)
            }
        }
        .onAppear {
            connectivity.activate()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                connectivity.activate()
            }
        }
    }
}

private struct ActiveWatchSessionView: View {
    let snapshot: WatchSessionSnapshot
    let labels: WatchAppLabels
    let send: (WatchSessionCommand) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(snapshot.presentationTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(snapshot.coveredCount)")
                        .font(.system(size: 37, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("/ \(snapshot.requiredCount)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: snapshot.progress)
                    .tint(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Label(labels.nextCue, systemImage: "arrow.down.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                    Text(snapshot.nextCueTitle ?? labels.allCovered)
                        .font(.headline)
                        .lineLimit(3)
                    if let detail = snapshot.nextCueDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Label(snapshot.isPaused ? "Paused" : "Remaining", systemImage: snapshot.isPaused ? "pause.fill" : "clock")
                        .font(.caption2.weight(.semibold))
                    Spacer()
                    Text(timeLabel(snapshot.remainingSeconds))
                        .font(.headline.monospacedDigit())
                }
                .foregroundStyle(snapshot.isPaused ? .orange : .primary)

                HStack(spacing: 8) {
                    Button {
                        send(snapshot.isPaused ? .resume : .pause)
                    } label: {
                        Label(snapshot.isPaused ? "Resume" : "Pause", systemImage: snapshot.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(snapshot.isPaused ? .green : .orange)

                    Button(role: .destructive) {
                        send(.end)
                    } label: {
                        Label("End", systemImage: "stop.fill")
                            .frame(width: 52, height: 32)
                    }
                    .tint(.red)
                }

                Text(labels.privacyNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(labels.appName)
    }

    private func timeLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

private struct WatchReadyView: View {
    let snapshot: WatchSessionSnapshot
    let labels: WatchAppLabels
    let send: (WatchSessionCommand) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.green)
            Text(snapshot.presentationTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text(labels.ready)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                send(.start)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            if let hint = labels.startHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(labels.privacyNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
    }
}

private struct WatchWaitingView: View {
    let labels: WatchAppLabels
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.cyan)
            Text(labels.waiting)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(labels.waitingDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(labels.privacyNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
    }
}
