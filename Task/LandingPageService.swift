//
//  LandingPageService.swift
//  Task
//

import Foundation

/// `nonisolated`: a plain value passed between actors. Without it the target's default
/// MainActor isolation would also tie its Equatable conformance to the main actor.
nonisolated struct FetchResult: Equatable, Sendable {
    struct Widget: Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let type: String
        let itemCount: Int
    }

    let statusCode: Int
    let byteCount: Int
    let widgets: [Widget]
    /// Beginning of the pretty-printed JSON. The full body is ~500 KB, too large for a single Text view.
    let preview: String
}

/// Performs the network request off the main actor.
nonisolated struct LandingPageService: Sendable {
    static let url = URL(string: "https://sportsbff-ams.kindredext.net/sports-api/api/v2/views/configured-landing-page?_typ=GetConfiguredLandingPageView&clientOffset=-120&topLeagueCategoryRn=")!

    /// Artificial delay before the request, so cancellation is easy to observe in the demo.
    var delay: Duration = .seconds(2)

    static let headers = [
        "locale": "en_GB",
        "jurisdiction": "UK",
        "ksp_jurisdiction": "mga",
        "Brand": "unibet",
    ]

    /// `@concurrent`: with Approachable Concurrency, a plain nonisolated async function runs on the
    /// caller's actor, so parsing the ~500 KB response would block the main thread.
    @concurrent
    func fetch() async throws -> FetchResult {
        // Task.sleep is cancellation-aware: it throws CancellationError as soon as the task is cancelled.
        try await Task.sleep(for: delay)

        var request = URLRequest(url: Self.url)
        for (field, value) in Self.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        // URLSession's async API is also cancellation-aware: it throws URLError(.cancelled).
        let (data, response) = try await URLSession.shared.data(for: request)

        // For CPU-bound work you have to check cancellation yourself.
        try Task.checkCancellation()

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = try? JSONSerialization.jsonObject(with: data)
        return FetchResult(
            statusCode: statusCode,
            byteCount: data.count,
            widgets: Self.widgets(in: json),
            preview: String(Self.prettyPrinted(json, fallback: data).prefix(4_000))
        )
    }

    /// Picks `view.widgets[]` out of the response. Item count = length of the first array in `content`.
    static func widgets(in json: Any?) -> [FetchResult.Widget] {
        guard
            let root = json as? [String: Any],
            let view = root["view"] as? [String: Any],
            let widgets = view["widgets"] as? [[String: Any]]
        else { return [] }

        return widgets.enumerated().map { index, widget in
            let content = widget["content"] as? [String: Any] ?? [:]
            let itemCount = content.values.lazy.compactMap { ($0 as? [Any])?.count }.first ?? 0
            return FetchResult.Widget(
                id: widget["id"] as? String ?? "\(index)",
                name: widget["name"] as? String ?? "—",
                type: widget["type"] as? String ?? "—",
                itemCount: itemCount
            )
        }
    }

    static func prettyPrinted(_ json: Any?, fallback data: Data) -> String {
        guard
            let json,
            let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: pretty, encoding: .utf8)
        else {
            return String(decoding: data, as: UTF8.self)
        }
        return string
    }
}
