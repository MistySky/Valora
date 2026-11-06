import Foundation
import zlib

// QQ Music QRC decryption/format parsing.
//
// The QQ-specific DES implementation is a Swift adaptation of the MIT-licensed
// QQMusicDecoder by WXRIW (https://github.com/WXRIW/QQMusicDecoder), specifically
// DESHelper.cs/Decrypter.cs. It is not copied from the GPL Lyrimuse engine.
// The original MIT copyright notice is retained in
// docs/verification/v0012/source-license.md. This code is only used for the
// explicit public QRC probe and for validated word-timed lyrics.
public enum QQMusicQRC {
    public static let key = Array("!@#)(*$%123ZXC!@!@#)(NHL".utf8)

    /// Decrypt the HEX payload and return the inner QRC XML/plain text.
    public static func decrypt(hex: String) -> String? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count % 2 == 0,
              let cipher = Data(hexString: trimmed) else { return nil }
        guard cipher.count % 8 == 0, !cipher.isEmpty else { return nil }
        let schedule = QQDES.tripleDESKeySchedule(key: key, decrypt: true)
        var plain = Data()
        plain.reserveCapacity(cipher.count)
        var offset = 0
        while offset < cipher.count {
            let block = Array(cipher[offset..<min(offset + 8, cipher.count)])
            guard block.count == 8 else { return nil }
            let decrypted = QQDES.tripleDESCrypt(block: block, schedule: schedule)
            plain.append(contentsOf: decrypted)
            offset += 8
        }
        guard let inflated = inflate(plain), let text = String(data: inflated, encoding: .utf8) else {
            return nil
        }
        return text
    }

    /// Extract the first LyricContent attribute from the decrypted XML.
    public static func lyricContent(from decrypted: String) -> String? {
        guard let marker = decrypted.range(of: "LyricContent=\"") else { return nil }
        let afterMarker = decrypted[marker.upperBound...]
        let boundary = afterMarker.range(of: "<Lyric_")?.lowerBound ?? afterMarker.endIndex
        let segment = afterMarker[..<boundary]
        guard let close = segment.range(of: "\"/>", options: .backwards) else { return nil }
        let raw = String(segment[..<close.lowerBound])
        return raw
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Extract the encrypted HEX content from a lyric_download XML-like body.
    public static func contentHex(from body: String) -> String? {
        guard let marker = body.range(of: "<content"),
              let open = body.range(of: ">", range: marker.upperBound..<body.endIndex),
              let start = body.range(of: "<![CDATA[", range: open.upperBound..<body.endIndex),
              let end = body.range(of: "]]></content>", range: start.upperBound..<body.endIndex) else {
            return nil
        }
        return String(body[start.upperBound..<end.lowerBound])
    }

    /// Parse the decrypted inner QRC text into line/word timings. Returns nil
    /// when no line has at least one real word timing marker.
    public static func parseLyrics(decrypted: String) -> [LyricLine]? {
        guard let content = lyricContent(from: decrypted) else { return nil }
        let qrcLines = QRCParser.parse(content)
        let lines: [LyricLine] = qrcLines.compactMap { qrc in
            let words = qrc.words.compactMap { word -> LyricWord? in
                guard word.startMilliseconds >= 0, word.durationMilliseconds > 0,
                      !word.text.isEmpty else { return nil }
                return LyricWord(text: word.text,
                                 start: Double(word.startMilliseconds) / 1000,
                                 duration: Double(word.durationMilliseconds) / 1000)
            }
            guard !words.isEmpty else { return nil }
            let text = words.map(\.text).joined()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return LyricLine(start: Double(qrc.startMilliseconds) / 1000,
                             text: text, words: words)
        }
        guard !lines.isEmpty else { return nil }
        return lines
    }

    private static func inflate(_ data: Data) -> Data? {
        var destination = [UInt8](repeating: 0, count: 8 * 1024 * 1024)
        var destinationLength = uLongf(destination.count)
        let status = data.withUnsafeBytes { raw -> Int32 in
            guard let source = raw.bindMemory(to: Bytef.self).baseAddress else { return Z_DATA_ERROR }
            return uncompress(&destination, &destinationLength, source, uLong(data.count))
        }
        guard status == Z_OK, destinationLength <= uLong(destination.count) else { return nil }
        return Data(destination.prefix(Int(destinationLength)))
    }
}

enum QQDES {
    static let sboxes: [[UInt8]] = [
        [14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7, 0,15,7,4,14,2,13,1,10,6,12,11,9,5,3,8, 4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0, 15,12,8,2,4,9,1,7,5,11,3,14,10,0,6,13],
        [15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10, 3,13,4,7,15,2,8,15,12,0,1,10,6,9,11,5, 0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15, 13,8,10,1,3,15,4,2,11,6,7,12,0,5,14,9],
        [10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8, 13,7,0,9,3,4,6,10,2,8,5,14,12,11,15,1, 13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7, 1,10,13,0,6,9,8,7,4,15,14,3,11,5,2,12],
        [7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15, 13,8,11,5,6,15,0,3,4,7,2,12,1,10,14,9, 10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4, 3,15,0,6,10,10,13,8,9,4,5,11,12,7,2,14],
        [2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9, 14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6, 4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14, 11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3],
        [12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11, 10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8, 9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6, 4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13],
        [4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1, 13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6, 1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2, 6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12],
        [13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7, 1,15,13,8,10,3,7,4,12,5,6,11,0,14,9,2, 7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8, 2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11]
    ]
    static let keyRndShift: [UInt32] = [1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1]
    static let keyPermC: [Int] = [56,48,40,32,24,16,8,0,57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35]
    static let keyPermD: [Int] = [62,54,46,38,30,22,14,6,61,53,45,37,29,21,13,5,60,52,44,36,28,20,12,4,27,19,11,3]
    static let keyCompression: [Int] = [13,16,10,23,0,4,2,27,14,5,20,9,22,18,11,3,25,7,15,6,26,19,12,1,40,51,30,36,46,54,29,39,50,44,32,47,43,48,38,55,33,52,45,41,49,35,28,31]

    static func bitnum(_ a: [UInt8], _ b: Int, _ c: Int) -> UInt32 {
        UInt32((a[(b / 32) * 4 + 3 - (b % 32) / 8] >> (7 - b % 8)) & 1) << UInt32(c)
    }
    static func bitnumIntr(_ a: UInt32, _ b: Int, _ c: Int) -> UInt8 {
        UInt8(((a >> UInt32(31 - b)) & 1) << UInt32(c))
    }
    static func bitnumIntl(_ a: UInt32, _ b: Int, _ c: Int) -> UInt32 {
        ((a << UInt32(b)) & 0x80000000) >> UInt32(c)
    }
    static func sboxBit(_ a: UInt8) -> Int {
        Int((a & 0x20) | ((a & 0x1f) >> 1) | ((a & 1) << 4))
    }

    static func keySchedule(_ key: [UInt8], decrypt: Bool) -> [[UInt8]] {
        var schedule = [[UInt8]](repeating: [UInt8](repeating: 0, count: 6), count: 16)
        var c: UInt32 = 0, d: UInt32 = 0
        for i in 0..<28 {
            c |= bitnum(key, keyPermC[i], 31 - i)
            d |= bitnum(key, keyPermD[i], 31 - i)
        }
        for i in 0..<16 {
            let shift = keyRndShift[i]
            c = ((c << shift) | (c >> (28 - shift))) & 0xfffffff0
            d = ((d << shift) | (d >> (28 - shift))) & 0xfffffff0
            let target = decrypt ? 15 - i : i
            for j in 0..<24 {
                schedule[target][j / 8] |= bitnumIntr(c, keyCompression[j], 7 - (j % 8))
            }
            for j in 24..<48 {
                schedule[target][j / 8] |= bitnumIntr(d, keyCompression[j] - 27, 7 - (j % 8))
            }
        }
        return schedule
    }

    static func tripleDESKeySchedule(key: [UInt8], decrypt: Bool) -> [[[UInt8]]] {
        if decrypt {
            return [keySchedule(Array(key[16..<24]), decrypt: true),
                    keySchedule(Array(key[8..<16]), decrypt: false),
                    keySchedule(Array(key[0..<8]), decrypt: true)]
        }
        return [keySchedule(Array(key[0..<8]), decrypt: false),
                keySchedule(Array(key[8..<16]), decrypt: true),
                keySchedule(Array(key[16..<24]), decrypt: false)]
    }

    static func tripleDESCrypt(block: [UInt8], schedule: [[[UInt8]]]) -> [UInt8] {
        var value = block
        for keys in schedule { value = crypt(value, key: keys) }
        return value
    }

    static func initialPermutation(_ input: [UInt8]) -> (UInt32, UInt32) {
        let s0 = bitnum(input,57,31) | bitnum(input,49,30) | bitnum(input,41,29) | bitnum(input,33,28) | bitnum(input,25,27) | bitnum(input,17,26) | bitnum(input,9,25) | bitnum(input,1,24) | bitnum(input,59,23) | bitnum(input,51,22) | bitnum(input,43,21) | bitnum(input,35,20) | bitnum(input,27,19) | bitnum(input,19,18) | bitnum(input,11,17) | bitnum(input,3,16) | bitnum(input,61,15) | bitnum(input,53,14) | bitnum(input,45,13) | bitnum(input,37,12) | bitnum(input,29,11) | bitnum(input,21,10) | bitnum(input,13,9) | bitnum(input,5,8) | bitnum(input,63,7) | bitnum(input,55,6) | bitnum(input,47,5) | bitnum(input,39,4) | bitnum(input,31,3) | bitnum(input,23,2) | bitnum(input,15,1) | bitnum(input,7,0)
        let s1 = bitnum(input,56,31) | bitnum(input,48,30) | bitnum(input,40,29) | bitnum(input,32,28) | bitnum(input,24,27) | bitnum(input,16,26) | bitnum(input,8,25) | bitnum(input,0,24) | bitnum(input,58,23) | bitnum(input,50,22) | bitnum(input,42,21) | bitnum(input,34,20) | bitnum(input,26,19) | bitnum(input,18,18) | bitnum(input,10,17) | bitnum(input,2,16) | bitnum(input,60,15) | bitnum(input,52,14) | bitnum(input,44,13) | bitnum(input,36,12) | bitnum(input,28,11) | bitnum(input,20,10) | bitnum(input,12,9) | bitnum(input,4,8) | bitnum(input,62,7) | bitnum(input,54,6) | bitnum(input,46,5) | bitnum(input,38,4) | bitnum(input,30,3) | bitnum(input,22,2) | bitnum(input,14,1) | bitnum(input,6,0)
        return (s0, s1)
    }

    static func inversePermutation(_ state: (UInt32, UInt32)) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 8)
        let (s0, s1) = state
        out[3] = bitnumIntr(s1,7,7)|bitnumIntr(s0,7,6)|bitnumIntr(s1,15,5)|bitnumIntr(s0,15,4)|bitnumIntr(s1,23,3)|bitnumIntr(s0,23,2)|bitnumIntr(s1,31,1)|bitnumIntr(s0,31,0)
        out[2] = bitnumIntr(s1,6,7)|bitnumIntr(s0,6,6)|bitnumIntr(s1,14,5)|bitnumIntr(s0,14,4)|bitnumIntr(s1,22,3)|bitnumIntr(s0,22,2)|bitnumIntr(s1,30,1)|bitnumIntr(s0,30,0)
        out[1] = bitnumIntr(s1,5,7)|bitnumIntr(s0,5,6)|bitnumIntr(s1,13,5)|bitnumIntr(s0,13,4)|bitnumIntr(s1,21,3)|bitnumIntr(s0,21,2)|bitnumIntr(s1,29,1)|bitnumIntr(s0,29,0)
        out[0] = bitnumIntr(s1,4,7)|bitnumIntr(s0,4,6)|bitnumIntr(s1,12,5)|bitnumIntr(s0,12,4)|bitnumIntr(s1,20,3)|bitnumIntr(s0,20,2)|bitnumIntr(s1,28,1)|bitnumIntr(s0,28,0)
        out[7] = bitnumIntr(s1,3,7)|bitnumIntr(s0,3,6)|bitnumIntr(s1,11,5)|bitnumIntr(s0,11,4)|bitnumIntr(s1,19,3)|bitnumIntr(s0,19,2)|bitnumIntr(s1,27,1)|bitnumIntr(s0,27,0)
        out[6] = bitnumIntr(s1,2,7)|bitnumIntr(s0,2,6)|bitnumIntr(s1,10,5)|bitnumIntr(s0,10,4)|bitnumIntr(s1,18,3)|bitnumIntr(s0,18,2)|bitnumIntr(s1,26,1)|bitnumIntr(s0,26,0)
        out[5] = bitnumIntr(s1,1,7)|bitnumIntr(s0,1,6)|bitnumIntr(s1,9,5)|bitnumIntr(s0,9,4)|bitnumIntr(s1,17,3)|bitnumIntr(s0,17,2)|bitnumIntr(s1,25,1)|bitnumIntr(s0,25,0)
        out[4] = bitnumIntr(s1,0,7)|bitnumIntr(s0,0,6)|bitnumIntr(s1,8,5)|bitnumIntr(s0,8,4)|bitnumIntr(s1,16,3)|bitnumIntr(s0,16,2)|bitnumIntr(s1,24,1)|bitnumIntr(s0,24,0)
        return out
    }

    static func f(_ state: UInt32, key: [UInt8]) -> UInt32 {
        let t1 = bitnumIntl(state,31,0)|((state & 0xf0000000) >> 1)|bitnumIntl(state,4,5)|bitnumIntl(state,3,6)|((state & 0x0f000000) >> 3)|bitnumIntl(state,8,11)|bitnumIntl(state,7,12)|((state & 0x00f00000) >> 5)|bitnumIntl(state,12,17)|bitnumIntl(state,11,18)|((state & 0x000f0000) >> 7)|bitnumIntl(state,16,23)
        let t2 = bitnumIntl(state,15,0)|((state & 0x0000f000) << 15)|bitnumIntl(state,20,5)|bitnumIntl(state,19,6)|((state & 0x00000f00) << 13)|bitnumIntl(state,24,11)|bitnumIntl(state,23,12)|((state & 0x000000f0) << 11)|bitnumIntl(state,28,17)|bitnumIntl(state,27,18)|((state & 0x0000000f) << 9)|bitnumIntl(state,0,23)
        var l = [UInt8((t1 >> 24) & 0xff), UInt8((t1 >> 16) & 0xff), UInt8((t1 >> 8) & 0xff),
                 UInt8((t2 >> 24) & 0xff), UInt8((t2 >> 16) & 0xff), UInt8((t2 >> 8) & 0xff)]
        for i in 0..<6 { l[i] ^= key[i] }
        var result = (UInt32(sboxes[0][sboxBit(l[0] >> 2)]) << 28)
            | (UInt32(sboxes[1][sboxBit(((l[0] & 0x03) << 4) | (l[1] >> 4))]) << 24)
            | (UInt32(sboxes[2][sboxBit(((l[1] & 0x0f) << 2) | (l[2] >> 6))]) << 20)
            | (UInt32(sboxes[3][sboxBit(l[2] & 0x3f)]) << 16)
            | (UInt32(sboxes[4][sboxBit(l[3] >> 2)]) << 12)
            | (UInt32(sboxes[5][sboxBit(((l[3] & 0x03) << 4) | (l[4] >> 4))]) << 8)
            | (UInt32(sboxes[6][sboxBit(((l[4] & 0x0f) << 2) | (l[5] >> 6))]) << 4)
            | UInt32(sboxes[7][sboxBit(l[5] & 0x3f)])
        result = bitnumIntl(result,15,0)|bitnumIntl(result,6,1)|bitnumIntl(result,19,2)|bitnumIntl(result,20,3)|bitnumIntl(result,28,4)|bitnumIntl(result,11,5)|bitnumIntl(result,27,6)|bitnumIntl(result,16,7)|bitnumIntl(result,0,8)|bitnumIntl(result,14,9)|bitnumIntl(result,22,10)|bitnumIntl(result,25,11)|bitnumIntl(result,4,12)|bitnumIntl(result,17,13)|bitnumIntl(result,30,14)|bitnumIntl(result,9,15)|bitnumIntl(result,1,16)|bitnumIntl(result,7,17)|bitnumIntl(result,23,18)|bitnumIntl(result,13,19)|bitnumIntl(result,31,20)|bitnumIntl(result,26,21)|bitnumIntl(result,2,22)|bitnumIntl(result,8,23)|bitnumIntl(result,18,24)|bitnumIntl(result,12,25)|bitnumIntl(result,29,26)|bitnumIntl(result,5,27)|bitnumIntl(result,21,28)|bitnumIntl(result,10,29)|bitnumIntl(result,3,30)|bitnumIntl(result,24,31)
        return result
    }

    static func crypt(_ input: [UInt8], key: [[UInt8]]) -> [UInt8] {
        var state = initialPermutation(input)
        for index in 0..<15 {
            let t = state.1
            state.1 = f(state.1, key: key[index]) ^ state.0
            state.0 = t
        }
        state.0 = f(state.1, key: key[15]) ^ state.0
        return inversePermutation(state)
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let value = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }
        self.init(bytes)
    }
}
