import Foundation

/// 1.7.9: MediaPlayer 0x1000d35c8 and QuickPeek 0x100155b64
/// route through 0x100379b10 -> 0x10027a2d8 when hideSongTitleExtras is true.
/// The original walks Swift Characters with independent ASCII bracket depths;
/// it does not normalize whitespace inside the remaining title or use a regex.
public enum MusicTitleFormatting: Sendable {
    public static func displayTitle(_ title: String, hideExtras: Bool) -> String {
        guard hideExtras else { return title }
        var parentheses = 0
        var brackets = 0
        var stripped = ""
        for character in title {
            switch character {
            case "(": parentheses += 1
            case "[": brackets += 1
            case ")":
                if parentheses > 0 { parentheses -= 1 }
                else if brackets == 0 { stripped.append(character) }
            case "]":
                if brackets > 0 { brackets -= 1 }
                else if parentheses == 0 { stripped.append(character) }
            default:
                if parentheses == 0 && brackets == 0 { stripped.append(character) }
            }
        }
        let result = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }
}
