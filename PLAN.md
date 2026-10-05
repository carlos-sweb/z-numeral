# z-numeral plan: number formatting for Zig

## Summary and agreed decisions

Implement a library entirely in Zig 0.16.0, without external runtime dependencies, providing typed options and patterns, text parsing, numeric operations, and all locales from numbro 2.5.0.

- Exact mode by default: integers up to 128 bits and decimals with a u128 coefficient and scale 0–38, without silent conversions to f64.
- Explicit compatible mode: the same results as numbro 2.5.0 for valid f64 inputs.
- Typed Zig errors for invalid inputs.
- Distribution as the `numeral` source module, initial version 0.1.0; remote publication is outside the scope.

References: https://numbrojs.com/getting-started.html and source at https://github.com/BenjaminVanRyseghem/numbro/tree/2.5.0.

## API

`formatAlloc(allocator, value, options)`, `formatBuf(buffer, value, options)`, and `formatTo(writer, value, options)` share an engine. The caller frees allocated results; buffers and configuration are borrowed. `numeral.compat` provides the same functions for f64.

`Options` uses optional fields to distinguish omission from false or zero. `parsePattern` produces options without allocating; `pattern` validates literals at compile time. `Formatter` reuses options, locales, and named formats without mutable global state.

Implement numbers, currency, percentages, binary/decimal/general bytes, ordinals, and durations; grouping, precision, signs, parentheses, abbreviations, exponential notation, prefixes, suffixes, and custom zero output. Map numbro's complete option surface to snake_case names and Zig enums. Cover historical patterns, optional decimals, and forced-scale modifiers.

Include the pinned version's complete locale catalog, UTF-8 separators, ordinal rules, currency, and default formats. Provide tag lookup, enumeration, explicit fallback, and immutable custom configuration with callbacks.

`unformat(text, parse_options)` returns a tagged integer/decimal value in exact mode and f64 in compatible mode. Validate the entire input and grouping in exact mode. Support all format types.

`Number` provides add, subtract, multiply, divide, difference, set, value, and clone. Preserve types where possible; combining floating-point values with exact types requires explicit conversion. Exact division requests scale and rounding. Failures leave the value unchanged.

Rounding modes: ties to even (exact default), ties away from zero, truncation, floor, and ceiling. Compatible mode follows numbro. Reject nonfinite values in exact mode; compatible mode preserves their representations. Document floating-point and fixed-decimal limits.

## Implementation

1. Create the package, manifest, plan, public API, and examples.
2. Pin numbro 2.5.0 with lockfile integrity hashes; generate reproducible fixtures and a coverage matrix.
3. Implement the exact core with wide intermediates, checked arithmetic, and rounding.
4. Implement the shared output engine, formats, and patterns; separate compatible numeric rules.
5. Port the catalog, ordinal rules, and parser for all formats.
6. Document installation, memory ownership, errors, examples, differences, and licenses for derived material.

Node participates only in reference generation; installing and using the library requires only Zig.

## Tests and acceptance

- Compare formatting byte for byte against numbro 2.5.0; compare parsing and operations.
- Cover options, patterns, and interactions in every locale, including abbreviation/byte thresholds, ordinals, and durations >24 h.
- Test i128/u128 extremes, values >2^53, scales 0/38, carry, negatives, and division.
- Test formatting→parsing round trips; for lossy formats, compare the displayed value.
- Verify errors, UTF-8, grouping, limits, buffers, and allocators without leaks.
- Run `zig build test` in Debug/ReleaseSafe, `zig fmt --check`, examples, and Linux/macOS/Windows CI with Zig 0.16.0.

Accept delivery when the matrix has no pending capabilities and every compatibility fixture matches. The matrix records evidence and verified limits; it does not guarantee untested behavior.
