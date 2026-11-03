import Foundation

@MainActor
protocol CodexScheduledRefresh: AnyObject {
    func cancel()
}

@MainActor
protocol CodexRefreshScheduling: AnyObject {
    func schedule(after interval: TimeInterval,
                  action: @escaping @MainActor () -> Void) -> any CodexScheduledRefresh
}

/// Production scheduler: one run-loop timer per provider. The provider owns
/// and cancels the token, so no timer survives stop or a newer schedule.
@MainActor
final class CodexTimerRefreshScheduler: CodexRefreshScheduling {
    private final class Token: CodexScheduledRefresh {
        let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }

    func schedule(after interval: TimeInterval,
                  action: @escaping @MainActor () -> Void) -> any CodexScheduledRefresh {
        let timer = Timer(timeInterval: max(0.001, interval), repeats: false) { _ in
            Task { @MainActor in action() }
        }
        timer.tolerance = min(30, max(0.1, interval * 0.2))
        RunLoop.main.add(timer, forMode: .common)
        return Token(timer)
    }
}
