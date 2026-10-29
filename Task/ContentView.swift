//
//  ContentView.swift
//  Task
//
//  Created by Zhihui Tang on 2026-10-16.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Cancel Previous", systemImage: "arrow.uturn.backward.circle") {
                TaskDemoView(
                    title: "Cancel Previous",
                    summary: "Each request waits 2 s before calling the API. Tap \"Fetch\" repeatedly: the previous task is cancelled and the new one starts at once, so a cancelled task may briefly overlap the new one.",
                    model: LandingPageViewModel()
                ) { model in
                    // Fire-and-forget: the result only reaches the view through `model.state`.
                    model.load()
                    return nil
                }
            }
            Tab("Serial Latest", systemImage: "list.number") {
                TaskDemoView(
                    title: "Serial Latest",
                    summary: "Requests run on a background thread, one at a time. A new request cancels the running one and waits for it to stop before starting; requests replaced while waiting never run.",
                    model: SerialLandingPageViewModel()
                ) { model in
                    // Awaits the result; throws CancellationError when a newer load() replaces it.
                    try await model.load()
                }
            }
            Tab("Async Latest", systemImage: "bolt.circle") {
                TaskDemoView(
                    title: "Async Latest",
                    summary: "load() is async and returns the result. A new request cancels the previous one and starts at once without waiting for it; only the newest caller gets a value, the others get CancellationError.",
                    model: AsyncLatestLandingPageViewModel()
                ) { model in
                    try await model.load()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
