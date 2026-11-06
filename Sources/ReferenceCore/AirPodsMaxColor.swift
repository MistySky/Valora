import Foundation

public enum AirPodsMaxColor: Int, CaseIterable {
    case spaceGray, skyBlue, silver, green, red, midnight, starlight, blue, orange, purple

    /// 0x10032f114, byte table 0x100493e66. Missing input uses tag 0 in the reference.
    public static func identify(rawColorID: Int?) -> Self {
        guard let rawColorID, rawColorID >= 0 else { return .spaceGray }
        let index = (rawColorID & 0x3f) - 2
        let table = [4, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 5, 6, 7, 8, 9]
        guard table.indices.contains(index) else { return .spaceGray }
        return Self(rawValue: table[index])!
    }

    /// Valid enum branches in 0x10031f95c, verified with raw ARM64 jump-table bytes
    /// and MOV/MOVK string construction. Its decompiled 256-case switch is invalid.
    public var movie: String {
        let suffixes = ["space-gray", "sky-blue", "silver", "green", "red", "midnight", "starlight", "blue", "orange", "purple"]
        return "airpods-max-" + suffixes[rawValue]
    }
}
