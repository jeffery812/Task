//
//  TaskDemoView.swift
//  Task
//

import SwiftUI

struct TaskDemoView<Model: TaskDemoModel>: View {
    let title: String
    let summary: String
    @State var model: Model
    /// Starts one request on `model`.
    let load: (Model) -> Void

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
            Button("Fetch", systemImage: "arrow.down.circle") {
                load(model)
            }
            Spacer()
            Button("Fetch ×5", systemImage: "bolt") {
                for _ in 0..<5 { load(model) }
            }
            Spacer()
            Button("Cancel", systemImage: "xmark.circle", role: .destructive, action: model.cancel)
        }
        .buttonStyle(.borderless)
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
