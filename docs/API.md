# API reference

Import `numeral` from a project that declares the module in its `build.zig`. Zig 0.16.0 is supported; other versions require independent validation.

## Formatting

| Function | Input and result | Ownership / errors |
|---|---|---|
| `formatBuf` | `[]u8`, number, `Options` → `Error![]u8` | Borrowed slice; `BufferTooSmall` |
| `formatAlloc` | `Allocator`, number, `Options` → `Error![]u8` | Owned result; `OutOfMemory` |
| `formatTo` | `*std.Io.Writer`, number, `Options` → `(Error \| Writer.Error)!void` | Partial output on failure |
| `parsePattern` | `[]const u8` → `Error!Options` | No allocation; borrows parts of the pattern |
| `pattern` | Compile-time literal → `Options` | Compile error for an invalid pattern |
| `byteUnits` | Number, `Base`, `?*const Locale` → `Error![]const u8` | Static slice or slice borrowed from the locale |

“Number” means an integer up to 128 bits, `f32`, `f64`, `Decimal`, `Value`, or `Number`. The `compat.format*` variants accept `f64`. Exact mode preserves all integer bits when formatting.

`Formatter.init(options)` validates borrowed configuration. Its `formatBuf`, `formatAlloc`, and `formatTo` methods merge stored options with call options: non-null fields from the call take precedence. `named(name)` returns options for a named format in the active locale. `compat.Formatter` provides the same interface for `f64`.

## Options

All fields are optional. Resolution order: base defaults, `Locale.defaults`, configuration, and call options. When only a specialized output is requested, its locale defaults also apply. Patterns produce the same options as a direct call.

| Group | Fields |
|---|---|
| Output type | `output`: `.number`, `.currency`, `.percent`, `.byte`, `.time`, `.ordinal` |
| Precision | `mantissa`: -1 or 0–38; `characteristic`: 0–400; `total_length`: 0–38 |
| Optional decimals | `optional_mantissa`, `trim_mantissa`, `optional_characteristic` |
| Separators | `thousand_separated`, `space_separated`, `space_separated_currency`, `space_separated_abbreviation` |
| Sign | `negative`: `.sign` / `.parenthesis`; `force_sign` |
| Currency | `currency_position`: `.prefix` / `.infix` / `.postfix`; `currency_symbol` |
| Scale | `average`, `force_average`: `.thousand` / `.million` / `.billion` / `.trillion`; `low_precision`, `abbreviations` |
| Bytes | `base`: `.binary` / `.decimal` / `.general` |
| Other | `exponential`, `prefix_symbol` (percentages), `prefix`, `postfix`, `zero_format`, `locale` |
| Rounding | `rounding`: `.half_even`, `.half_away`, `.trunc`, `.floor`, `.ceil`, `.js`; `rounding_function` for compatible mode only |

A positive `total_length` enables abbreviation and adjusts precision; it is incompatible with `exponential`. `average` without `mantissa` requests zero decimal places. `low_precision` allows rounding to select a unit early; it defaults to true for numbers and false for currency.

`optional_mantissa` omits a fractional part consisting entirely of zeros; `trim_mantissa` removes trailing zeros. The historical pattern `0.0[0000]` uses the first sequence of zeros after the decimal point, just as numbro does, so it does not mean a range of 1 to 5 decimal places. Use options to express the desired maximum.

`space_separated_abbreviation` participates in the historical compatible currency rule; use `space_separated` for spacing between a number and its abbreviation. `abbreviations` customizes units in exact mode; compatible mode uses the locale's units, as numbro 2.5.0 does.

`rounding_function` receives the scaled `f64` value; when provided, it takes precedence over `rounding`. The exact engine does not support it. Text returned by custom callbacks is borrowed and must be valid UTF-8.

## Locales

`locales.all` lists the 61 unique tags from numbro 2.5.0. `locales.get(tag)` requires an exact, case-sensitive match; `getOr(tag, fallback)` uses only the requested fallback. They return `UnknownLocale` when no locale is found.

`Locale` configures UTF-8 separators, group size, abbreviations, currency, byte units, default formats, and named formats. There is no global registry: keep an instance and pass it through `Options.locale` or `ParseOptions.locale`.

`ordinal_fn: fn(f64) []const u8` customizes ordinals in both modes. To preserve a full decimal in exact mode, use `ordinal_exact_fn: fn(Decimal) []const u8`; this callback takes precedence in the exact engine. Built-in ordinals evaluate rules using exact data, even for large integers. `Locale.named(name)` returns `UnknownFormat` if the name is missing.

## Parsing

`unformat(text, ParseOptions)` returns a `Value`. `ParseOptions` contains `locale`, `format`, and `zero_format`. Defaults are en-US, empty format options, and no zero substitution. `format.locale` applies when `ParseOptions.locale` is not specified.

Exact mode validates the entire input and each group size, and returns only numbers representable as 128-bit integers or `Decimal`. It parses numbers, currency, percentages, abbreviations, bytes, ordinals, and durations. Durations require minutes and seconds from 0 to 59; a leading sign applies to the entire duration. `compat.unformat` reproduces numbro's parsing rules and returns `f64`.

`validate(text, options)` reports whether parsing succeeds; output formatting may lose information. `compat.validate` checks the compatible parser. These functions allocate no memory.

For infix currency, pass `currency_position = .infix` and the original symbol in `format`. To interpret `KB`/`MB` with base 1024 in exact mode, pass `.output = .byte, .base = .general`; otherwise they are parsed as decimal units. The compatible parser preserves numbro's interpretation.

The maximum input length is 1500 bytes; text exponents are limited to ±400 to bound processing work. Borrowed configuration metadata is validated as UTF-8. The compatible parser may accept forms the strict parser rejects, such as incorrect grouping or hexadecimal integers.

## Decimal, Value, and Number

`Decimal.init(negative, magnitude, scale)` and `Decimal.parse(text)` check the `u128` coefficient and scale of 0–38. Decimals are normalized: trailing zeros and the sign of zero are removed. `add`, `subtract`, `multiply`, and `divide(other, scale, rounding)` return a new decimal or an error. Wide intermediates prevent rejecting representable quotients merely because temporary scaling exceeds `u128`.

`Value` distinguishes `.signed: i128`, `.unsigned: u128`, `.decimal: Decimal`, and `.float: f64`. `Value.init` accepts native numbers and decimals; positive literals use `.unsigned`. `toFloat` converts explicitly and may lose precision.

`Number.init`, `set`, `value`, `clone`, `add`, `subtract`, `multiply`, `divide`, `difference`, and `toFloat` provide operations on `Value`. `clone` copies the value without allocating. `difference` returns the absolute difference. `divide` requires scale and rounding for exact numbers. Failed operations leave the state unchanged.

Operations between two signed or two unsigned integers preserve that range and return `Overflow` if exceeded. A fractional division result uses decimal. Operations involving decimals preserve decimal. Combining both integer types allows a signed, unsigned, or decimal result according to sign and magnitude. Mixing floating-point values with exact types returns `MixedNumericTypes`.

`compat.Number` operates on `f64`, using the decimal rules of numbro/bignumber.js and scale 20 for division. Its mutating methods do not return errors: they may produce infinities or NaN, as numbro does. Both types provide `binaryByteUnits`, `decimalByteUnits`, and `byteUnits` for unit names.

## Errors

| Error | Meaning |
|---|---|
| `InvalidPattern` | Invalid or incomplete historical syntax |
| `InvalidOptions` | Inconsistent configuration or incompatible callback |
| `UnknownLocale`, `UnknownFormat` | Missing locale tag or named format |
| `InvalidNumber` | Empty, incomplete, or partially nonnumeric text |
| `InvalidUtf8` | Incorrectly encoded text or configuration |
| `InvalidGrouping` | Incorrect digit groups in exact parsing |
| `PrecisionOutOfRange` | Scale or precision exceeds the limit |
| `Overflow` | Coefficient, range, or intermediate exceeds capacity |
| `DivisionByZero` | Exact division by zero |
| `NonFinite` | NaN or infinity in exact mode |
| `MixedNumericTypes` | Implicit mixing of floating-point values with exact types |
| `BufferTooSmall` | Insufficient output buffer |
| `OutOfMemory` | Allocator cannot complete the output |
| `WriteFailed` | Failure propagated by `formatTo` |

Preservation of the buffer or writer is not guaranteed on write failure. The caller retains ownership of buffers and options.
