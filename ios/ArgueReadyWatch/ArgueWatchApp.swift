import SwiftUI

@main
struct ArgueWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityBridge.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView(labels: WatchAppLabels(
                appName: "ArgueReady",
                nextCue: "Next requirement",
                allCovered: "All required points covered",
                ready: "Ready to rehearse",
                waiting: "Ready for rehearsal",
                waitingDetail: "Open a matter on your iPhone. You can start and control rehearsal here.",
                startHint: "Confirm the preflight on your iPhone to start.",
                privacyNote: "Checklist state only — no audio or transcript on Watch."
            ))
            .environmentObject(connectivity)
        }
    }
}
