import Dispatch
import Foundation
import Testing
@testable import Colony

/// Default clock used by Colony tests.
struct ColonyTestClock: HiveClock {
    let nowValue: UInt64
    let usesRealSleep: Bool

    init(nowValue: UInt64 = 0, usesRealSleep: Bool = true) {
        self.nowValue = nowValue
        self.usesRealSleep = usesRealSleep
    }

    func nowNanoseconds() -> UInt64 { nowValue }

    func sleep(nanoseconds: UInt64) async throws {
        if usesRealSleep {
            try await Task.sleep(nanoseconds: nanoseconds)
            return
        }

        await Task.yield()
    }
}

struct ColonyTestLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

/// Alias for the production in-memory checkpoint store to avoid test-only duplication.
typealias ColonyTestInMemoryCheckpointStore = ColonyInMemoryCheckpointStore

func colonyWaitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if await condition() {
            return true
        }

        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }

    return await condition()
}

private struct ColonyTestFailure: Error, CustomStringConvertible {
    let description: String
}

func colonyTestFail(_ message: String = "Unexpected test control flow.") {
    Issue.record(ColonyTestFailure(description: message))
}
