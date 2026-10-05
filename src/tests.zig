const std = @import("std");
const n = @import("root.zig");
const Fixture = struct { zero_format: ?[]const u8 = null, locale: []const u8, value: f64, pattern: ?[]const u8 = null, options: std.json.Value = .null, named: ?[]const u8 = null, expected: []const u8 };
const Oracle = struct { operations: []struct { a: f64, b: f64, op: []const u8, expected: f64 }, reference: []const u8, fixtures: []Fixture, ordinals: []struct { locale: []const u8, value: f64, expected: []const u8 }, reads: []struct { locale: []const u8, text: []const u8, expected: f64 } };
fn fromJson(v: std.json.Value) !n.Options {
    var o = n.Options{};
    if (v == .null) return o;
    var it = v.object.iterator();
    while (it.next()) |e| {
        var buf: [100]u8 = undefined;
        var len: usize = 0;
        for (e.key_ptr.*) |c| {
            if (std.ascii.isUpper(c)) {
                buf[len] = '_';
                len += 1;
            }
            buf[len] = std.ascii.toLower(c);
            len += 1;
        }
        inline for (@typeInfo(n.Options).@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, buf[0..len])) {
                const Child = @typeInfo(field.type).optional.child;
                if (comptime @typeInfo(Child) == .bool) @field(o, field.name) = e.value_ptr.bool else if (comptime @typeInfo(Child) == .int) @field(o, field.name) = @intCast(e.value_ptr.integer) else if (comptime @typeInfo(Child) == .@"enum") @field(o, field.name) = std.meta.stringToEnum(Child, e.value_ptr.string).? else if (comptime Child == []const u8) @field(o, field.name) = e.value_ptr.string;
            }
        }
    }
    return o;
}
test "numbro 2.5.0 format oracle" {
    const parsed = try std.json.parseFromSlice(Oracle, std.testing.allocator, @embedFile("fixtures.json"), .{});
    defer parsed.deinit();
    var failures: usize = 0;
    var buf: [4000]u8 = undefined;
    for (parsed.value.fixtures) |f| {
        var o = if (f.pattern) |p| try n.parsePattern(p) else if (f.named) |name| try (try n.locales.get(f.locale)).named(name) else try fromJson(f.options);
        o.locale = try n.locales.get(f.locale);
        o.zero_format = f.zero_format;
        const actual = n.compat.formatBuf(&buf, f.value, o) catch |err| {
            if (failures < 12 or std.mem.eql(u8, f.locale, "en-US")) std.debug.print("{s} {d} {s}: {s}\n", .{ f.locale, f.value, f.pattern orelse "options", @errorName(err) });
            failures += 1;
            continue;
        };
        if (!std.mem.eql(u8, f.expected, actual)) {
            if (failures < 12 or std.mem.eql(u8, f.locale, "en-US")) std.debug.print("{s} {d} {s}: expected [{s}], actual [{s}]\n", .{ f.locale, f.value, f.pattern orelse f.named orelse "options", f.expected, actual });
            failures += 1;
        }
    }
    if (failures > 0) std.debug.print("{d}/{d} format mismatches\n", .{ failures, parsed.value.fixtures.len });
    try std.testing.expectEqual(@as(usize, 0), failures);
}
test "all locale ordinal rules" {
    const parsed = try std.json.parseFromSlice(Oracle, std.testing.allocator, @embedFile("fixtures.json"), .{});
    defer parsed.deinit();
    for (parsed.value.ordinals) |f| try std.testing.expectEqualStrings(f.expected, (try n.locales.get(f.locale)).ordinal(f.value));
}
test "numbro 2.5.0 unformat oracle" {
    const parsed = try std.json.parseFromSlice(Oracle, std.testing.allocator, @embedFile("fixtures.json"), .{});
    defer parsed.deinit();
    var failures: usize = 0;
    for (parsed.value.reads) |f| {
        const actual = n.compat.unformat(f.text, .{ .locale = try n.locales.get(f.locale) }) catch |err| {
            if (failures < 12 or std.mem.eql(u8, f.locale, "en-US")) std.debug.print("read {s} [{s}]: {s}\n", .{ f.locale, f.text, @errorName(err) });
            failures += 1;
            continue;
        };
        if (actual != f.expected) {
            if (failures < 12 or std.mem.eql(u8, f.locale, "en-US")) std.debug.print("read {s} [{s}]: expected {d}, actual {d}\n", .{ f.locale, f.text, f.expected, actual });
            failures += 1;
        }
    }
    if (failures > 0) std.debug.print("{d}/{d} read mismatches\n", .{ failures, parsed.value.reads.len });
    try std.testing.expectEqual(@as(usize, 0), failures);
}
test "exact u128 and decimal formatting" {
    var buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings("340282366920938463463374607431768211455", try n.formatBuf(&buf, std.math.maxInt(u128), .{}));
    try std.testing.expectEqualStrings("-170141183460469231731687303715884105728", try n.formatBuf(&buf, std.math.minInt(i128), .{}));
    try std.testing.expectEqualStrings("9,007,199,254,740,993", try n.formatBuf(&buf, @as(u64, 9007199254740993), n.pattern("0,0")));
    try std.testing.expectEqualStrings("1.234,50", try n.formatBuf(&buf, try n.Decimal.parse("1234.5"), .{ .mantissa = 2, .thousand_separated = true, .locale = try n.locales.get("es-CL") }));
}

test "numbro arithmetic oracle" {
    const parsed = try std.json.parseFromSlice(Oracle, std.testing.allocator, @embedFile("fixtures.json"), .{});
    defer parsed.deinit();
    var failures: usize = 0;
    for (parsed.value.operations) |f| {
        var num = n.compat.Number.init(f.a);
        const actual = if (std.mem.eql(u8, f.op, "difference")) num.difference(f.b) else blk: {
            if (std.mem.eql(u8, f.op, "add")) num.add(f.b) else if (std.mem.eql(u8, f.op, "subtract")) num.subtract(f.b) else if (std.mem.eql(u8, f.op, "multiply")) num.multiply(f.b) else num.divide(f.b);
            break :blk num.value();
        };
        if (actual != f.expected) {
            if (failures < 12) std.debug.print("operation {d} {s} {d}: expected {d}, actual {d}\n", .{ f.a, f.op, f.b, f.expected, actual });
            failures += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), failures);
}

test "exact rounding, precision, signs and currencies" {
    var buf: [800]u8 = undefined;
    const D = n.Decimal;
    try std.testing.expectEqualStrings("2", try n.formatBuf(&buf, try D.parse("2.5"), .{ .mantissa = 0 }));
    try std.testing.expectEqualStrings("3", try n.formatBuf(&buf, try D.parse("2.5"), .{ .mantissa = 0, .rounding = .half_away }));
    try std.testing.expectEqualStrings("-3", try n.formatBuf(&buf, try D.parse("-2.5"), .{ .mantissa = 0, .rounding = .floor }));
    try std.testing.expectEqualStrings("-2", try n.formatBuf(&buf, try D.parse("-2.5"), .{ .mantissa = 0, .rounding = .ceil }));
    try std.testing.expectEqualStrings("-2", try n.formatBuf(&buf, try D.parse("-2.5"), .{ .mantissa = 0, .rounding = .trunc }));
    try std.testing.expectEqualStrings("10.00", try n.formatBuf(&buf, try D.parse("9.995"), .{ .mantissa = 2 }));
    try std.testing.expectEqualStrings("0.00000000000000000000000000000000000001", try n.formatBuf(&buf, try D.init(false, 1, 38), .{}));
    try std.testing.expectEqualStrings("1.00000000000000000000000000000000000000", try n.formatBuf(&buf, 1, .{ .mantissa = 38 }));
    try std.testing.expectEqualStrings("0", try n.formatBuf(&buf, try D.init(true, 0, 38), .{}));
    try std.testing.expectEqualStrings("0", try n.formatBuf(&buf, -0.0, .{}));
    try std.testing.expectEqualStrings("0.00", try n.formatBuf(&buf, -0.001, .{ .mantissa = 2 }));
    try std.testing.expectEqualStrings("($1,234.50)", try n.formatBuf(&buf, try D.parse("-1234.5"), n.Options.merge(n.pattern("0,0.00"), .{ .output = .currency, .negative = .parenthesis })));
    try std.testing.expectEqualStrings("1 € 23", try n.formatBuf(&buf, try D.parse("1.23"), .{ .output = .currency, .currency_position = .infix, .currency_symbol = "€", .mantissa = 2, .space_separated_currency = true }));
    try std.testing.expectEqualStrings("N/A", try n.formatBuf(&buf, 0, .{ .zero_format = "N/A", .thousand_separated = true }));
    try std.testing.expectEqualStrings("1.23 million", try n.formatBuf(&buf, 1230000, .{ .average = true, .mantissa = 2, .space_separated = true, .abbreviations = .{ .million = "million" } }));
    try std.testing.expectEqualStrings("25:01:01", try n.formatBuf(&buf, 90061, .{ .output = .time }));
    try std.testing.expectEqualStrings("-0:00:01", try n.formatBuf(&buf, -1, .{ .output = .time }));
    try std.testing.expectEqualStrings("1.23e+6", try n.formatBuf(&buf, 1230000, .{ .exponential = true, .mantissa = 2 }));
    try std.testing.expectEqualStrings("1,0000000000000000000000000000000000001ème", try n.formatBuf(&buf, try D.parse("1.0000000000000000000000000000000000001"), .{ .output = .ordinal, .locale = try n.locales.get("fr-FR") }));
}

test "exact arithmetic, clones and failure atomicity" {
    var num = try n.Number.init(@as(i128, 5));
    try num.add(@as(i128, 2));
    try num.subtract(@as(i128, 1));
    try num.multiply(@as(i128, 3));
    try std.testing.expectEqual(@as(i128, 18), num.value().signed);
    var copy = num.clone();
    try copy.set(try n.Decimal.parse("0.1"));
    try copy.add(try n.Decimal.parse("0.2"));
    try std.testing.expectEqual(try n.Decimal.parse("0.3"), copy.value().decimal);
    try std.testing.expectEqual(@as(i128, 18), num.value().signed);
    try copy.divide(try n.Decimal.parse("3"), 38, .half_even);
    try std.testing.expectEqual(try n.Decimal.parse("0.1"), copy.value().decimal);
    try num.set(@as(i128, std.math.maxInt(i128)));
    try std.testing.expectError(error.Overflow, num.add(@as(i128, 1)));
    try std.testing.expectEqual(std.math.maxInt(i128), num.value().signed);
    try num.set(std.math.maxInt(u128));
    try std.testing.expectError(error.Overflow, num.multiply(@as(u128, 2)));
    try std.testing.expectEqual(std.math.maxInt(u128), num.value().unsigned);
    try num.set(@as(u128, 1));
    try std.testing.expectError(error.Overflow, num.subtract(@as(u128, 2)));
    try std.testing.expectEqual(@as(u128, 1), num.value().unsigned);
    try std.testing.expectEqual(@as(u128, 2), (try num.difference(@as(u128, 3))).unsigned);
    try std.testing.expectError(error.DivisionByZero, num.divide(@as(u128, 0), 2, .half_even));
    try std.testing.expectEqual(@as(u128, 1), num.value().unsigned);
    try std.testing.expectError(error.MixedNumericTypes, num.add(@as(f64, 0.5)));
    try num.divide(@as(u128, 3), 6, .half_even);
    try std.testing.expectEqual(try n.Decimal.parse("0.333333"), num.value().decimal);
    try num.set(@as(f64, 1.5));
    try num.add(@as(f64, 0.5));
    try num.subtract(@as(f64, 1));
    try num.multiply(@as(f64, 4));
    try num.divide(@as(f64, 2), 0, .half_even);
    try std.testing.expectEqual(@as(f64, 2), num.value().float);
    var buf: [100]u8 = undefined;
    try std.testing.expectEqualStrings("2", try n.formatBuf(&buf, num, .{}));
    const tiny = try n.Decimal.init(false, 1, 38);
    const tenth = try n.Decimal.parse("0.1");
    try std.testing.expectError(error.PrecisionOutOfRange, tiny.multiply(tenth));
    const max = try n.Decimal.init(false, std.math.maxInt(u128), 0);
    try std.testing.expectEqual(try n.Decimal.parse("1"), try max.divide(max, 38, .half_even));
    try std.testing.expectError(error.Overflow, max.add(try n.Decimal.parse("1")));
}

test "strict parsing, complete input and lossy formats" {
    const l = try n.locales.get("es-CL");
    var buf: [200]u8 = undefined;
    try std.testing.expectEqualStrings("1234.5", try n.formatBuf(&buf, try n.unformat("1.234,50", .{ .locale = l }), .{}));
    try std.testing.expectEqualStrings("-10000", try n.formatBuf(&buf, try n.unformat("($10,000.00)", .{}), .{}));
    try std.testing.expectEqualStrings("0.5", try n.formatBuf(&buf, try n.unformat("50%", .{}), .{}));
    try std.testing.expectEqualStrings("1230000", try n.formatBuf(&buf, try n.unformat("1.23m", .{}), .{}));
    try std.testing.expectEqualStrings("2048", try n.formatBuf(&buf, try n.unformat("2 KiB", .{}), .{}));
    try std.testing.expectEqualStrings("2000", try n.formatBuf(&buf, try n.unformat("2 KB", .{}), .{}));
    try std.testing.expectEqualStrings("2048", try n.formatBuf(&buf, try n.unformat("2 KB", .{ .format = .{ .output = .byte, .base = .general } }), .{}));
    try std.testing.expectEqualStrings("90061", try n.formatBuf(&buf, try n.unformat("25:01:01", .{}), .{}));
    try std.testing.expectEqualStrings("-1", try n.formatBuf(&buf, try n.unformat("-0:00:01", .{}), .{}));
    try std.testing.expectEqualStrings("23", try n.formatBuf(&buf, try n.unformat("23rd", .{}), .{}));
    try std.testing.expectEqualStrings("1.23", try n.formatBuf(&buf, try n.unformat("1 € 23", .{ .format = .{ .output = .currency, .currency_position = .infix, .currency_symbol = "€" } }), .{}));
    try std.testing.expectEqualStrings("0", try n.formatBuf(&buf, try n.unformat("N/A", .{ .zero_format = "N/A" }), .{}));
    try std.testing.expectEqualStrings("1234.5", try n.formatBuf(&buf, try n.unformat("USD 1,234.50 net", .{ .format = .{ .prefix = "USD ", .postfix = " net" } }), .{}));
    try std.testing.expectError(error.InvalidGrouping, n.unformat("12,34", .{}));
    try std.testing.expectError(error.InvalidGrouping, n.unformat("1,234,56", .{}));
    try std.testing.expectError(error.InvalidNumber, n.unformat("123garbage", .{}));
    try std.testing.expectError(error.InvalidNumber, n.unformat("1:99:00", .{}));
    try std.testing.expectError(error.InvalidNumber, n.unformat("", .{}));
    try std.testing.expectError(error.InvalidNumber, n.unformat("Infinity", .{}));
    try std.testing.expectError(error.Overflow, n.unformat("340282366920938463463374607431768211456", .{}));
    try std.testing.expectError(error.PrecisionOutOfRange, n.unformat("1e-39", .{}));
    const tiny_ordinal = "1,0000000000000000000000000000000000001ème";
    const tiny_read = try n.unformat(tiny_ordinal, .{ .locale = try n.locales.get("fr-FR") });
    try std.testing.expectEqual(try n.Decimal.parse("1.0000000000000000000000000000000000001"), tiny_read.decimal);
    try std.testing.expect(n.validate("1,234.5", .{}));
    try std.testing.expect(!n.validate("1,23", .{}));
    try std.testing.expectEqual(@as(f64, 16), try n.compat.unformat("0x10", .{}));
    try std.testing.expectEqual(@as(f64, 0), try n.compat.unformat("   ", .{}));
    try std.testing.expect(std.math.isInf(try n.compat.unformat("Infinity", .{})));
}

fn allocationExercise(allocator: std.mem.Allocator) !void {
    const a = try n.formatAlloc(allocator, std.math.maxInt(u128), .{ .thousand_separated = true, .prefix = "exact ", .postfix = "!" });
    defer allocator.free(a);
    const b = try n.compat.formatAlloc(allocator, -10000.23, n.pattern("($0,0.00)"));
    defer allocator.free(b);
    const f = try n.Formatter.init(.{ .locale = try n.locales.get("fr-FR") });
    const c = try f.formatAlloc(allocator, 1234, try f.named("fullWithTwoDecimals"));
    defer allocator.free(c);
}
test "buffers, streaming, ownership and allocator failures" {
    var buf: [20]u8 = undefined;
    try std.testing.expectEqualStrings("12.50", try n.formatBuf(buf[0..5], 12.5, .{ .mantissa = 2 }));
    try std.testing.expectError(error.BufferTooSmall, n.formatBuf(buf[0..4], 12.5, .{ .mantissa = 2 }));
    try std.testing.expectError(error.BufferTooSmall, n.compat.formatBuf(buf[0..4], 12.5, .{ .mantissa = 2 }));
    var writer = std.Io.Writer.fixed(buf[0..4]);
    try std.testing.expectError(error.WriteFailed, n.formatTo(&writer, 12.5, .{ .mantissa = 2 }));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}

test "configuration, UTF-8, patterns and unit helpers" {
    var buf: [300]u8 = undefined;
    try std.testing.expectError(error.UnknownLocale, n.locales.get("xx-XX"));
    try std.testing.expectEqualStrings("en-US", (try n.locales.getOr("xx-XX", "en-US")).tag);
    try std.testing.expectError(error.UnknownLocale, n.locales.getOr("xx-XX", "yy-YY"));
    try std.testing.expectError(error.UnknownFormat, (try n.locales.get("en-US")).named("missing"));
    for ([_][]const u8{ "", "0.[00", "(0", "0..00", "0:00", "bad format", "0}" }) |p| try std.testing.expectError(error.InvalidPattern, n.parsePattern(p));
    try std.testing.expectError(error.InvalidUtf8, n.parsePattern("0\xff"));
    try std.testing.expectError(error.InvalidUtf8, n.unformat("12\xff", .{}));
    try std.testing.expectError(error.InvalidUtf8, n.formatBuf(&buf, 1, .{ .prefix = "\xff" }));
    try std.testing.expectError(error.PrecisionOutOfRange, n.formatBuf(&buf, 1, .{ .mantissa = 39 }));
    try std.testing.expectError(error.PrecisionOutOfRange, n.Decimal.init(false, 1, 39));
    try std.testing.expectError(error.NonFinite, n.formatBuf(&buf, std.math.inf(f64), .{}));
    try std.testing.expectEqualStrings("NaN%", try n.compat.formatBuf(&buf, std.math.nan(f64), .{ .output = .percent }));
    try std.testing.expectEqualStrings("-$Infinity", try n.compat.formatBuf(&buf, -std.math.inf(f64), .{ .output = .currency, .mantissa = 2 }));
    try std.testing.expectEqualStrings("InfinityYiB", try n.compat.formatBuf(&buf, std.math.inf(f64), .{ .output = .byte, .base = .binary }));
    const custom = n.Locale{ .tag = "custom", .thousands = " ", .decimal = ",", .thousands_size = 2, .currency_symbol = "¤", .ordinal_rule = .constant, .ordinal_constant = "º" };
    try std.testing.expectEqualStrings("1 23 45,60", try n.formatBuf(&buf, 12345.6, .{ .locale = &custom, .thousand_separated = true, .mantissa = 2 }));
    const formatter = try n.Formatter.init(.{ .mantissa = 2, .thousand_separated = true });
    try std.testing.expectEqualStrings("1234", try formatter.formatBuf(&buf, 1234, .{ .mantissa = 0, .thousand_separated = false }));
    try std.testing.expectEqualStrings("KiB", try n.byteUnits(2048, .binary, null));
    try std.testing.expectEqualStrings("KB", try n.byteUnits(2048, .decimal, null));
    const num = try n.Number.init(2048);
    try std.testing.expectEqualStrings("KiB", try num.binaryByteUnits());
    try std.testing.expectEqualStrings("KB", try num.decimalByteUnits());
    try std.testing.expectEqualStrings("KB", try num.byteUnits());
    const legacy = n.compat.Number.init(2048);
    try std.testing.expectEqualStrings("KiB", try legacy.binaryByteUnits());
    try std.testing.expectEqualStrings("KB", try legacy.decimalByteUnits());
    try std.testing.expectEqualStrings("KB", try legacy.byteUnits());
}

test "compatible reusable configuration and custom ordinal callbacks" {
    var buf: [128]u8 = undefined;
    const f = try n.compat.Formatter.init(.{ .locale = try n.locales.get("fr-FR") });
    try std.testing.expectEqualStrings("1 234,50", try f.formatBuf(&buf, 1234.5, try f.named("fullWithTwoDecimalsNoCurrency")));
    const allocated = try f.formatAlloc(std.testing.allocator, 1234.5, try f.named("fullWithTwoDecimalsNoCurrency"));
    defer std.testing.allocator.free(allocated);
    try std.testing.expectEqualStrings("1 234,50", allocated);
    var w = std.Io.Writer.fixed(&buf);
    try f.formatTo(&w, 1234.5, try f.named("fullWithTwoDecimalsNoCurrency"));
    try std.testing.expectEqualStrings("1 234,50", w.buffered());
    const custom = n.Locale{ .tag = "custom", .ordinal_fn = ordinalCallback, .ordinal_exact_fn = exactOrdinalCallback };
    try std.testing.expectEqualStrings("2whole", try n.formatBuf(&buf, 2, .{ .output = .ordinal, .locale = &custom }));
    try std.testing.expectEqualStrings("2legacy", try n.compat.formatBuf(&buf, 2, .{ .output = .ordinal, .locale = &custom }));
    try std.testing.expect(n.compat.validate("12,34", .{}));
    try std.testing.expectEqualStrings("NaN", try n.compat.formatBuf(&buf, 1.25, .{ .mantissa = 2, .rounding_function = nanRounding }));
    try std.testing.expectError(error.InvalidOptions, n.formatBuf(&buf, 1.25, .{ .mantissa = 2, .rounding_function = nanRounding }));
    try std.testing.expectError(error.InvalidOptions, n.compat.formatBuf(&buf, 1, .{ .output = .byte }));
    try std.testing.expectError(error.InvalidOptions, n.formatBuf(&buf, 1, .{ .total_length = 3, .exponential = true }));
    const large = try n.Decimal.parse("999999999999.99999999999999999999");
    try std.testing.expectEqualStrings("1000.000b", try n.formatBuf(&buf, large, .{ .average = true, .low_precision = false, .mantissa = 3 }));
    try std.testing.expectEqualStrings("(1,23 €)", try n.formatBuf(&buf, -1.23, .{ .locale = try n.locales.get("fr-FR"), .output = .currency, .mantissa = 2, .space_separated_currency = true, .negative = .parenthesis }));
    try std.testing.expectEqualStrings("(43%)", try n.formatBuf(&buf, -0.43, .{ .output = .percent, .negative = .parenthesis }));
}
fn ordinalCallback(_: f64) []const u8 {
    return "legacy";
}
fn exactOrdinalCallback(d: n.Decimal) []const u8 {
    return if (d.scale == 0) "whole" else "fraction";
}

fn nanRounding(_: f64) f64 {
    return std.math.nan(f64);
}
