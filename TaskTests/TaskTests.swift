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

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
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
