import Foundation

/// Chrome's native-messaging wire format: a 4-byte little-endian byte count
/// followed by UTF-8 JSON. The same framing is used on Valora's local socket
/// so a host/extension message cannot be mistaken for an unframed stream.
public enum ChromeNativeFraming {
    public static func read(from handle: FileHandle) throws -> Data? {
        guard let lengthData = try handle.read(upToCount: 4), !lengthData.isEmpty else {
            return nil
        }
        guard lengthData.count == 4 else { throw ChromeBridgeProtocolError.malformedFrame }
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        guard length > 0 else { throw ChromeBridgeProtocolError.malformedFrame }
        guard Int(length) <= ValoraChromeBridge.maxMessageBytes else {
            throw ChromeBridgeProtocolError.messageTooLarge
        }
        guard let data = try handle.read(upToCount: Int(length)), data.count == Int(length) else {
            throw ChromeBridgeProtocolError.malformedFrame
        }
        return data
    }

    public static func encode(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= ValoraChromeBridge.maxMessageBytes else {
            throw ChromeBridgeProtocolError.messageTooLarge
        }
        var length = UInt32(data.count).littleEndian
        return Data(bytes: &length, count: 4) + data
    }

    public static func write(_ data: Data, to handle: FileHandle) throws {
        try handle.write(contentsOf: encode(data))
    }

    public static func readJSON(from handle: FileHandle) throws -> [String: Any]? {
        guard let data = try read(from: handle) else { return nil }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChromeBridgeProtocolError.invalidMessage
        }
        return object
    }

    public static func writeJSON(_ object: [String: Any], to handle: FileHandle) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ChromeBridgeProtocolError.invalidMessage
        }
        try write(JSONSerialization.data(withJSONObject: object), to: handle)
    }

    public static func decodeSingleJSON(_ data: Data) throws -> [String: Any] {
        guard data.count >= 5 else { throw ChromeBridgeProtocolError.malformedFrame }
        let length = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        guard Int(length) <= ValoraChromeBridge.maxMessageBytes,
              data.count == 4 + Int(length),
              let object = try JSONSerialization.jsonObject(with: data.dropFirst(4)) as? [String: Any] else {
            throw ChromeBridgeProtocolError.malformedFrame
        }
        return object
    }
}
