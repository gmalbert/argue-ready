import Foundation

/// The small, privacy-safe payload sent from an active iPhone session to the Watch.
/// It intentionally contains checklist state only — never audio or transcript text.
struct WatchSessionSnapshot: Hashable {
    let presentationID: String?
    let presentationTitle: String
    let coveredCount: Int
    let requiredCount: Int
    let nextCueTitle: String?
    let nextCueDetail: String?
    let elapsedSeconds: Int
    let targetDurationSeconds: Int
    let isPaused: Bool
    let isActive: Bool
    let canStart: Bool
    let updatedAt: Date

    var remainingSeconds: Int {
        max(0, targetDurationSeconds - elapsedSeconds)
    }

    var progress: Double {
        guard requiredCount > 0 else { return 0 }
        return min(1, max(0, Double(coveredCount) / Double(requiredCount)))
    }

    var payload: [String: Any] {
        var payload: [String: Any] = [
            "presentationTitle": presentationTitle,
            "coveredCount": coveredCount,
            "requiredCount": requiredCount,
            "elapsedSeconds": elapsedSeconds,
            "targetDurationSeconds": targetDurationSeconds,
            "isPaused": isPaused,
            "isActive": isActive,
            "canStart": canStart,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        if let presentationID {
            payload["presentationID"] = presentationID
        }
        if let nextCueTitle {
            payload["nextCueTitle"] = nextCueTitle
        }
        if let nextCueDetail {
            payload["nextCueDetail"] = nextCueDetail
        }
        return payload
    }

    init(
        presentationID: String? = nil,
        presentationTitle: String,
        coveredCount: Int,
        requiredCount: Int,
        nextCueTitle: String?,
        nextCueDetail: String?,
        elapsedSeconds: Int,
        targetDurationSeconds: Int,
        isPaused: Bool,
        isActive: Bool = true,
        canStart: Bool = false,
        updatedAt: Date = .now
    ) {
        self.presentationID = presentationID
        self.presentationTitle = presentationTitle
        self.coveredCount = max(0, coveredCount)
        self.requiredCount = max(0, requiredCount)
        self.nextCueTitle = nextCueTitle
        self.nextCueDetail = nextCueDetail
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.targetDurationSeconds = max(0, targetDurationSeconds)
        self.isPaused = isPaused
        self.isActive = isActive
        self.canStart = canStart
        self.updatedAt = updatedAt
    }

    init?(payload: [String: Any]) {
        guard
            let presentationTitle = payload["presentationTitle"] as? String,
            let coveredCount = payload["coveredCount"] as? Int,
            let requiredCount = payload["requiredCount"] as? Int,
            let elapsedSeconds = payload["elapsedSeconds"] as? Int,
            let targetDurationSeconds = payload["targetDurationSeconds"] as? Int,
            let isPaused = payload["isPaused"] as? Bool,
            let isActive = payload["isActive"] as? Bool
        else { return nil }

        self.init(
            presentationID: payload["presentationID"] as? String,
            presentationTitle: presentationTitle,
            coveredCount: coveredCount,
            requiredCount: requiredCount,
            nextCueTitle: payload["nextCueTitle"] as? String,
            nextCueDetail: payload["nextCueDetail"] as? String,
            elapsedSeconds: elapsedSeconds,
            targetDurationSeconds: targetDurationSeconds,
            isPaused: isPaused,
            isActive: isActive,
            canStart: payload["canStart"] as? Bool ?? false,
            updatedAt: (payload["updatedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        )
    }
}

enum WatchSessionCommand: String, Hashable {
    case start
    case pause
    case resume
    case end

    var payload: [String: Any] {
        ["command": rawValue]
    }

    init?(payload: [String: Any]) {
        guard let rawValue = payload["command"] as? String else { return nil }
        self.init(rawValue: rawValue)
    }
}
