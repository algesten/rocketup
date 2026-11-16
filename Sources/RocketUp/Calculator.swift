import Foundation

enum Calculator {
    static func result(_ query: String, locale: Locale = .current) -> String? {
        // The parser and evaluator recurse. Bound pasted input before parsing it.
        guard query.utf8.count <= 512 else { return nil }
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "π", with: "pi")
        guard !input.isEmpty else { return nil }
        var depth = 0
        for character in input {
            if character == "(" { depth += 1; if depth > 32 { return nil } }
            if character == ")" { depth -= 1; if depth < 0 { return nil } }
        }
        guard depth == 0 else { return nil }
        // Search changes every keystroke; don't populate the library's unlimited cache.
        let parsed = NumericExpression.parse(input, usingCache: false)
        let expression = NumericExpression(parsed, constants: ["e": exp(1), "tau": 2 * .pi], symbols: [
            .prefix("+"): { $0[0] },
            .function("ln", arity: 1): { log($0[0]) },
            .function("log10", arity: 1): { log10($0[0]) },
            .function("log2", arity: 1): { log2($0[0]) },
            .function("exp", arity: 1): { exp($0[0]) },
        ])
        guard let value = try? expression.evaluate(), value.isFinite else { return nil }
        // Localized printf also adds grouping; keep numbers easy to copy by
        // localizing only the decimal separator after significant-digit formatting.
        let formatted = String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value).lowercased()
        return formatted.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
    }
}
