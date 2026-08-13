import AppKit
import VOEBBKit

/// Ampelfarbe eines Mediums für die Mac-UI (gleiche Schwellen wie bookEmoji).
extension Loan {
    var urgencyNSColor: NSColor {
        if isOverdue || daysUntilDue < 7 { return .systemRed }
        if daysUntilDue <= 14 { return .systemOrange }
        return .systemGreen
    }
}

/// Baut einen Menü-Titel mit farbigem Ampel-Punkt: "● Titel…"
func dotMenuTitle(_ text: String, color: NSColor, indent: String = "  ") -> NSAttributedString {
    let result = NSMutableAttributedString()
    let font = NSFont.menuFont(ofSize: 0)
    result.append(NSAttributedString(string: "\(indent)●  ", attributes: [
        .font: font,
        .foregroundColor: color,
    ]))
    result.append(NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: NSColor.labelColor,
    ]))
    return result
}
