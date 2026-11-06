import Foundation

/// Product strings compared in ISO 1.7.9 0x10032f148.
/// CoreAudio's model UID includes the product token followed by a vendor token.
public enum AirPodsModel: Int, CaseIterable, Sendable {
    case airPods = 0, airPods2, airPods3, airPods4, pro, pro2, pro3, max, max2

    /// Bluetooth PnP product ID (16-bit), e.g. 0x2013 for AirPods 3.
    public static func identify(productID: UInt16) -> Self? {
        identify(modelUID: String(format: "%04x", productID))
    }

    public static func identify(modelUID: String) -> Self? {
        guard let token = modelUID.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        switch token.lowercased() {
        case "2002": return .airPods
        case "200f": return .airPods2
        case "2013": return .airPods3
        case "201b", "2019": return .airPods4
        case "200e": return .pro
        case "2014", "2024": return .pro2
        case "2027": return .pro3
        case "200a": return .max
        case "201f", "202d": return .max2
        default: return nil
        }
    }

    /// User-facing product name for the device row. Only this row uses it; the
    /// native device name and existing toast/asset strings stay unchanged.
    public var displayName: String {
        switch self {
        case .airPods: return "AirPods"
        case .airPods2: return "AirPods 2"
        case .airPods3: return "AirPods 3"
        case .airPods4: return "AirPods 4"
        case .pro: return "AirPods Pro"
        case .pro2: return "AirPods Pro 2"
        case .pro3: return "AirPods Pro 3"
        case .max: return "AirPods Max"
        case .max2: return "AirPods Max 2"
        }
    }

    public var symbol: String {
        switch self {
        case .max, .max2: return "airpodsmax"
        case .airPods3: return "airpods.gen3"
        case .airPods4: return "airpods.gen4"
        case .pro3: return "airpods.pro.gen3"
        case .pro, .pro2: return "airpods.pro"
        default: return "airpods"
        }
    }
    /// Runtime fallback for macOS versions without the OS 26 Pro 3 symbol.
    public var fallbackSymbol: String? {
        self == .pro3 ? "airpods.pro" : nil
    }

    /// Max movies are selected separately using AirPodsMaxColor; older AirPods
    /// retain their symbol fallback when no matching movie is available.
    public var uncoloredMovie: String? {
        switch self {
        case .airPods3: return "airpods-3"
        case .airPods4: return "airpods-4"
        case .pro: return "airpods-pro"
        case .pro2: return "airpods-pro-2"
        case .pro3: return "airpods-pro-3"
        default: return nil
        }
    }
}
