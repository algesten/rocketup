# Expression dependency inspection

Inspected 2026-11-16 for RocketUp's local calculator. Accepted for this integration with the bounds and limitations below.

## Exact dependency and provenance

- Canonical repository: <https://github.com/nicklockwood/Expression>, created September 2016, owned by `nicklockwood`.
- Release: [0.13.9](https://github.com/nicklockwood/Expression/releases/tag/0.13.9), July 14, 2024.
- Commit: [`95ffe4c352e456cede933d9910d25b9c84039d1b`](https://github.com/nicklockwood/Expression/tree/95ffe4c352e456cede933d9910d25b9c84039d1b).
- Only `Sources/Expression.swift` (1,478 lines) and `LICENSE.md` are copied, byte-for-byte. No upstream binaries, framework, examples, workflows, or package manifest are executed or shipped. `AnyExpression.swift`, which supports arbitrary values and objects, is excluded.
- [Expression.lock.json](Expression.lock.json) records the exact revision and SHA-256 hashes. `Tests/DependencyChecks.py`, run by the calculator checks and Xcode Cloud, fails if the source or bundled license changes. Vendoring means builds cannot silently select a newer release, resolve transitive packages, or fetch changed tag contents.
- Retrieved the tag directly from the canonical GitHub repository, compared the downloaded source to the Git checkout, inspected the full history through the release, and cross-checked the release's commit on GitHub. Nick Lockwood authored 181 of the 193 commits through this release. The history contains incremental parser, portability, and testing changes rather than a recent code replacement.
- The tag is lightweight and the commit is unsigned. Repository identity, history, and matching hashes support provenance; they do not cryptographically authenticate the author or establish absence of malicious code.

The GitHub API reported no published security advisories at inspection time. Open and closed issue titles were checked for security, crashes, hangs, and overflow; historical Swift 5.6/5.7 crash fixes predate this release. There are four commits after 0.13.9 on `main`; the only numeric-source change replaces the cache's dispatch queue with `NSLock`. RocketUp bypasses this cache. No subsequent parser/security fix was found in that comparison. These checks are observations, not a guarantee against undisclosed defects.

## Source and execution review

Read the complete numeric evaluator, including public initializers, symbol lookup, arity validation, optimizer, cache, numeric/Unicode scanners, recursive parser, stack reduction, and evaluation/error handling. Also inspected the package manifest, upstream test structure, CI workflow, license, changelog, relevant historical fixes, and changes after the release.

- The manifest declares no external dependencies, binary targets, plugins, or build scripts. RocketUp does not use the manifest at build time.
- Numeric source imports only Foundation and Dispatch. No network, filesystem, process, shell, dynamic-library loading, Objective-C selector dispatch, reflection-based evaluation, or unsafe-memory API was found.
- Input becomes an expression tree. Evaluation invokes Swift closures from the built-in math dictionary or RocketUp's small numeric additions; unknown symbols throw. User input cannot register closures or access Swift/Objective-C objects. There is no `eval` or interpreted language runtime.
- Built-in operations are arithmetic and bounded-argument platform math functions. No user-defined loops, recursion, assignments, or I/O are enabled. Boolean symbols are disabled. Array literals and subscripts have no supplied implementation.
- Parser loops consume input or terminate. Parser, tree optimization, description, and evaluation recurse, so arbitrarily large input can consume excessive CPU or stack. RocketUp rejects input above 512 UTF-8 bytes or 32 nested parentheses before parsing. Bounded malformed-input tests exercise the remaining parser surface.
- The library's static parse cache is unlimited. RocketUp uses `parse(..., usingCache: false)` to avoid retaining every incremental query.
- There is a forced error cast in the parser catch block; all throwing scanner/parser paths inspected throw the library's own error type. There are force-unwrapped scanner/description values and indexed parser/argument arrays whose validity depends on internal invariants. No failing invariant was found, but this is not a formal proof of memory or crash safety.
- The built-in functions index their arguments after symbol/arity resolution. Wrong arities are covered by upstream and RocketUp tests. Results are IEEE-754 `Double`, so domain errors and division by zero can produce NaN/infinity rather than throw. RocketUp rejects non-finite final results and formats finite results with 15 significant digits and the current macOS locale’s decimal separator (also used for the clipboard). This is a scientific floating-point calculator, without symbolic algebra or arbitrary precision.

## Mathematical limitations and decisions

Parentheses, normal arithmetic precedence, scientific literals, trig/inverse trig, roots, logs, rounding, min/max, modulo, and `pow` are supported. Trig arguments are radians; `log` and `ln` mean natural log. Multiplication must be explicit. `%` is a remainder operator.

The upstream library has precedence metadata for a custom `^` operator but does not implement that operator by default. Inspection found its precedence table marks it left-associative and prefix negation binds first; simply adding a `pow` closure would therefore give surprising answers for chained powers and negative bases. RocketUp deliberately leaves `^` undefined and supports powers through `pow(base, exponent)`, preserving the audited source without patches. Supporting conventional exponent notation later requires a separately tested parser change or a different evaluator.

## License and distribution

Read [the exact upstream MIT license](https://github.com/nicklockwood/Expression/blob/95ffe4c352e456cede933d9910d25b9c84039d1b/LICENSE.md) and the matching full notice in the Swift source header. It explicitly permits use, copying, modification, distribution, sublicensing, and sale. It requires retaining the copyright and permission notice in copies or substantial portions, and contains a warranty/liability disclaimer. It imposes no source disclosure, copyleft, noncommercial, or separate payment requirement.

Bundling this code in RocketUp is permitted under those terms. Keep the source header intact and distribute the complete license as `Expression-LICENSE.txt` in `RocketUp.app/Contents/Resources`. The synchronized Xcode sources group copies it as a resource, and the Swift package also declares the resources directory. Verify that the built/installed app contains the identical license before distributing. No upstream artwork, branding assets, or example code is bundled.

## Validation and update process

The unmodified upstream suite passed **633 tests with zero failures** on the installed Xcode toolchain. RocketUp's checks cover the requested division example, precedence, nested functions, constants, scientific notation, decimal-point/comma locale formatting, invalid syntax and arities, non-finite results, input boundaries, cache avoidance, and 5,000 deterministic malformed inputs. The sandboxed integration test exercises the visible result, keyboard navigation, Return/click copying, dismissal, invalid-input clipboard preservation, Escape, and returning to app search.

To update: inspect the canonical repository and diff against this revision; review the complete changed source and license; rerun upstream and RocketUp checks; copy the approved files; update the lock revision and hashes; record the new inspection; build the signed app and verify its bundled license. Do not change checksums merely to bypass a failed integrity check.
