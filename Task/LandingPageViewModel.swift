//
//  LandingPageViewModel.swift
//  Task
//

import Foundation
import Observation

/// Each request runs in its own Task; a new request cancels the previous one and starts at once.
@Observable
final class LandingPageViewModel: TaskDemoModel {
    private(set) var state: LoadState = .idle
    private(set) var log: [LogEntry] = []

    /// The only running task. Starting a new one always cancels this one first.
    private var currentTask: Task<Void, Never>?
    private var nextRequestID = 1
    private let fetch: @Sendable () async throws -> FetchResult

    init(fetch: @escaping @Sendable () async throws -> FetchResult = { try await LandingPageService().fetch() }) {
        self.fetch = fetch
    }

    /// Starts a new request. Any request still in flight is cancelled; only the newest one wins.
    func load() {
        if let currentTask {
            currentTask.cancel()
            append("Cancel previous task")
        }

        let requestID = nextRequestID
        nextRequestID += 1
        state = .loading(requestID: requestID)
        append("#\(requestID) started")

        currentTask = Task { [weak self, fetch] in
            do {
                let result = try await fetch()
                // Cancellation is cooperative: the work may finish after cancel() was called,
                // so a stale task must never overwrite the newer task's state.
                try Task.checkCancellation()
                self?.finish(state: .loaded(requestID: requestID, result),
                             message: "#\(requestID) finished, HTTP \(result.statusCode)")
            } catch {
                // A cancelled task can still fail with a non-cancellation error (e.g. a timeout).
                // It is stale either way and must not touch `state` or `currentTask`,
                // which may already belong to a newer task.
                if Task.isCancelled || Self.isCancellation(error) {
                    self?.append("#\(requestID) cancelled")
                } else {
                    self?.finish(state: .failed(requestID: requestID, message: error.localizedDescription),
                                 message: "#\(requestID) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancel() {
        guard let currentTask else { return }
        currentTask.cancel()
        self.currentTask = nil
        state = .idle
        append("Cancel requested by user")
    }

    func clearLog() {
        log.removeAll()
    }

    /// Only called by the task that is still current, so clearing `currentTask` here is safe.
    /// Task does not reset this reference by itself when it completes.
    private func finish(state newState: LoadState, message: String) {
        state = newState
        currentTask = nil
        append(message)
    }

    private func append(_ message: String) {
        log.insert(LogEntry(message: message), at: 0)
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
