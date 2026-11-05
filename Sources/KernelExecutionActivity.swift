import Foundation

/// Live request state only; it is never written into a notebook document.
enum KernelExecutionPhase: String, Equatable {
    case queued
    case running
    case waitingForInput

    fileprivate var priority: Int {
        switch self {
        case .queued: return 0
        case .running: return 1
        case .waitingForInput: return 2
        }
    }
}

struct KernelExecutionActivity: Equatable, Identifiable {
    let id: String
    let originID: String?
    var phase: KernelExecutionPhase
    let queuedAt: Date
    var startedAt: Date?

    mutating func mark(_ phase: KernelExecutionPhase, at date: Date = Date()) {
        if phase != .queued && startedAt == nil { startedAt = date }
        self.phase = phase
    }

    /// An origin can have queued selections while another request is active.
    /// Prefer real activity; tie-break consistently without resetting its clock.
    static func representative(in activities: [Self]) -> Self? {
        activities.sorted { left, right in
            if left.phase.priority != right.phase.priority { return left.phase.priority > right.phase.priority }
            let lhs = left.startedAt ?? left.queuedAt
            let rhs = right.startedAt ?? right.queuedAt
            return lhs == rhs ? left.id < right.id : lhs < rhs
        }.first
    }
    static func representative(forOriginID originID: String, in activities: [Self]) -> Self? {
        representative(in: activities.filter { $0.originID == originID })
    }
}
