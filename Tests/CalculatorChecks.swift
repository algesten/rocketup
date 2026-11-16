import Foundation

let examples: [(String, String)] = [
    ("100 / 42", "2.38095238095238"),
    ("2 + 3 * 4", "14"),
    ("(2 + 3) * (4 - 1)", "15"),
    ("sin(pi / 2)", "1"),
    ("cos(0) + sqrt(81)", "10"),
    ("tan(0) + asin(0) + acos(1) + atan(0)", "0"),
    ("pow(2, pow(3, 2))", "512"),
    ("pow(-2, 3) + pow(2, -2)", "-7.75"),
    ("ln(e) + log(e) + log10(100) + log2(8) + exp(0)", "8"),
    ("max(1, 2, min(4, 5))", "4"),
    ("abs(-4) + floor(1.9) + ceil(1.1) + round(1.5)", "9"),
    ("mod(10, 3) + 10 % 3", "2"),
    ("  SQRT(16) × 2 − 4 ÷ 2  ", "6"),
    ("sin(π / 2) + cos(tau)", "2"),
    ("1.5e3 / .5", "3000"),
    ("0.1 + 0.2", "0.3"),
    ("-0", "0"),
    ("+42", "42"),
    ("-3 * (-2 + 4)", "-6"),
    ("1e100 * 1e100", "1e+200"),
    ("1e-200", "1e-200"),
]
for (query, expected) in examples {
    let actual = Calculator.result(query, locale: Locale(identifier: "en_US_POSIX"))
    precondition(actual == expected, "\(query): \(actual ?? "nil") != \(expected)")
    precondition(!NumericExpression.isCached(query), "Live queries must not fill the parser cache")
}
for identifier in ["en_US", "en_GB", "de_DE", "es_ES", "fr_FR"] {
    let locale = Locale(identifier: identifier)
    let separator = locale.decimalSeparator!
    precondition(Calculator.result("100 / 42", locale: locale) == "2\(separator)38095238095238", "Decimal separator did not follow \(identifier)")
    precondition(Calculator.result("1.25e100", locale: locale) == "1\(separator)25e+100")
    precondition(Calculator.result("10000", locale: locale) == "10000", "Numbers should not have grouping separators")
}
precondition(Calculator.result("100 / 42") == "2\(Locale.current.decimalSeparator!)38095238095238", "Default formatting did not follow the user locale")
let rejected = ["", " ", "Safari", "1Password", "sin", "100 /", "sqrt(", "(1 + 2", "1 + 2)",
                "1 2", "2(3)", "2pi", "1 + 2 junk", "sqrt()", "sqrt(1, 2)", "pow(2)", "max(1)",
                "unknown(1)", "1 / 0", "0 / 0", "sqrt(-1)", "log(0)", "acos(2)", "exp(1000)",
                "1e309", "[1, 2][0]", "foo[0]", "system(1)", "1; 2", "2 ^ 3"]
for query in rejected {
    precondition(Calculator.result(query) == nil, "Unexpected result for \(query)")
}
let nested = String(repeating: "(", count: 32) + "1" + String(repeating: ")", count: 32)
precondition(Calculator.result(nested) == "1")
precondition(Calculator.result("(" + nested + ")") == nil)
precondition(Calculator.result(String(repeating: "1+", count: 255) + "1") == "256")
precondition(Calculator.result(String(repeating: "1+", count: 256) + "1") == nil)
precondition(Calculator.result(String(repeating: "-", count: 512)) == nil)

// Reproducible malformed-input smoke test for the vendored parser's error paths.
var seed: UInt64 = 42
let alphabet = Array("0123456789+-*/%()[],.e^ abcdefsin√π'\"\\\n")
for _ in 0..<5_000 {
    seed = seed &* 6364136223846793005 &+ 1
    let length = Int(seed % 64)
    var query = ""
    for _ in 0..<length {
        seed = seed &* 6364136223846793005 &+ 1
        query.append(alphabet[Int(seed % UInt64(alphabet.count))])
    }
    _ = Calculator.result(query)
}
print("Calculator arithmetic, scientific functions, locale formatting, invalid input, bounds, and 5,000 malformed inputs passed")
