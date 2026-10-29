//
//  TaskDemoView.swift
//  Task
//

import SwiftUI

struct TaskDemoView<Model: TaskDemoModel>: View {
    let title: String
    let summary: String
    @State var model: Model
    /// Starts one request on `model` and returns its result once it is loaded.
    /// Returns `nil` for fire-and-forget models whose result only shows up in `model.state`.
    /// Throws `CancellationError` when a newer request replaced this one.
    let load: (Model) async throws -> FetchResult?

    /// Callers still awaiting `load`.
    @State private var awaitingCount = 0
    /// What the last caller that was not replaced got back from `load`.
    @State private var callerOutcome: CallerOutcome?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    controls
                } footer: {
                    Text(summary)
                }

                Section("Result") {
                    result
                }

                if awaitingCount > 0 || callerOutcome != nil {
                    Section("Returned to caller") {
                        caller
                    }
                }

                Section {
                    ForEach(model.log) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.date, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                        }
                        .font(.caption.monospaced())
                    }
                } header: {
                    HStack {
                        Text("Task log")
                        Spacer()
                        Button("Clear", action: model.clearLog)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(title)
        }
    }

    private var controls: some View {
        HStack {
            Button("Fetch", systemImage: "arrow.down.circle", action: startLoad)
            Spacer()
            Button("Fetch ×5", systemImage: "bolt") {
                for _ in 0..<5 { startLoad() }
            }
            Spacer()
            Button("Cancel", systemImage: "xmark.circle", role: .destructive, action: model.cancel)
        }
        .buttonStyle(.borderless)
    }

    /// Awaits `load` like any caller would, then shows what it returned.
    private func startLoad() {
        awaitingCount += 1
        Task {
            defer { awaitingCount -= 1 }
            do {
                if let value = try await load(model) {
                    callerOutcome = .loaded(value)
                }
            } catch is CancellationError {
                // Replaced by a newer request, or cancelled: the newer caller reports its own outcome.
            } catch {
                callerOutcome = .failed(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private var caller: some View {
        if awaitingCount > 0 {
            HStack {
                ProgressView()
                Text("Awaiting load()… (\(awaitingCount) \(awaitingCount == 1 ? "caller" : "callers"))")
            }
        } else {
            switch callerOutcome {
            case .loaded(let value):
                Label("Loaded · HTTP \(value.statusCode) · \(value.widgets.count) widgets", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label("Failed: \(message)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.state {
        case .idle:
            Text("Tap Fetch to start.")
                .foregroundStyle(.secondary)
        case .loading(let requestID):
            HStack {
                ProgressView()
                Text("Request #\(requestID) running…")
            }
        case .loaded(let requestID, let result):
            Text("Request #\(requestID) · HTTP \(result.statusCode) · \(result.byteCount.formatted(.byteCount(style: .file)))")
                .font(.headline)
                .foregroundStyle((200..<300).contains(result.statusCode) ? .green : .orange)
            ForEach(result.widgets) { widget in
                LabeledContent {
                    Text("\(widget.itemCount) items")
                } label: {
                    Text(widget.name)
                    Text(widget.type)
                }
            }
            DisclosureGroup("Raw JSON (first 4,000 chars)") {
                ScrollView(.horizontal) {
                    Text(result.preview)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        case .failed(let requestID, let message):
            Label("Request #\(requestID) failed: \(message)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}

private enum CallerOutcome {
    case loaded(FetchResult)
    case failed(String)
}
