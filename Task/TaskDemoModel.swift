//
//  TaskDemoModel.swift
//  Task
//

import Foundation
import Observation

enum LoadState: Equatable {
    case idle
    case loading(requestID: Int)
    case loaded(requestID: Int, FetchResult)
    case failed(requestID: Int, message: String)
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
}

/// What `TaskDemoView` needs from a view model, so each strategy can share the same screen.
/// `load` is not part of it: each view model has its own signature, and the view gets it as a closure.
protocol TaskDemoModel: AnyObject, Observable {
    var state: LoadState { get }
    var log: [LogEntry] { get }
    func cancel()
    func clearLog()
}

/// `Thread.isMainThread` is unavailable from async code in Swift 6; a synchronous wrapper is fine for logging.
nonisolated func isOnMainThread() -> Bool {
    Thread.isMainThread
}
