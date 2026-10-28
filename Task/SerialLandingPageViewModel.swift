//
//  SerialLandingPageViewModel.swift
//  Task
//

import Foundation
import Observation

/// Same request as `LandingPageViewModel`, but callers `await` the result, and the work runs on a
/// background thread strictly one request after another: a new request waits for the cancelled one
/// to stop before it starts, and requests replaced while waiting never run.
@Observable
final class SerialLandingPageViewModel: TaskDemoModel {
    private(set) var state: LoadState = .idle
    private(set) var log: [LogEntry] = []

    /// The latest request. Only touched on the main actor, so no lock is needed.
    private var currentTask: Task<FetchResult, any Error>?
    private var nextRequestID = 1
    private let fetch: @Sendable () async throws -> FetchResult

    init(fetch: @escaping @Sendable () async throws -> FetchResult = { try await LandingPageService().fetch() }) {
        self.fetch = fetch
    }

    /// Fetches the landing page and returns the result. A newer `load()` cancels this one.
    ///
    /// Throws `CancellationError` if a newer call replaced this one, or if the caller's task is cancelled.
    func load() async throws -> FetchResult {
        let requestID = nextRequestID
        nextRequestID += 1
        state = .loading(requestID: requestID)
        append("#\(requestID) submitted")

        let previous = currentTask
        previous?.cancel()

        // `@concurrent`: the work runs on the global concurrent executor, not the main actor.
        let task = Task { @concurrent [weak self, fetch] in
            // Cancellation is cooperative: wait until the previous request has actually finished.
            _ = await previous?.result
            try Task.checkCancellation() // Replaced while waiting: never start.

            let onMainThread = isOnMainThread()
            await self?.append("#\(requestID) running, main thread: \(onMainThread)")
            return try await fetch()
        }
        currentTask = task

        do {
            // `task.value` does not forward cancellation to an unstructured task,
            // so cancelling the caller has to cancel the work explicitly.
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            // load() is reentrant: other calls may have run while this one was suspended above.
            // Back on the main actor, like every call that could cancel `task`, so this check
            // cannot race with them: the value may have arrived just before a newer call.
            guard !task.isCancelled else { throw CancellationError() }

            state = .loaded(requestID: requestID, value)
            append("#\(requestID) finished, HTTP \(value.statusCode)")
            currentTask = nil
            return value
        } catch {
            // `task` is cancelled only by a newer load(), cancel() or the caller's cancellation.
            // A cancelled request may still fail with another error (e.g. a timeout).
            if task.isCancelled {
                append("#\(requestID) cancelled")
                // Not replaced by a newer load(): nothing else will update `state`, so leave `.loading`.
                if requestID == nextRequestID - 1 {
                    state = .idle
                }
                throw CancellationError()
            }
            state = .failed(requestID: requestID, message: error.localizedDescription)
            append("#\(requestID) failed: \(error.localizedDescription)")
            currentTask = nil
            throw error
        }
    }

    func cancel() {
        // Keep `currentTask` so the next request still waits for this one to stop.
        currentTask?.cancel()
        state = .idle
        append("Cancel requested by user")
    }

    func clearLog() {
        log.removeAll()
    }

    private func append(_ message: String) {
        log.insert(LogEntry(message: message), at: 0)
    }
}
