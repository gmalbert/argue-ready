import Foundation
import WatchConnectivity
import OSLog

private let connectivitySubsystem = Bundle.main.object(forInfoDictionaryKey: "WKCompanionAppBundleIdentifier") as? String
    ?? Bundle.main.bundleIdentifier ?? "com.cuecomplete.app"
private let connectivityLogger = Logger(subsystem: connectivitySubsystem, category: "WatchConnectivity")

#if os(iOS)
import Combine
#endif

#if os(iOS)

final class WatchConnectivityBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityBridge()

    @Published private(set) var latestSnapshot: WatchSessionSnapshot?
    @Published private(set) var pendingCommand: WatchSessionCommand?
    private let latestSnapshotKey = "cuecomplete.watch.latest-snapshot"

    private override init() {
        super.init()
        if let payload = UserDefaults.standard.dictionary(forKey: latestSnapshotKey) {
            latestSnapshot = WatchSessionSnapshot(payload: payload)
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            flushLatestSnapshot(on: session)
        } else {
            session.activate()
        }
    }

    func send(snapshot: WatchSessionSnapshot) {
        guard WCSession.isSupported() else { return }
        latestSnapshot = snapshot
        UserDefaults.standard.set(snapshot.payload, forKey: latestSnapshotKey)
        activate()
    }

    func send(command: WatchSessionCommand) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(command.payload, replyHandler: nil) { error in
                connectivityLogger.error("Command delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            session.transferUserInfo(command.payload)
        }
    }

    func clearPendingCommand() {
        pendingCommand = nil
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = WatchSessionCommand(payload: message) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.pendingCommand = command
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                replyHandler([:])
                return
            }
            if message["request"] as? String == "snapshot" {
                connectivityLogger.info("Watch requested the latest snapshot")
                replyHandler(self.latestSnapshot?.payload ?? [:])
            } else {
                if let command = WatchSessionCommand(payload: message) {
                    self.pendingCommand = command
                }
                replyHandler([:])
            }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let command = WatchSessionCommand(payload: userInfo) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.pendingCommand = command
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            connectivityLogger.error("iPhone activation failed: \(error.localizedDescription, privacy: .public)")
        }
        guard error == nil, activationState == .activated else { return }
        DispatchQueue.main.async { [weak self] in
            self?.logState(on: session)
            self?.flushLatestSnapshot(on: session)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.logState(on: session)
            self?.flushLatestSnapshot(on: session)
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.logState(on: session)
            self?.flushLatestSnapshot(on: session)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    private func logState(on session: WCSession) {
        connectivityLogger.info("iPhone activation=\(session.activationState.rawValue) paired=\(session.isPaired) watchInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
    }

    // Application context queues state; accepting it does not mean the Watch has
    // consumed it. Keep the latest snapshot for foreground and reconnect retries.
    private func flushLatestSnapshot(on session: WCSession) {
        guard session.activationState == .activated,
              let snapshot = latestSnapshot else { return }

        connectivityLogger.debug("Sending snapshot active=\(snapshot.isActive) paused=\(snapshot.isPaused) covered=\(snapshot.coveredCount)/\(snapshot.requiredCount) keys=\(snapshot.payload.keys.sorted().joined(separator: ","), privacy: .public)")

        do {
            try session.updateApplicationContext(snapshot.payload)
        } catch {
            connectivityLogger.error("Application context delivery failed: \(error.localizedDescription, privacy: .public)")
        }

        guard session.isReachable else { return }
        session.sendMessage(snapshot.payload, replyHandler: nil) { error in
            // Context still holds the latest state. A failed older message must
            // never replace it with an outdated snapshot.
            connectivityLogger.error("Immediate snapshot delivery failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#elseif os(watchOS)

import WatchKit
import SwiftUI

final class WatchConnectivityBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityBridge()

    @Published private(set) var snapshot: WatchSessionSnapshot?
    private var lastCoveredCount = 0

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            requestLatestSnapshot(on: session)
        } else {
            session.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            connectivityLogger.error("Watch activation failed: \(error.localizedDescription, privacy: .public)")
        }
        guard error == nil, activationState == .activated else { return }
        connectivityLogger.info("Watch activated companionInstalled=\(session.isCompanionAppInstalled) reachable=\(session.isReachable) contextKeys=\(session.receivedApplicationContext.keys.sorted().joined(separator: ","), privacy: .public)")
        consume(session.receivedApplicationContext)
        requestLatestSnapshot(on: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        requestLatestSnapshot(on: session)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        consume(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        consume(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        consume(userInfo)
    }

    func send(command: WatchSessionCommand) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(command.payload, replyHandler: nil) { error in
                connectivityLogger.error("Watch command delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            session.transferUserInfo(command.payload)
        }
    }

    private func requestLatestSnapshot(on session: WCSession) {
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "snapshot"], replyHandler: { [weak self] payload in
            self?.consume(payload)
        }, errorHandler: { error in
            connectivityLogger.error("Snapshot request failed: \(error.localizedDescription, privacy: .public)")
        })
    }

    private func consume(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }
        guard let nextSnapshot = WatchSessionSnapshot(payload: payload) else {
            connectivityLogger.error("Invalid snapshot keys=\(payload.keys.sorted().joined(separator: ","), privacy: .public)")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Delayed background context can arrive after a newer live message.
            if let current = self.snapshot, nextSnapshot.updatedAt < current.updatedAt { return }
            if self.snapshot?.isActive != nextSnapshot.isActive || self.snapshot?.isPaused != nextSnapshot.isPaused {
                connectivityLogger.info("Watch session state received active=\(nextSnapshot.isActive) paused=\(nextSnapshot.isPaused) canStart=\(nextSnapshot.canStart)")
            }
            if nextSnapshot.isActive, nextSnapshot.coveredCount > self.lastCoveredCount {
                WKInterfaceDevice.current().play(.success)
            }
            self.lastCoveredCount = nextSnapshot.isActive ? nextSnapshot.coveredCount : 0
            self.snapshot = nextSnapshot
            connectivityLogger.debug("Consumed snapshot active=\(nextSnapshot.isActive) paused=\(nextSnapshot.isPaused) covered=\(nextSnapshot.coveredCount)/\(nextSnapshot.requiredCount)")
        }
    }
}

#endif
