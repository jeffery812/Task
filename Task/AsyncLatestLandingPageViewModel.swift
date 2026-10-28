//
//  AsyncLatestLandingPageViewModel.swift
//  Task
//

import Foundation
import Observation

/// Callers `await` the result, like `SerialLandingPageViewModel`, but a new request does not wait:
/// it cancels the previous one and starts at once, like `LandingPageViewModel`.
/// Only the newest request returns a value; replaced ones throw `CancellationError`.
@Observable
final class AsyncLatestLandingPageViewModel: TaskDemoModel {
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
    /// Throws `CancellationError` if a newer call or `cancel()` replaced this one, or if the caller's task is cancelled.
    func load() async throws -> FetchResult {
        let requestID = nextRequestID
        nextRequestID += 1

        if let currentTask {
            currentTask.cancel()
            append("Cancel previous task")
        }
        state = .loading(requestID: requestID)
        append("#\(requestID) started")

        // Unlike the serial strategy there is no `await previous?.result`: the cancelled request
        // may still be winding down while this one runs.
        let task = Task { @concurrent [weak self, fetch] in
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
            // load() is reentrant: a newer call may have cancelled `task` while this one was suspended,
            // even though the value arrived. A stale value must not overwrite the newer state.
            guard !task.isCancelled else { throw CancellationError() }

            state = .loaded(requestID: requestID, value)
            currentTask = nil
            append("#\(requestID) finished, HTTP \(value.statusCode)")
            return value
        } catch {
            // A cancelled request may still fail with another error (e.g. a timeout); it is stale either way.
            if task.isCancelled {
                append("#\(requestID) cancelled")
                // Cancelled by the caller rather than replaced: nothing else will update `state`.
                if currentTask == task {
                    currentTask = nil
                    state = .idle
                }
                throw CancellationError()
            }
            state = .failed(requestID: requestID, message: error.localizedDescription)
            currentTask = nil
            append("#\(requestID) failed: \(error.localizedDescription)")
            throw error
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

    private func append(_ message: String) {
        log.insert(LogEntry(message: message), at: 0)
    }
}
