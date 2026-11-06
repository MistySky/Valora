import Foundation

/// One Codex rate-limit window. A missing percentage/reset stays nil; zero is
/// preserved only when the service actually sent numeric zero.
struct CodexQuotaWindow: Equatable, Sendable {
    let usedPercent: Double?
    let resetsAt: Date?

    /// The official UI reports remaining quota. Protocol fields stay
    /// `usedPercent`; this is the one derived display value.
    var remainingPercent: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }
}

struct CodexResetCredit: Identifiable, Equatable, Sendable {
    let id: String
    let expiresAt: Date?

    var expirationDate: Date? { expiresAt }
}

/// Minimal parsed result of Codex app-server `account/rateLimits/read`.
/// No account/email, transcript, token or model data is represented here.
struct CodexRateLimits: Equatable, Sendable {
    let fiveHour: CodexQuotaWindow?
    let week: CodexQuotaWindow?
    let resetAvailableCount: Int?
    let resetCredits: [CodexResetCredit]
    let observedAt: Date

    var hasQuotaWindows: Bool { fiveHour != nil || week != nil }
}

enum CodexUsageStatus: Equatable, Sendable {
    case unavailable
    case loading
    case ready
    case missingEngine
    case notSignedIn
    case timedOut
    case protocolError

    var displayMessage: String? {
        switch self {
        case .ready, .loading: return nil
        case .unavailable: return "额度暂不可用"
        case .missingEngine: return "未找到本机 Codex 引擎"
        case .notSignedIn: return "Codex 未登录或登录已失效"
        case .timedOut: return "额度读取超时"
        case .protocolError: return "额度接口暂不兼容"
        }
    }
}

struct CodexUsageSnapshot: Equatable, Sendable {
    var status: CodexUsageStatus
    var fiveHour: CodexQuotaWindow?
    var week: CodexQuotaWindow?
    var resetAvailableCount: Int?
    var resetCredits: [CodexResetCredit]
    var observedAt: Date?
    var message: String?
    /// Set when a later background read failed but an earlier successful
    /// snapshot is still displayed.
    var refreshErrorMessage: String? = nil

    var hasSuccessfulData: Bool { status == .ready && observedAt != nil }

    static let initial = CodexUsageSnapshot(
        status: .unavailable, fiveHour: nil, week: nil,
        resetAvailableCount: nil, resetCredits: [], observedAt: nil, message: nil)

    static func loading() -> CodexUsageSnapshot {
        .init(status: .loading, fiveHour: nil, week: nil,
              resetAvailableCount: nil, resetCredits: [], observedAt: nil, message: nil)
    }

    static func failure(_ status: CodexUsageStatus, message: String? = nil) -> CodexUsageSnapshot {
        .init(status: status, fiveHour: nil, week: nil,
              resetAvailableCount: nil, resetCredits: [], observedAt: nil,
              message: message ?? status.displayMessage)
    }

    /// Kept as the raw used-percent projection for internal compatibility.
    var fiveHourPercentText: String { Self.percentText(fiveHour?.usedPercent) }
    var weekPercentText: String { Self.percentText(week?.usedPercent) }

    /// Display values: official remaining quota, never a fabricated 100% when
    /// the service did not provide a percentage.
    var fiveHourRemainingPercentText: String { Self.percentText(fiveHour?.remainingPercent) }
    var weekRemainingPercentText: String { Self.percentText(week?.remainingPercent) }

    private static func percentText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--%" }
        return "\(Int(value.rounded()))%"
    }
}

enum CodexUsageParseError: Error, Equatable {
    case invalidResponse
}

/// Transport failures, kept separate from protocol parsing so the UI can say
/// what actually happened instead of showing stale data as fresh.
enum CodexUsageError: Error, Equatable {
    case missingEngine
    case notSignedIn
    case processExited
    case timeout
    case protocolError(String)
    case outputLimit
}

/// Parses the strict subset needed by this feature.
enum CodexRateLimitsParser {
    static func parse(data: Data, now: Date = Date()) throws -> CodexRateLimits {
        let object = try? JSONSerialization.jsonObject(with: data)
        return try parse(object: object, now: now)
    }

    static func parse(object: Any?, now: Date = Date()) throws -> CodexRateLimits {
        guard let root = object as? [String: Any] else { throw CodexUsageParseError.invalidResponse }

        let mapKeys = ["rateLimitsByLimitId", "rate_limits_by_limit_id"]
        let legacyKeys = ["rateLimits", "rate_limits"]
        let mapKey = mapKeys.first { root[$0] != nil }
        let legacyKey = legacyKeys.first { root[$0] != nil }
        let bucket: [String: Any]?
        if let mapKey {
            let rawMap = root[mapKey]
            if rawMap is NSNull {
                // The protocol field is nullable. A null map is absent, so the
                // legacy field may be used only for this explicit null case.
                bucket = try legacyBucket(root, key: legacyKey)
            } else if let map = rawMap as? [String: Any] {
                // A present map is authoritative, including an empty map.
                // Other model buckets never contribute to global Codex rows.
                if map.keys.contains("codex") {
                    let rawCodex = map["codex"]
                    if rawCodex is NSNull {
                        bucket = nil
                    } else if let codex = rawCodex as? [String: Any] {
                        bucket = codex
                    } else {
                        throw CodexUsageParseError.invalidResponse
                    }
                } else {
                    bucket = nil
                }
            } else {
                // Wrong scalar/array types are protocol failures; never fall
                // back to stale legacy data.
                throw CodexUsageParseError.invalidResponse
            }
        } else {
            bucket = try legacyBucket(root, key: legacyKey)
        }

        var fiveHour: CodexQuotaWindow?
        var week: CodexQuotaWindow?
        if let bucket {
            for slot in ["primary", "secondary"] {
                guard let raw = bucket[slot] as? [String: Any] else { continue }
                guard let duration = integer(raw.value(forKeys: ["windowDurationMins", "window_duration_mins"])),
                      duration == 300 || duration == 10_080 else { continue }
                let window = CodexQuotaWindow(
                    usedPercent: validPercent(raw.value(forKeys: ["usedPercent", "used_percent"])),
                    resetsAt: date(raw.value(forKeys: ["resetsAt", "resets_at"])))
                if duration == 300, fiveHour == nil { fiveHour = window }
                if duration == 10_080, week == nil { week = window }
            }
        }

        let credits = parseResetCredits(root.value(forKeys: ["rateLimitResetCredits", "rate_limit_reset_credits"]))
        return CodexRateLimits(fiveHour: fiveHour, week: week,
                               resetAvailableCount: credits.count, resetCredits: credits.credits,
                               observedAt: now)
    }

    private static func legacyBucket(_ root: [String: Any], key: String?) throws -> [String: Any]? {
        guard let key else { return nil }
        let raw = root[key]
        if raw is NSNull { return nil }
        guard let bucket = raw as? [String: Any] else { throw CodexUsageParseError.invalidResponse }
        return bucket
    }

    private static func parseResetCredits(_ value: Any?) -> (count: Int?, credits: [CodexResetCredit]) {
        guard let value = value as? [String: Any] else { return (nil, []) }
        let count = integer(value.value(forKeys: ["availableCount", "available_count"])).flatMap { $0 >= 0 ? $0 : nil }
        let rawCredits = (value.value(forKeys: ["credits"]) as? [Any]) ?? []
        var parsed: [CodexResetCredit] = []
        for (offset, item) in rawCredits.enumerated() {
            guard let item = item as? [String: Any] else { continue }
            let id = (item.value(forKeys: ["id", "creditId", "credit_id"]) as? String)
                ?? "credit-\(offset + 1)"
            parsed.append(CodexResetCredit(id: id, expiresAt: date(item.value(forKeys: ["expiresAt", "expires_at"]))))
        }
        // True expiry order; credits without an expiry stay after dated ones.
        parsed.sort {
            switch ($0.expiresAt, $1.expiresAt) {
            case let (lhs?, rhs?): return lhs < rhs
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return $0.id < $1.id
            }
        }
        // Stable unique ForEach identity for duplicate service IDs. Do not
        // drop or merge credits and do not alter their count or expiry.
        var seen: [String: Int] = [:]
        parsed = parsed.map { credit in
            let occurrence = (seen[credit.id] ?? 0) + 1
            seen[credit.id] = occurrence
            guard occurrence > 1 else { return credit }
            return CodexResetCredit(id: "\(credit.id)#\(occurrence)", expiresAt: credit.expiresAt)
        }
        return (count, parsed)
    }

    /// JSONSerialization bridges numeric 0/1 as `NSNumber` whose `is Bool`
    /// check is true on Darwin. Use objCType to reject actual JSON booleans
    /// while retaining numeric zero and one as valid percentages/counts.
    private static func numeric(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber else { return nil }
        return String(cString: number.objCType) == "c" ? nil : number
    }

    private static func validPercent(_ value: Any?) -> Double? {
        guard let number = numeric(value) else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite, (0...100).contains(percent) else { return nil }
        return percent
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = numeric(value) else { return nil }
        let double = number.doubleValue
        // Int.max is not exactly representable as Double (it rounds to 2^63).
        // Use an exclusive upper bound so a rounded boundary cannot trap Int().
        let minBound = -9_223_372_036_854_775_808.0 // -2^63
        let maxBoundExclusive = 9_223_372_036_854_775_808.0 // 2^63
        guard double.isFinite, double.rounded() == double,
              double >= minBound, double < maxBoundExclusive else { return nil }
        return Int(double)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let number = numeric(value) else { return nil }
        let seconds = number.doubleValue
        guard seconds.isFinite, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func value(forKeys keys: [String]) -> Any? {
        for key in keys {
            if let value = self[key] { return value }
        }
        return nil
    }
}
