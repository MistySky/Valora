import Foundation
import Observation

/// Owns one bounded Codex quota read at a time. It never sends a model request,
/// changes a login, reads auth.json, starts a thread/turn, or consumes a reset
/// credit. The only transport allowed is the app-server allowlist in
/// `CodexAppServerClient`.
@MainActor
@Observable
final class CodexUsageProvider {
    private(set) var snapshot: CodexUsageSnapshot = .initial
    private(set) var isRefreshing = false
    var isRunningForTest: Bool { active }

    @ObservationIgnored private let readLimits: @Sendable () async throws -> CodexRateLimits
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored let refreshInterval: TimeInterval
    @ObservationIgnored let freshnessInterval: TimeInterval
    @ObservationIgnored let failureCooldown: TimeInterval
    @ObservationIgnored private var active = false
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var scheduledRefresh: (any CodexScheduledRefresh)?
    @ObservationIgnored private let scheduler: any CodexRefreshScheduling
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var lastFailureAt: Date?
    @ObservationIgnored private(set) var requestCount = 0
    @ObservationIgnored private(set) var completionCount = 0
    @ObservationIgnored private(set) var discardedCount = 0
    @ObservationIgnored private(set) var coalescedOpenCount = 0

    init(readLimits: @escaping @Sendable () async throws -> CodexRateLimits,
         now: @escaping @Sendable () -> Date = Date.init,
         refreshInterval: TimeInterval = 180,
         freshnessInterval: TimeInterval = 45,
         failureCooldown: TimeInterval = 60,
         scheduler: any CodexRefreshScheduling = CodexTimerRefreshScheduler()) {
        self.readLimits = readLimits
        self.now = now
        self.refreshInterval = max(30, refreshInterval)
        self.freshnessInterval = max(1, freshnessInterval)
        self.failureCooldown = max(1, failureCooldown)
        self.scheduler = scheduler
    }

    func start() {
        guard !active else { return }
        active = true
        // An old, cancelled request remains the one actual in-flight owner.
        // Restart only queues a latest request until that work really returns.
        if inFlight != nil {
            pendingRefresh = true
            return
        }
        requestRefresh(force: true)
    }

    func stop() {
        active = false
        generation &+= 1
        scheduledRefresh?.cancel()
        scheduledRefresh = nil
        // Do NOT clear inFlight/isRefreshing: a non-cooperative provider or
        // app-server child may still be alive. The completion path clears the
        // latch after the old work actually ends.
        inFlight?.cancel()
        pendingRefresh = false
        snapshot = .initial
    }

    /// Opening the popover reuses a fresh snapshot; it does not start a new
    /// app-server process. A stale snapshot may request one coalesced refresh.
    func refreshOnOpen() {
        guard active else { return }
        let current = now()
        if snapshot.hasSuccessfulData {
            // A cached snapshot is displayed during any refresh; only a
            // genuinely stale cache may trigger a read. A failed background
            // read must still honor its cooldown even though the snapshot
            // remains ready with old values.
            if let observed = snapshot.observedAt,
               current.timeIntervalSince(observed) < freshnessInterval {
                return
            }
            if let failed = lastFailureAt,
               current.timeIntervalSince(failed) < failureCooldown {
                return
            }
        } else if snapshot.status != .loading {
            if let failed = lastFailureAt,
               current.timeIntervalSince(failed) < failureCooldown {
                return
            }
        }
        // A click while a valid read is already in flight is covered by that
        // read; do not queue a redundant pending pass.
        guard inFlight == nil else { return }
        requestRefresh(force: false)
    }

    private func requestRefresh(force: Bool) {
        guard active else { return }
        if inFlight != nil {
            if !pendingRefresh { pendingRefresh = true }
            return
        }
        scheduledRefresh?.cancel()
        scheduledRefresh = nil
        _ = force
        startRequest()
    }

    private func startRequest() {
        guard active, inFlight == nil else { return }
        isRefreshing = true
        // A background refresh keeps the last successful snapshot visible.
        // Only the first read, with no successful cache, may show loading.
        if !snapshot.hasSuccessfulData {
            snapshot = .loading()
        }
        requestCount &+= 1
        generation &+= 1
        let requestGeneration = generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let result: Result<CodexRateLimits, Error>
            do {
                result = .success(try await self.readLimits())
            } catch {
                result = .failure(error)
            }
            self.finishRequest(requestGeneration, result: result)
        }
        inFlight = task
    }

    private func finishRequest(_ requestGeneration: UInt64, result: Result<CodexRateLimits, Error>) {
        // Always release the actual ownership latch, even when this result is
        // stale or the provider was stopped/restarted. The generation only
        // decides whether it may commit.
        inFlight = nil
        isRefreshing = false
        completionCount &+= 1
        if active, requestGeneration == generation {
            switch result {
            case .success(let reading):
                consecutiveFailures = 0
                lastFailureAt = nil
                snapshot = CodexUsageSnapshot(reading: reading, now: now())
            case .failure(let error):
                consecutiveFailures += 1
                lastFailureAt = now()
                if snapshot.hasSuccessfulData {
                    var stale = snapshot
                    stale.refreshErrorMessage = Self.failureMessage(error)
                    snapshot = stale
                } else {
                    snapshot = Self.failureSnapshot(error)
                }
            }
        } else {
            discardedCount &+= 1
        }
        guard active else { return }
        if pendingRefresh {
            pendingRefresh = false
            startRequest()
            return
        }
        scheduleNext()
    }

    private func scheduleNext() {
        scheduledRefresh?.cancel()
        let base = refreshInterval
        let backoff = min(900, base * pow(2, Double(min(consecutiveFailures, 3))))
        // A reset is a real service event, not a local percentage. If it is
        // sooner than the normal 180s cadence, refresh at that boundary; the
        // service response remains the only source of the new value.
        let resetBoundaries = [snapshot.fiveHour?.resetsAt, snapshot.week?.resetsAt]
            .compactMap { $0 }
            .map { $0.timeIntervalSince(now()) }
            .filter { $0 > 0 }
        let delay = resetBoundaries.min().map { min(backoff, $0) } ?? backoff
        scheduledRefresh = scheduler.schedule(after: max(1, delay)) { [weak self] in
            self?.requestRefresh(force: true)
        }
    }

    private static func failureMessage(_ error: Error) -> String {
        if let codex = error as? CodexUsageError {
            switch codex {
            case .missingEngine: return "未找到本机 Codex 引擎"
            case .notSignedIn, .processExited: return "Codex 未登录或登录已失效"
            case .timeout: return "额度读取超时"
            case .protocolError(let message): return message
            case .outputLimit: return "Codex 输出超过上限"
            }
        }
        return error.localizedDescription
    }

    private static func failureSnapshot(_ error: Error) -> CodexUsageSnapshot {
        if let error = error as? CodexUsageError {
            switch error {
            case .missingEngine: return .failure(.missingEngine)
            case .notSignedIn, .processExited: return .failure(.notSignedIn)
            case .timeout: return .failure(.timedOut)
            case .protocolError(let message): return .failure(.protocolError, message: message)
            case .outputLimit: return .failure(.protocolError, message: "Codex 输出超过上限")
            }
        }
        return .failure(.unavailable, message: error.localizedDescription)
    }
}

extension CodexUsageSnapshot {
    init(reading: CodexRateLimits, now: Date) {
        self.init(status: .ready,
                  fiveHour: reading.fiveHour, week: reading.week,
                  resetAvailableCount: reading.resetAvailableCount,
                  resetCredits: reading.resetCredits,
                  observedAt: now,
                  message: reading.hasQuotaWindows ? nil : "额度数据未提供")
    }
}
