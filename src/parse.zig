const std = @import("std");
const t = @import("types.zig");
const dec = @import("decimal.zig");
const nums = @import("number.zig");
const locales = @import("locales.zig");
pub const ParseOptions = struct { locale: ?*const t.Locale = null, format: t.Options = .{}, zero_format: ?[]const u8 = null };
/// Read complete localized text with explicit parse options; return a tagged number or f64, with typed errors.
pub fn unformat(text: []const u8, options: ParseOptions) t.Error!nums.Value {
    return nums.fromD(try parse(text, options, false), false);
}
/// Read localized text with numbro-compatible f64 semantics; invalid input returns a typed error.
pub fn compatUnformat(text: []const u8, options: ParseOptions) t.Error!f64 {
    try options.format.validate();
    const l = options.locale orelse options.format.locale orelse try locales.get("en-US");
    try l.validate();
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    const stripped = trim(text);
    if (stripped.len == 0 and text.len > 0) return 0;
    if (std.mem.eql(u8, stripped, "Infinity") or std.mem.eql(u8, stripped, "+Infinity")) return std.math.inf(f64);
    if (std.mem.eql(u8, stripped, "-Infinity")) return -std.math.inf(f64);
    return (try parse(text, options, true)).toFloat();
}
fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}
fn parse(text: []const u8, options: ParseOptions, compatible: bool) t.Error!dec.D {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    try options.format.validate();
    const locale = options.locale orelse options.format.locale orelse try locales.get("en-US");
    try locale.validate();
    var s = trim(text);
    if (s.len == 0 or s.len > 1500) return error.InvalidNumber;
    if (options.zero_format orelse options.format.zero_format) |zero| if (std.mem.eql(u8, s, zero)) return .{};
    if (options.format.prefix) |prefix| {
        if (!std.mem.startsWith(u8, s, prefix)) return error.InvalidNumber;
        s = s[prefix.len..];
    }
    if (options.format.postfix) |postfix| {
        if (!std.mem.endsWith(u8, s, postfix)) return error.InvalidNumber;
        s = s[0 .. s.len - postfix.len];
    }
    s = trim(s);
    if (s.len == 0) return error.InvalidNumber;
    if (std.mem.indexOfScalar(u8, s, ':') != null) {
        var it = std.mem.splitScalar(u8, s, ':');
        var values: [3]dec.D = undefined;
        var count: usize = 0;
        while (it.next()) |part| {
            if (count == 3) return error.InvalidNumber;
            values[count] = try dec.parseD(trim(part));
            count += 1;
        }
        if (count != 3) return error.InvalidNumber;
        if (!compatible and ((try values[1].integer()) >= 60 or (try values[2].integer()) >= 60 or values[1].negative or values[2].negative)) return error.InvalidNumber;
        const hours = values[0];
        if (compatible) return compatD(values[2].toFloat() + 60 * values[1].toFloat() + 3600 * hours.toFloat());
        const negative = hours.negative or s[0] == '-';
        values[0].negative = false;
        var result = try dec.multiplyD(values[0], .{ .magnitude = 3600 });
        result = try dec.addD(result, try dec.multiplyD(values[1], .{ .magnitude = 60 }));
        result = try dec.addD(result, values[2]);
        if (negative) result.negative = true;
        return result;
    }
    var neg = false;
    if (s[0] == '(' and s[s.len - 1] == ')') {
        neg = true;
        s = trim(s[1 .. s.len - 1]);
    }
    // Currency can be outside numbro's negative parentheses.
    const symbol = options.format.currency_symbol orelse locale.currency_symbol;
    var cleaned: [1500]u8 = undefined;
    var len: usize = 0;
    var i: usize = 0;
    var removed = false;
    while (i < s.len) {
        if (!removed and symbol.len > 0 and std.mem.startsWith(u8, s[i..], symbol)) {
            if (!compatible and (options.format.currency_position orelse locale.currency_position) == .infix) {
                while (len > 0 and cleaned[len - 1] == ' ') len -= 1;
                if (len + locale.decimal.len > cleaned.len) return error.Overflow;
                @memcpy(cleaned[len..][0..locale.decimal.len], locale.decimal);
                len += locale.decimal.len;
                i += symbol.len;
                while (i < s.len and s[i] == ' ') i += 1;
            } else i += symbol.len;
            removed = true;
            continue;
        }
        cleaned[len] = s[i];
        len += 1;
        i += 1;
    }
    s = trim(cleaned[0..len]);
    if (s.len > 1 and s[0] == '(' and s[s.len - 1] == ')') {
        neg = !neg;
        s = trim(s[1 .. s.len - 1]);
    }
    var percent = false;
    if (std.mem.endsWith(u8, s, "%")) {
        percent = true;
        s = trim(s[0 .. s.len - 1]);
    } else if (std.mem.startsWith(u8, s, "%")) {
        percent = true;
        s = trim(s[1..]);
    }
    var multiplier: dec.Wide = 1;
    var suffix_found = false;
    const default_bytes = t.Locale{ .tag = "bytes" };
    const bs = if (compatible) &default_bytes else locale;
    var power: usize = 9;
    while (power > 0) {
        power -= 1;
        const candidates = [_]struct { suffix: []const u8, factor: dec.Wide }{ .{ .suffix = bs.binary_suffixes[power], .factor = std.math.pow(dec.Wide, 1024, power) }, .{ .suffix = bs.decimal_suffixes[power], .factor = std.math.pow(dec.Wide, 1000, power) } };
        for (candidates) |c| {
            if (s.len > c.suffix.len and std.mem.endsWith(u8, s, c.suffix)) {
                multiplier = if (!compatible and options.format.base == .general) std.math.pow(dec.Wide, 1024, power) else c.factor;
                s = trim(s[0 .. s.len - c.suffix.len]);
                suffix_found = true;
                break;
            }
        }
        if (suffix_found) break;
    }
    if (!suffix_found) {
        // Ordinals precede abbreviations, just as in numbro.
        var numeric: [1500]u8 = undefined;
        var nlen: usize = 0;
        var ni: usize = 0;
        while (ni < s.len) {
            if (std.ascii.isDigit(s[ni]) or s[ni] == '-' or s[ni] == '+') {
                numeric[nlen] = s[ni];
                nlen += 1;
                ni += 1;
            } else if (std.mem.startsWith(u8, s[ni..], locale.decimal)) {
                numeric[nlen] = '.';
                nlen += 1;
                ni += locale.decimal.len;
            } else if (locale.thousands.len > 0 and std.mem.startsWith(u8, s[ni..], locale.thousands)) {
                ni += locale.thousands.len;
            } else break;
        }
        if (nlen > 0) {
            const v = std.fmt.parseFloat(f64, numeric[0..nlen]) catch 0;
            const ordinal = if (compatible) locale.ordinal(v) else try @import("format.zig").ordinalExact(locale, try dec.parseD(numeric[0..nlen]));
            if (ordinal.len > 0 and !std.mem.eql(u8, ordinal, ".") and std.mem.endsWith(u8, s, ordinal)) {
                s = trim(s[0 .. s.len - ordinal.len]);
                suffix_found = true;
            }
        }
        if (!suffix_found) {
            var a: usize = 4;
            while (a > 0) {
                a -= 1;
                const abbreviation = locale.abbreviations.at(a);
                if (abbreviation.len > 0 and s.len > abbreviation.len and std.mem.endsWith(u8, s, abbreviation)) {
                    multiplier = try dec.pow10((a + 1) * 3);
                    s = trim(s[0 .. s.len - abbreviation.len]);
                    break;
                }
            }
        }
    }
    // Normalize locale delimiters, validating grouping before removing it.
    var buf: [1500]u8 = undefined;
    len = 0;
    i = 0;
    var point = false;
    var group_digits: usize = 0;
    var grouped = false;
    while (i < s.len) {
        if (locale.decimal.len > 0 and std.mem.startsWith(u8, s[i..], locale.decimal) and !point) {
            if (!compatible and grouped and group_digits != locale.thousands_size) return error.InvalidGrouping;
            point = true;
            buf[len] = '.';
            len += 1;
            i += locale.decimal.len;
            continue;
        }
        if (locale.thousands.len > 0 and std.mem.startsWith(u8, s[i..], locale.thousands) and !point) {
            if (!compatible and (group_digits == 0 or (grouped and group_digits != locale.thousands_size) or (!grouped and group_digits > locale.thousands_size))) return error.InvalidGrouping;
            grouped = true;
            group_digits = 0;
            i += locale.thousands.len;
            continue;
        }
        const c = s[i];
        if (std.ascii.isDigit(c) and !point) group_digits += 1;
        if (c == ' ' and compatible) {
            i += 1;
            continue;
        }
        if (c == 'e' or c == 'E') {
            if (!compatible and grouped and group_digits != locale.thousands_size) return error.InvalidGrouping;
            point = true;
        }
        buf[len] = c;
        len += 1;
        i += 1;
    }
    if (!compatible and grouped and !point and group_digits != locale.thousands_size) return error.InvalidGrouping;
    if (compatible and len > 2 and buf[0] == '0') {
        const base: u8 = switch (buf[1]) {
            'x', 'X' => 16,
            'o', 'O' => 8,
            'b', 'B' => 2,
            else => 0,
        };
        if (base != 0) {
            var d = dec.D{ .magnitude = std.fmt.parseInt(u128, buf[2..len], base) catch return error.InvalidNumber, .negative = neg };
            d.magnitude = try dec.checkedMul(d.magnitude, multiplier);
            if (percent) d.scale += 2;
            return d;
        }
    }
    if (compatible and (std.mem.eql(u8, buf[0..len], "Infinity") or std.mem.eql(u8, buf[0..len], "+Infinity") or std.mem.eql(u8, buf[0..len], "-Infinity"))) return .{ .magnitude = 1, .scale = -400, .negative = buf[0] == '-' };
    var result = try dec.parseD(buf[0..len]);
    if (neg) result.negative = !result.negative;
    if (compatible) {
        var v = result.toFloat() * @as(f64, @floatFromInt(@as(u128, @intCast(multiplier))));
        if (percent) v /= 100;
        return compatD(v);
    }
    result.magnitude = try dec.checkedMul(result.magnitude, multiplier);
    if (percent) result.scale += 2;
    return result.normalize();
}

fn compatD(v: f64) t.Error!dec.D {
    if (std.math.isNan(v)) return error.InvalidNumber;
    if (std.math.isInf(v)) return .{ .magnitude = 1, .scale = -400, .negative = v < 0 };
    return dec.from(v);
}
