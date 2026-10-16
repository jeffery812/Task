//
//  ContentView.swift
//  Task
//
//  Created by Zhihui Tang on 2026-10-16.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = LandingPageViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    controls
                } footer: {
                    Text("Each request waits 2 s before calling the API. Tap \"Fetch\" repeatedly: older tasks are cancelled and only the newest one shows its result.")
                }

                Section("Result") {
                    result
                }

                Section {
                    ForEach(viewModel.log) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.date, format: .dateTime.hour().minute().second())
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                        }
                        .font(.caption.monospaced())
                    }
                } header: {
                    HStack {
                        Text("Task log")
                        Spacer()
                        Button("Clear", action: viewModel.clearLog)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Single Task Demo")
        }
    }

    private var controls: some View {
        HStack {
            Button("Fetch", systemImage: "arrow.down.circle", action: viewModel.load)
            Spacer()
            Button("Fetch ×5", systemImage: "bolt") {
                for _ in 0..<5 { viewModel.load() }
            }
            Spacer()
            Button("Cancel", systemImage: "xmark.circle", role: .destructive, action: viewModel.cancel)
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var result: some View {
        switch viewModel.state {
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

#Preview {
    ContentView()
}
