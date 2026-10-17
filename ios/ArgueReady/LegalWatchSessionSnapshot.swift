import Foundation

extension LegalMatter {
    func watchSnapshot(
        results: [CueResult] = [],
        elapsedSeconds: Int = 0,
        isPaused: Bool = false,
        isActive: Bool = false,
        canStart: Bool = false
    ) -> WatchSessionSnapshot {
        let resultsByID = Dictionary(results.map { ($0.cueID, $0) }, uniquingKeysWith: { _, newest in newest })
        let required = requiredLeafRequirements
        let coveredCount = required.filter { requirement in
            let status = resultsByID[requirement.id]?.status ?? .open
            return status == .covered || status == .manual
        }.count
        let next = required.first { requirement in
            let status = resultsByID[requirement.id]?.status ?? .open
            return status == .open || status == .emerging
        }
        return WatchSessionSnapshot(
            presentationID: id.uuidString,
            presentationTitle: title,
            coveredCount: coveredCount,
            requiredCount: required.count,
            nextCueTitle: next?.title,
            nextCueDetail: next?.detail,
            elapsedSeconds: elapsedSeconds,
            targetDurationSeconds: totalMinutes * 60,
            isPaused: isPaused,
            isActive: isActive,
            canStart: canStart
        )
    }
}
