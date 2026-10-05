# Coverage and verification matrix

Pinned reference: **numbro 2.5.0 + bignumber.js 9.3.1**, with integrity hashes in `tools/package-lock.json`. Target Zig version: **0.16.0**. Results are stored in `src/fixtures.json`; the library does not execute JavaScript.

## Capabilities

| Planned capability | Implementation | Evidence |
|---|---|---|
| Typed formatting and defaults | `Options`, `Formatter`, two explicit engines | Corpus with options, named formats, and false/0 overrides |
| Historical patterns | Runtime parser and compile-time validation | Documented examples and K/M/B/T modifiers, prefixes, and suffixes |
| Numbers and grouping | Locale separators and explicit precision | Byte-for-byte formatting in every locale |
| Currency, signs, parentheses, and infix symbols | Configurable position and symbol | Corpus and targeted exact tests |
| Percentages | ×100 scaling; prefix/postfix symbol | Corpus, parsing, and ratio tests |
| Abbreviation and exponential notation | Units, total precision, forced scale | Thresholds, extreme values, and random samples |
| Bytes | Binary/general base 1024 and base 1000 | Corpus through YiB/YB, parsing, and unit helpers |
| Ordinals | Six rule families and callbacks | 1,220 direct cases, plus ordinal formats |
| Durations | Seconds → hours:minutes:seconds | Corpus and tests for signs, rounding, and >24 h |
| Parsing | Strict exact parser and compatible parser | 2,924 results compared without numeric tolerance |
| Arithmetic | `Decimal`, `Number`, `compat.Number` | 261 reference operations; exact precision and failures |
| 128-bit integers and fixed decimal | Wide intermediates, checked limits | i128/u128 extremes, >2^53, scales 0/38, representable quotients |
| Explicit memory management | Buffer, allocator, and writer | Exact/short buffers, failure propagation, and failure at every allocation |
| Complete catalog | 61 unique tags from the reference package | Fixtures for locales, rules, and named formats |
| Custom locales and fallback | Borrowed `Locale`, exact lookup, explicit fallback | UTF-8 separators, custom grouping, callbacks, and unknown tags |
| Package and documentation | `numeral` module, manifest, and English guides | Independent local consumer and seven README examples |

## Reproducible corpus

The generator includes documented patterns, typed configurations, named formats, negative and fractional values, abbreviation thresholds, rounding cases, very small and large amounts, and finite `f64` extremes.

It adds 512 pseudorandom values using an LCG seeded with `0x5a17c0de`. Each sample is compared in nine configurations: eight patterns and exponential notation. Differences are not removed from fixtures to make tests pass.

Formatting comparisons require exact byte equality. Parsing and arithmetic compare `f64` equality without a tolerance that could hide differences. NaN, infinities, write failures, and invalid configuration are checked in targeted tests.

The corpus covers the declared API surface; it does not prove equivalence for every possible combination of values, callbacks, and options. Explicit API limits, including formatting precision of 0–38, are documented in `API.md`.

## Local validation and CI

Acceptance commands:

```sh
zig build test
zig build test -Doptimize=ReleaseSafe
zig build examples
zig build examples -Doptimize=ReleaseSafe
zig build check -Dtarget=x86_64-windows-gnu
zig build check -Dtarget=aarch64-macos
zig build docs
zig fmt --check build.zig build.zig.zon src examples
python3 tools/check-docs.py
```

Local development uses Linux x86_64. The Windows and macOS `check` steps compile tests and examples but do not execute those systems' binaries. `.github/workflows/ci.yml` configures native execution on all three systems in Debug and ReleaseSafe; no remote workflow has been run from this directory.

A limitation in Zig 0.16.0's LLVM backend for direct `u4096` to `f64` conversion on aarch64 was verified and addressed: bounded values are narrowed to u16/u128 before conversion, and general values use a decimal representation. The core retains wide precision without introducing a platform dependency.

## Public documentation

The 89 public functions in the source modules have `///` comments, including support functions. `docs/API.md` describes parameters, ownership, limits, and errors; `README.md` contains seven executable snippets. `zig build docs` generates browsable reference documentation in `zig-out/docs`.

The example checker also builds a consumer application using the exact installation snippets from the README. Temporary files are stored in `.cache/docs`, excluded from version control.

## Intentional differences

- Typed errors for invalid input, without JavaScript error strings.
- Explicit, borrowed configuration, without global state or JavaScript object coercion.
- Exact mode uses ties-to-even rounding, strict grouping, and checked operations.
- Exact mode places parentheses around the number and its complete unit/symbol; compatible mode preserves numbro's historical placement.
- Exact division and conversions are limited by a u128 coefficient and scale 38; arbitrary-length decimals are not supported.
- Patterns retain their historical rules; options provide the most explicit way to specify precision.
- Exact byte output is calculated with up to 38 decimal places; nonterminating quotients are rounded before display.
