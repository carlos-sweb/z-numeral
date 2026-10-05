const std = @import("std");
const t = @import("types.zig");
/// Parse numbro's historical pattern syntax. Slices in the result borrow text.
pub fn parsePattern(text: []const u8) t.Error!t.Options {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    if (text.len == 0) return error.InvalidPattern;
    var s = text;
    var o = t.Options{};
    if (s[0] == '{') {
        const end = std.mem.indexOfScalar(u8, s, '}') orelse return error.InvalidPattern;
        o.prefix = s[1..end];
        s = s[end + 1 ..];
    }
    if (std.mem.lastIndexOfScalar(u8, s, '{')) |start| {
        if (s[s.len - 1] != '}') return error.InvalidPattern;
        o.postfix = s[start + 1 .. s.len - 1];
        s = s[0..start];
    }
    if (s.len == 0) return error.InvalidPattern;
    var bracket = false;
    var parens: u8 = 0;
    var dots: u8 = 0;
    var has_digit = false;
    for (s) |c| {
        switch (c) {
            '[' => {
                if (bracket) return error.InvalidPattern;
                bracket = true;
            },
            ']' => {
                if (!bracket) return error.InvalidPattern;
                bracket = false;
            },
            '(' => {
                if (parens != 0) return error.InvalidPattern;
                parens = 1;
            },
            ')' => {
                if (parens != 1) return error.InvalidPattern;
                parens = 2;
            },
            '.' => {
                dots += 1;
                if (dots > 1) return error.InvalidPattern;
            },
            '0'...'9' => has_digit = true,
            ',', '+', '-', '$', '%', 'a', 'b', 'd', 'o', ':', ' ', 'K', 'M', 'B', 'T' => {},
            else => return error.InvalidPattern,
        }
    }
    if (bracket or parens == 1 or !has_digit) return error.InvalidPattern;
    if (std.mem.indexOfScalar(u8, s, ':') != null and !std.mem.eql(u8, s, "00:00:00")) return error.InvalidPattern;
    if (contains(s, "$")) o.output = .currency else if (contains(s, "%")) o.output = .percent else if (contains(s, "bd")) {
        o.output = .byte;
        o.base = .general;
    } else if (contains(s, "b")) {
        o.output = .byte;
        o.base = .binary;
    } else if (contains(s, "d")) {
        o.output = .byte;
        o.base = .decimal;
    } else if (contains(s, ":")) o.output = .time else if (contains(s, "o")) o.output = .ordinal;
    if (contains(s, ",")) o.thousand_separated = true;
    if (contains(s, "a")) o.average = true;
    inline for (.{ "K", "M", "B", "T" }, 0..) |marker, i| {
        if (contains(s, marker)) {
            o.force_average = @enumFromInt(i);
            break;
        }
    }
    if (contains(s, " ")) {
        o.space_separated = true;
        o.space_separated_currency = true;
        if ((o.average orelse false) or o.force_average != null) o.space_separated_abbreviation = true;
    }
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] >= '1' and s[i] <= '9') {
            const start = i;
            while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {}
            o.total_length = std.fmt.parseInt(u16, s[start..i], 10) catch return error.InvalidPattern;
            break;
        }
    }
    const dot = std.mem.indexOfScalar(u8, s, '.');
    const characteristic = s[0 .. dot orelse s.len];
    if (zeroRun(characteristic)) |n| o.characteristic = @intCast(n);
    if (dot) |d| {
        const mantissa = s[d + 1 ..];
        if (zeroRun(mantissa)) |n| o.mantissa = @intCast(n);
        o.trim_mantissa = contains(mantissa, "[");
        o.optional_mantissa = contains(s, "[.]");
        o.optional_characteristic = !contains(characteristic, "0");
    }
    var core = s;
    if (core[0] == '+') {
        o.force_sign = true;
        core = core[1..];
    }
    if (core.len >= 2 and core[0] == '(' and core[core.len - 1] == ')') o.negative = .parenthesis;
    try o.validate();
    return o;
}
fn contains(s: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, s, needle) != null;
}
fn zeroRun(s: []const u8) ?usize {
    const start = std.mem.indexOfScalar(u8, s, '0') orelse return null;
    var end = start;
    while (end < s.len and s[end] == '0') : (end += 1) {}
    return end - start;
}
/// Compile a literal pattern and report mistakes at compile time.
pub fn pattern(comptime text: []const u8) t.Options {
    return comptime parsePattern(text) catch |err| @compileError("invalid numeral pattern: " ++ @errorName(err));
}
