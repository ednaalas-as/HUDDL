import Foundation

/// Form validation rules taken from the Figma error states.
enum Validation {
    static func username(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return "Choose a username" }
        if value.contains(" ") { return "Spaces aren't allowed in usernames" }
        if v.count < 3 { return "Use at least 3 characters" }
        if v.count > 30 { return "Use 30 characters or fewer" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        if v.lowercased().unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Use only letters, numbers, dots, dashes and underscores"
        }
        return nil
    }

    static func email(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return "Enter your email address" }
        let pattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return v.range(of: pattern, options: .regularExpression) == nil ? "Enter a valid email address" : nil
    }

    static func password(_ value: String, requireNumber: Bool = false) -> String? {
        if value.isEmpty { return "Enter a password" }
        if value.count < 8 { return requireNumber ? "Use at least 8 characters, including a number" : "Use at least 8 characters" }
        if requireNumber && value.rangeOfCharacter(from: .decimalDigits) == nil { return "Use at least 8 characters, including a number" }
        return nil
    }

    static func confirm(_ password: String, _ confirm: String) -> String? {
        if confirm.isEmpty { return "Confirm your password" }
        return password == confirm ? nil : "Passwords don't match"
    }

    static func required(_ value: String, _ message: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? message : nil
    }

    static func normalizedUsername(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
    }
}
