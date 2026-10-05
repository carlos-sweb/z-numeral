# z-numeral

[Documentation on GitHub Pages](https://carlos-sweb.github.io/z-numeral/)

Number formatting for **Zig 0.16.0**, with clear options, numbro patterns, and 61 locales. The module is named `numeral`. It requires no JavaScript, libc, or external runtime dependencies.

```zig
var buffer: [128]u8 = undefined;
const result = try numeral.formatBuf(&buffer, 1234567, .{
    .thousand_separated = true,
    .mantissa = 2,
});
try std.testing.expectEqualStrings("1,234,567.00", result);
```

## Documentation

[Documentation site](https://carlos-sweb.github.io/z-numeral/) · [Generated Zig API reference](https://carlos-sweb.github.io/z-numeral/api/)

## Installation

Run this command from your Zig project's directory:

```sh
zig fetch --save=z_numeral https://github.com/carlos-sweb/z-numeral/archive/75ae970a92c164c0dd0a9474a26da64308eb6723.tar.gz
```

## Usage

In `build.zig`, import the module into your executable:

```zig
const numeral_dependency = b.dependency("z_numeral", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("numeral", numeral_dependency.module("numeral"));
```

In your code, use `const numeral = @import("numeral");`. The complete standalone application is in [examples/consumer](examples/consumer); run it with `zig build run` from that directory. [examples/basic.zig](examples/basic.zig) contains the library demo; running `zig build run` from the library root prints:

```text
1,234,567.00
$1.234,50
97.488%
```

## Options and patterns

Options are partial: `null` inherits a value; `false`, `0`, and an empty string are explicit values. Use enums to select the output type, rounding mode, or currency position.

```zig
var buffer: [128]u8 = undefined;
const options = numeral.pattern("0,0.00");
const result = try numeral.formatBuf(&buffer, 1234.5, options);
try std.testing.expectEqualStrings("1,234.50", result);

const dynamic = try numeral.parsePattern("0.000%");
try std.testing.expectEqualStrings("43.000%", try numeral.formatBuf(&buffer, 0.43, dynamic));
```

`pattern` validates a literal at compile time. `parsePattern` validates text at runtime and borrows its slices for the result: keep the text alive while using the options. The historical syntax follows numbro 2.5.0, including its optional decimal rules; use options for explicit control.

| Purpose | Main options | Pattern |
|---|---|---|
| Group thousands | `thousand_separated` | `0,0` |
| Two decimal places | `mantissa = 2` | `0.00` |
| Omit a zero fractional part | `optional_mantissa = true` | `0[.]00` |
| Remove trailing zeros | `trim_mantissa = true` | `0.00[00]` |
| Show a positive sign | `force_sign = true` | `+0` |
| Parenthesize negative values | `negative = .parenthesis` | `(0)` |
| Currency | `output = .currency` | `$0,0.00` |
| Percentage of a ratio | `output = .percent` | `0.00%` |
| Abbreviate magnitude | `average = true` | `0.0a` |
| Force a scale | `force_average = .million` | `0M` |
| Binary bytes | `output = .byte, base = .binary` | `0.0b` |
| Decimal bytes | `output = .byte, base = .decimal` | `0.0d` |
| Base 1024 with KB/MB labels | `output = .byte, base = .general` | `0.0bd` |
| Ordinal | `output = .ordinal` | `0o` |
| Duration in seconds | `output = .time` | `00:00:00` |
| Exponential notation | `exponential = true` | Use options |

## Exact precision

Integers retain their precision up to 128 bits. For decimal amounts, pass a `Decimal` or construct one from text: a floating-point literal such as `0.1` already has binary semantics before it reaches the library.

```zig
var buffer: [128]u8 = undefined;
const amount = try numeral.Decimal.parse("1234.50");
const result = try numeral.formatBuf(&buffer, amount, .{
    .output = .currency,
    .thousand_separated = true,
    .mantissa = 2,
    .locale = try numeral.locales.get("es-CL"),
});
try std.testing.expectEqualStrings("$1.234,50", result);
```

`Decimal` stores a sign, a `u128` coefficient, and a scale of 0–38. It normalizes trailing zeros. The coefficient must fit in `u128`; support for 38 decimal places does not mean that every combination of integer and fractional parts fits. Operations return `Overflow` or `PrecisionOutOfRange` when the result exceeds these limits.

The default exact rounding mode is `.half_even`. Available alternatives are `.half_away`, `.trunc`, `.floor`, `.ceil`, and `.js` (ties toward positive infinity). The formatter accepts `mantissa` from 0 to 38; omitting it or using `-1` preserves the available decimal places. It does not perform decimal arithmetic through `f64`.

Floating-point values are converted through their shortest decimal representation that round-trips to the original value. This allows formatting them but does not recover the original decimal intent. Exact mode rejects `NaN` and infinities.

## Compatibility with numbro

```zig
var buffer: [128]u8 = undefined;
const result = try numeral.compat.formatBuf(&buffer, 0.974878234, numeral.pattern("0.000%"));
try std.testing.expectEqualStrings("97.488%", result);

var number = numeral.compat.Number.init(0.1);
number.add(0.2);
try std.testing.expectEqual(@as(f64, 0.3), number.value());
```

`numeral.compat` reproduces the rules of **numbro 2.5.0**, using `f64` and its decimal arithmetic rules. This includes unusual results, such as certain signs when rounding to zero, Turkish ordinal formats, and seconds displayed as `60` in rounded durations. Tests compare the implementation against results generated by the pinned version; see the [coverage matrix](docs/COVERAGE.md).

Compatibility covers this library's typed API, with its precision limits and Zig errors for invalid inputs. It does not include JavaScript object coercion, dynamic module loading, or global state. The compatible parser accepts localized numeric text; the exact parser requires valid grouping and consumes the entire input.

## Memory and output

- `formatBuf(buffer, value, options)` returns a slice of the buffer. It allocates no memory and may write partially before returning `BufferTooSmall`.
- `formatAlloc(allocator, value, options)` returns an owned slice: free it with the same allocator.
- `formatTo(writer, value, options)` writes to `*std.Io.Writer`; it propagates `WriteFailed` and may emit a prefix before failing.
- Slices in options, patterns, and custom locales are borrowed. Built-in locales have static lifetimes.

```zig
const allocator = std.testing.allocator;
const result = try numeral.formatAlloc(allocator, 1234.5, numeral.pattern("0,0.00"));
defer allocator.free(result);
try std.testing.expectEqualStrings("1,234.50", result);
```

## Parsing, reuse, and arithmetic

```zig
const value = try numeral.unformat("1.234,50", .{ .locale = try numeral.locales.get("es-CL") });
try std.testing.expectEqual(try numeral.Decimal.parse("1234.5"), value.decimal);

var buffer: [128]u8 = undefined;
const formatter = try numeral.Formatter.init(.{ .locale = try numeral.locales.get("fr-FR") });
const result = try formatter.formatBuf(&buffer, 1234.5, try formatter.named("fullWithTwoDecimalsNoCurrency"));
try std.testing.expectEqualStrings("1 234,50", result);
```

`unformat` returns a `Value`: `.unsigned`, `.signed`, or `.decimal`. The formatter also accepts `Value` and `Number`. A negative integer whose magnitude exceeds the `i128` range is represented as a decimal with scale zero.

Formats that round or abbreviate lose information: parsing their text recovers the displayed value. For infix currency or `.general` bytes, also pass the original options in `ParseOptions.format`.

```zig
var number = try numeral.Number.init(try numeral.Decimal.parse("0.1"));
try number.add(try numeral.Decimal.parse("0.2"));
try std.testing.expectEqual(try numeral.Decimal.parse("0.3"), number.value().decimal);
try number.divide(try numeral.Decimal.parse("3"), 6, .half_even);
try std.testing.expectEqual(try numeral.Decimal.parse("0.1"), number.value().decimal);
```

Exact operations check for overflow and preserve the previous value on failure. Mixing floating-point values with integers or decimals returns `MixedNumericTypes`; use `toFloat()` to convert explicitly. Operations between integers of the same signedness preserve that range; positive integer literals create unsigned values.

## Development

```sh
zig build test
zig build test -Doptimize=ReleaseSafe
zig build examples
zig build docs
zig build run
zig fmt --check build.zig src examples
python3 tools/check-docs.py
```

The documentation workflow regenerates the Zig API reference and publishes it with the entry page to GitHub Pages on every push to `main`. To preview the API locally, run `zig build docs` and serve `zig-out/docs` over HTTP.

Fixtures are included: normal tests download nothing. To regenerate them:

```sh
npm ci --prefix tools --ignore-scripts --no-audit --no-fund
node tools/generate.mjs
```

The lockfile pins numbro 2.5.0 and bignumber.js 9.3.1 with integrity hashes. The generator uses a fixed seed for random cases and applies `zig fmt` to the locale catalog. The [plan](PLAN.md), [API reference](docs/API.md), and [coverage matrix](docs/COVERAGE.md) explain decisions, limits, and tests. Derived code and data retain the MIT notices for [numbro](LICENSE) and [Numeral.js](LICENSE-Numeraljs).
