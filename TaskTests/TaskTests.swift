//
//  TaskTests.swift
//  TaskTests
//
//  Created by Zhihui Tang on 2026-10-16.
//

import Foundation
import Testing
@testable import Task

@MainActor
struct TaskTests {

    @Test func newLoadCancelsPreviousTask() async throws {
        let viewModel = LandingPageViewModel {
            try await Task.sleep(for: .milliseconds(200))
            return FetchResult.stub
        }

        viewModel.load()
        viewModel.load()
        viewModel.load()

        try await waitUntil { if case .loaded = viewModel.state { true } else { false } }

        #expect(viewModel.state == .loaded(requestID: 3, FetchResult.stub))
        let messages = viewModel.log.map(\.message)
        #expect(messages.contains("#1 cancelled"))
        #expect(messages.contains("#2 cancelled"))
        #expect(!messages.contains("#1 finished, HTTP 200"))
        #expect(!messages.contains("#2 finished, HTTP 200"))
    }

    @Test func staleResultDoesNotOverwriteNewerTask() async throws {
        // The fetch ignores cancellation, so the cancelled task still returns a value.
        let viewModel = LandingPageViewModel {
            try? await Task.sleep(for: .milliseconds(100))
            return FetchResult.stub
        }

        viewModel.load()
        viewModel.load()

        try await waitUntil { if case .loaded = viewModel.state { true } else { false } }
        #expect(viewModel.state == .loaded(requestID: 2, FetchResult.stub))
        #expect(viewModel.log.map(\.message).contains("#1 cancelled"))
    }

    @Test func staleErrorDoesNotClearNewerTask() async throws {
        // A cancelled task that fails with a non-cancellation error, e.g. a timeout arriving after cancel().
        let viewModel = LandingPageViewModel {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(100))
            return FetchResult.stub
        }

        viewModel.load()
        viewModel.load()

        try await waitUntil { viewModel.log.contains { $0.message == "#1 cancelled" } }
        #expect(viewModel.state == .loading(requestID: 2))

        // #2 must still be the current task, so cancel() reaches it.
        viewModel.cancel()
        try await waitUntil { viewModel.log.contains { $0.message == "#2 cancelled" } }
        #expect(!viewModel.log.contains { $0.message.hasPrefix("#1 failed") })
    }

    @Test func cancelStopsRunningTask() async throws {
        let viewModel = LandingPageViewModel {
            try await Task.sleep(for: .seconds(10))
            return FetchResult.stub
        }

        viewModel.load()
        viewModel.cancel()

        try await waitUntil { viewModel.log.contains { $0.message == "#1 cancelled" } }
        #expect(viewModel.state == .idle)
    }

    // MARK: - Serial latest

    @Test func serialRequestsRunOneAtATimeOffMainThread() async throws {
        let recorder = Recorder()
        let viewModel = SerialLandingPageViewModel {
            await recorder.start(onMainThread: isOnMainThread())
            // Keeps running after cancel(), so #2–#5 really have to wait for #1.
            await uncancellableSleep(for: .milliseconds(100))
            await recorder.end()
            return FetchResult.stub
        }

        var superseded = [Task { try await viewModel.load() }]
        try await waitUntil { await recorder.startedCount == 1 }
        for id in 2...4 {
            superseded.append(Task { try await viewModel.load() })
            try await waitUntil { viewModel.state == .loading(requestID: id) }
        }

        // The latest caller simply awaits its result.
        let result = try await viewModel.load()

        #expect(result == FetchResult.stub)
        #expect(viewModel.state == .loaded(requestID: 5, FetchResult.stub))
        for task in superseded {
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        #expect(await recorder.startedCount == 2) // Only #1 and #5 ran; #2–#4 never started.
        #expect(await recorder.maxRunning == 1)   // #5 waited for #1 to stop.
        #expect(await recorder.ranOnMainThread == false)
        let messages = viewModel.log.map(\.message)
        for id in 2...4 {
            #expect(!messages.contains("#\(id) running, main thread: false"))
        }
    }

    @Test func cancellingCallerCancelsSerialRequest() async throws {
        let viewModel = SerialLandingPageViewModel {
            try await Task.sleep(for: .seconds(10))
            return FetchResult.stub
        }

        let caller = Task { try await viewModel.load() }
        try await waitUntil { viewModel.log.contains { $0.message.hasPrefix("#1 running") } }
        caller.cancel()

        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(viewModel.log.contains { $0.message == "#1 cancelled" })
        #expect(viewModel.state == .idle) // Not stuck in .loading.
    }

    @Test func reentrantLoadsKeepLatestState() async throws {
        let viewModel = SerialLandingPageViewModel {
            try await Task.sleep(for: .milliseconds(100))
            return FetchResult.stub
        }

        // #1 is suspended inside load() when #2 enters and replaces it.
        let first = Task { try await viewModel.load() }
        try await waitUntil { viewModel.log.contains { $0.message.hasPrefix("#1 running") } }
        let second = Task { try await viewModel.load() }

        await #expect(throws: CancellationError.self) { try await first.value }
        // #1 resumed after #2 started: it must leave #2's state alone.
        #expect(viewModel.state == .loading(requestID: 2))

        #expect(try await second.value == FetchResult.stub)
        #expect(viewModel.state == .loaded(requestID: 2, FetchResult.stub))
    }

    @Test func serialFailureIsThrownToCaller() async throws {
        let viewModel = SerialLandingPageViewModel { throw URLError(.notConnectedToInternet) }

        await #expect(throws: URLError.self) { try await viewModel.load() }
        guard case .failed(requestID: 1, _) = viewModel.state else {
            Issue.record("Expected failed state, got \(viewModel.state)")
            return
        }
    }

    // MARK: - Async latest

    @Test func asyncLatestStartsAtOnceAndReturnsOnlyLatest() async throws {
        let recorder = Recorder()
        let viewModel = AsyncLatestLandingPageViewModel {
            await recorder.start(onMainThread: isOnMainThread())
            // Keeps running after cancel(), so #2 overlaps #1 unless it waits.
            await uncancellableSleep(for: .milliseconds(200))
            await recorder.end()
            return FetchResult.stub
        }

        let first = Task { try await viewModel.load() }
        try await waitUntil { await recorder.startedCount == 1 }
        let result = try await viewModel.load()

        #expect(result == FetchResult.stub)
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(viewModel.state == .loaded(requestID: 2, FetchResult.stub))
        #expect(await recorder.maxRunning == 2)   // #2 did not wait for #1 to stop.
        #expect(await recorder.ranOnMainThread == false)
        #expect(!viewModel.log.contains { $0.message == "#1 finished, HTTP 200" })
    }

    @Test func asyncLatestStaleResultDoesNotOverwriteNewerState() async throws {
        // The fetch ignores cancellation, so #1 still returns a value after #2 replaced it.
        let viewModel = AsyncLatestLandingPageViewModel {
            try? await Task.sleep(for: .milliseconds(100))
            return FetchResult.stub
        }

        let first = Task { try await viewModel.load() }
        try await waitUntil { viewModel.log.contains { $0.message.hasPrefix("#1 running") } }
        let second = Task { try await viewModel.load() }

        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await second.value == FetchResult.stub)
        #expect(viewModel.state == .loaded(requestID: 2, FetchResult.stub))
    }

    @Test func cancellingCallerCancelsAsyncLatestRequest() async throws {
        let viewModel = AsyncLatestLandingPageViewModel {
            try await Task.sleep(for: .seconds(10))
            return FetchResult.stub
        }

        let caller = Task { try await viewModel.load() }
        try await waitUntil { viewModel.log.contains { $0.message.hasPrefix("#1 running") } }
        caller.cancel()

        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(viewModel.state == .idle) // Not stuck in .loading.

        // The cancelled request is no longer current, so the next one does not log "Cancel previous task".
        viewModel.clearLog()
        let next = Task { try await viewModel.load() }
        try await waitUntil { viewModel.log.contains { $0.message == "#2 started" } }
        #expect(!viewModel.log.contains { $0.message == "Cancel previous task" })
        next.cancel()
    }

    @Test func userCancelStopsAsyncLatestRequest() async throws {
        let viewModel = AsyncLatestLandingPageViewModel {
            try await Task.sleep(for: .seconds(10))
            return FetchResult.stub
        }

        let caller = Task { try await viewModel.load() }
        try await waitUntil { viewModel.log.contains { $0.message.hasPrefix("#1 running") } }
        viewModel.cancel()

        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(viewModel.state == .idle)
    }

    @Test func asyncLatestFailureIsThrownToCaller() async throws {
        let viewModel = AsyncLatestLandingPageViewModel { throw URLError(.notConnectedToInternet) }

        await #expect(throws: URLError.self) { try await viewModel.load() }
        guard case .failed(requestID: 1, _) = viewModel.state else {
            Issue.record("Expected failed state, got \(viewModel.state)")
            return
        }
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while await !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private extension FetchResult {
    static let stub = FetchResult(statusCode: 200, byteCount: 0, widgets: [], preview: "")
}

/// Sleeps for the full duration even if the current task is cancelled.
/// (`try? await Task.sleep` is not enough: it returns as soon as the task is cancelled.)
private func uncancellableSleep(for duration: Duration) async {
    await Task.detached { try? await Task.sleep(for: duration) }.value
}

/// Records how many operations started and how many ran at the same time.
private actor Recorder {
    private(set) var startedCount = 0
    private(set) var maxRunning = 0
    private(set) var ranOnMainThread = false
    private var running = 0

    func start(onMainThread: Bool) {
        startedCount += 1
        running += 1
        maxRunning = max(maxRunning, running)
        ranOnMainThread = ranOnMainThread || onMainThread
    }

    func end() {
        running -= 1
    }
}

struct LandingPageServiceTests {

    @Test func parsesWidgets() throws {
        let json = try JSONSerialization.jsonObject(with: Data("""
        {"view": {"widgets": [
            {"id": "topleagues", "name": "Top Leagues", "type": "TopLeagues", "content": {"_typ": "X", "leagues": [1, 2, 3]}},
            {"id": "empty", "name": "Empty", "type": "Other", "content": {"_typ": "Y"}}
        ]}}
        """.utf8))

        #expect(LandingPageService.widgets(in: json) == [
            .init(id: "topleagues", name: "Top Leagues", type: "TopLeagues", itemCount: 3),
            .init(id: "empty", name: "Empty", type: "Other", itemCount: 0),
        ])
    }
}
