//! Translated numbro 2.5.0 formatting rules. See NOTICE and MIT notices.
const std = @import("std");
const t = @import("types.zig");
const dec = @import("decimal.zig");
const locales = @import("locales.zig");
const fmt = @import("format.zig");
const Writer = std.Io.Writer;
const E = fmt.FormatError;
const defaults = t.Options{ .mantissa = -1, .characteristic = 0, .negative = .sign, .thousand_separated = false, .space_separated = false, .average = false, .force_sign = false, .optional_mantissa = true, .space_separated_abbreviation = false };

/// Write the ECMAScript decimal representation of a f64 to a borrowed scratch buffer.
pub fn jsNumber(buf: []u8, value: f64) E![]const u8 {
    if (!std.math.isFinite(value)) return if (std.math.isNan(value)) "NaN" else if (value < 0) "-Infinity" else "Infinity";
    if (value == 0) return "0";
    var d = try dec.from(value);
    while (d.magnitude % 10 == 0) {
        d.magnitude /= 10;
        d.scale -= 1;
    }
    const exp = @as(i16, @intCast(fmt.digitCount(d.magnitude))) - 1 - d.scale;
    var w = Writer.fixed(buf);
    if (value < 0) try w.writeByte('-');
    var digitsbuf: [1500]u8 = undefined;
    if (exp < -6 or exp >= 21) {
        const digits = std.fmt.bufPrint(&digitsbuf, "{d}", .{d.magnitude}) catch return error.Overflow;
        try w.writeByte(digits[0]);
        if (digits.len > 1) {
            try w.writeByte('.');
            try w.writeAll(digits[1..]);
        }
        try w.print("e{s}{d}", .{ if (exp >= 0) "+" else "", exp });
    } else {
        d.negative = false;
        const text = try fmt.ascii(&digitsbuf, d, @max(d.scale, 0));
        try w.writeAll(text);
    }
    return w.buffered();
}
fn fixed(buf: []u8, value: f64, precision: i16, o: t.Options) E![]const u8 {
    var rawbuf: [1500]u8 = undefined;
    const raw = try jsNumber(&rawbuf, value);
    var d = try dec.from(value);
    if (std.mem.indexOfScalar(u8, raw, 'e') == null) {
        var scaledbuf: [1600]u8 = undefined;
        const scaled = std.fmt.bufPrint(&scaledbuf, "{s}e+{d}", .{ raw, precision }) catch return error.Overflow;
        const x = std.fmt.parseFloat(f64, scaled) catch return error.InvalidNumber;
        const v = fmt.roundedFloat(x, o) / std.math.pow(f64, 10, @as(f64, @floatFromInt(precision)));
        if (!std.math.isFinite(v)) return jsNumber(buf, v);
        d = try dec.from(v);
        d = try d.rescale(precision, .half_away);
    } else d = try d.rescale(precision, .trunc);
    var w = Writer.fixed(buf);
    // toFixedLarge keeps a negative zero; the later insertSign step removes
    // its minus only when the localized output still coerces to numeric zero.
    const negative = d.negative or (value < 0 and std.mem.indexOfScalar(u8, raw, 'e') != null);
    if (negative) try w.writeByte('-');
    var digits: [1500]u8 = undefined;
    try w.writeAll(try fmt.ascii(&digits, d, precision));
    return w.buffered();
}
fn onlyOutput(o: t.Options) bool {
    inline for (@typeInfo(t.Options).@"struct".fields) |f| {
        if (comptime !std.mem.eql(u8, f.name, "output") and !std.mem.eql(u8, f.name, "locale")) if (@field(o, f.name) != null) return false;
    }
    return true;
}
fn special(l: *const t.Locale, output: t.Output) t.Options {
    return switch (output) {
        .number => .{},
        .currency => l.currency_format,
        .percent => l.percentage_format,
        .byte => l.byte_format,
        .ordinal => l.ordinal_format,
        .time => l.time_format,
    };
}

/// Render using this engine's semantics; propagate configuration, numeric and writer errors.
pub fn render(w: *Writer, original: f64, provided: t.Options) E!void {
    try provided.validate();
    const l = provided.locale orelse try locales.get("en-US");
    var p = provided;
    const output = p.output orelse .number;
    if (output == .byte and p.base == null) return error.InvalidOptions;
    if (onlyOutput(p) and output != .number) p = t.Options.merge(special(l, output), p);
    const o = t.Options.merge(defaults, p);
    try w.writeAll(p.prefix orelse "");
    if (output == .time) {
        const hours = @floor(original / 60 / 60);
        const minutes = @floor((original - hours * 3600) / 60);
        const seconds = fmt.roundedFloat(original - hours * 3600 - minutes * 60, .{});
        var b: [1500]u8 = undefined;
        try w.writeAll(try jsNumber(&b, hours));
        try w.writeByte(':');
        if (minutes < 10) try w.writeByte('0');
        try w.writeAll(try jsNumber(&b, minutes));
        try w.writeByte(':');
        if (seconds < 10) try w.writeByte('0');
        try w.writeAll(try jsNumber(&b, seconds));
    } else {
        var value = original;
        var suffix: []const u8 = "";
        if (output == .percent) value *= 100;
        if (output == .byte) {
            const base = p.base.?;
            const scale: f64 = if (base == .decimal) 1000 else 1024;
            const suffixes = if (base == .binary) l.binary_suffixes else l.decimal_suffixes;
            var unit: usize = 0;
            var divisor: f64 = 1;
            if (@abs(value) >= scale) {
                while (unit < 8 and @abs(value) >= divisor * scale) {
                    unit += 1;
                    divisor *= scale;
                }
                value /= divisor;
            }
            suffix = suffixes[unit];
        }
        const position = o.currency_position orelse l.currency_position;
        const symbol = o.currency_symbol orelse l.currency_symbol;
        const space = o.space_separated orelse false;
        const cs = o.space_separated_currency orelse space;
        var sepbuf: [1500]u8 = undefined;
        const separator = if (output == .currency and position == .infix) (std.fmt.bufPrint(&sepbuf, "{s}{s}{s}", .{ if (cs) " " else "", symbol, if (cs) " " else "" }) catch return error.Overflow) else l.decimal;
        var corebuf: [6000]u8 = undefined;
        var corep = p;
        if (output == .currency and corep.low_precision == null) corep.low_precision = false;
        const number = try core(&corebuf, value, corep, l, separator);
        switch (output) {
            .currency => {
                const average = (o.average orelse false) or o.force_average != null or (o.total_length orelse 0) != 0;
                if (position == .prefix) {
                    if (original < 0 and o.negative == .sign) {
                        try w.writeByte('-');
                        if (cs) try w.writeByte(' ');
                        try w.writeAll(symbol);
                        try w.writeAll(number[@min(1, number.len)..]);
                    } else if (original > 0 and (o.force_sign orelse false)) {
                        try w.writeByte('+');
                        if (cs) try w.writeByte(' ');
                        try w.writeAll(symbol);
                        try w.writeAll(number[@min(1, number.len)..]);
                    } else {
                        try w.writeAll(symbol);
                        if (cs) try w.writeByte(' ');
                        try w.writeAll(number);
                    }
                } else {
                    try w.writeAll(number);
                    if (position == .postfix) {
                        if (cs and (!average or (o.space_separated_abbreviation orelse false))) try w.writeByte(' ');
                        try w.writeAll(symbol);
                    }
                }
            },
            .percent => {
                if (o.prefix_symbol orelse false) {
                    try w.writeByte('%');
                    if (space) try w.writeByte(' ');
                    try w.writeAll(number);
                } else {
                    try w.writeAll(number);
                    if (space) try w.writeByte(' ');
                    try w.writeByte('%');
                }
            },
            .byte => {
                try w.writeAll(number);
                if (space) try w.writeByte(' ');
                try w.writeAll(suffix);
            },
            .ordinal => {
                try w.writeAll(number);
                if (space) try w.writeByte(' ');
                const ord = l.ordinal(original);
                try w.writeAll(if (l.ordinal_rule == .turkish and ord.len == 0) "undefined" else ord);
            },
            else => try w.writeAll(number),
        }
    }
    try w.writeAll(p.postfix orelse "");
}
fn core(buf: []u8, original: f64, p: t.Options, l: *const t.Locale, separator: []const u8) E![]const u8 {
    if (original == 0) if (p.zero_format) |zero| return zero;
    if (!std.math.isFinite(original)) return if (std.math.isNan(original)) "NaN" else if (original < 0) "-Infinity" else "Infinity";
    const o = t.Options.merge(t.Options.merge(defaults, l.defaults), p);
    var v = original;
    const total = o.total_length orelse 0;
    const characteristic = if (total != 0) 0 else o.characteristic orelse 0;
    const average = total != 0 or o.force_average != null or (o.average orelse false);
    var mantissa: i16 = if (total != 0) -1 else if (average and p.mantissa == null) 0 else o.mantissa orelse -1;
    const optional = if (total != 0) false else p.optional_mantissa orelse (mantissa == -1);
    var abbreviation: []const u8 = "";
    var exponent: ?i16 = null;
    if (average) {
        var unit: ?usize = null;
        if (o.force_average) |a| unit = @intFromEnum(a) else {
            var i: usize = 4;
            while (i > 0) {
                i -= 1;
                const divisor = std.math.pow(f64, 10, @as(f64, @floatFromInt((i + 1) * 3)));
                if (@abs(v) >= divisor or ((o.low_precision orelse true) and fmt.roundedFloat(@abs(v) / divisor, o) == 1)) {
                    unit = i;
                    break;
                }
            }
        }
        if (unit) |i| {
            v /= std.math.pow(f64, 10, @as(f64, @floatFromInt((i + 1) * 3)));
            abbreviation = l.abbreviations.at(i);
        }
        if (total != 0) {
            var b: [1500]u8 = undefined;
            var s = try jsNumber(&b, v);
            if (v < 0) s = s[1..];
            const length = std.mem.indexOfScalar(u8, s, '.') orelse s.len;
            mantissa = @intCast(total -| length);
        }
    }
    if (o.exponential orelse false) {
        var d = try dec.from(v);
        while (d.magnitude != 0 and d.magnitude % 10 == 0) {
            d.magnitude /= 10;
            d.scale -= 1;
        }
        const exp: i16 = if (v == 0) 0 else @as(i16, @intCast(fmt.digitCount(d.magnitude))) - 1 - d.scale;
        d.scale += exp;
        v = d.toFloat();
        exponent = exp;
        if (characteristic > 1) {
            v *= std.math.pow(f64, 10, @as(f64, @floatFromInt(characteristic - 1)));
            exponent.? -= @intCast(characteristic - 1);
        }
    }
    var rawbuf: [2000]u8 = undefined;
    const raw = if (mantissa == -1) try jsNumber(&rawbuf, v) else try fixed(&rawbuf, v, mantissa, o);
    const dot = std.mem.indexOfScalar(u8, raw, '.');
    var integral = raw[0 .. dot orelse raw.len];
    var fraction: []const u8 = if (dot) |i| raw[i + 1 ..] else "";
    const trim = o.trim_mantissa orelse false;
    if ((trim or optional) and allZero(fraction)) fraction = "";
    if (trim) while (fraction.len > 0 and fraction[fraction.len - 1] == '0') {
        fraction = fraction[0 .. fraction.len - 1];
    };
    const optional_char = o.optional_characteristic orelse false;
    const is_zero = std.mem.eql(u8, integral, "0") or std.mem.eql(u8, integral, "-0");
    if (optional_char and is_zero) integral = if (std.mem.startsWith(u8, integral, "-")) "-" else "";
    const neg = v < 0 and std.mem.startsWith(u8, integral, "-");
    if (neg) integral = integral[1..];
    const pad = if (optional_char and is_zero) 0 else characteristic -| integral.len;
    var padded: [2400]u8 = undefined;
    if (pad + integral.len > padded.len) return error.Overflow;
    @memset(padded[0..pad], '0');
    @memcpy(padded[pad..][0..integral.len], integral);
    integral = padded[0 .. pad + integral.len];
    var out: [6000]u8 = undefined;
    var w = Writer.fixed(&out);
    if (neg) try w.writeByte('-');
    for (integral, 0..) |c, i| {
        if (i > 0 and (o.thousand_separated orelse false) and (integral.len - i) % l.thousands_size == 0) try w.writeAll(l.thousands);
        try w.writeByte(c);
    }
    if (fraction.len > 0) {
        try w.writeAll(separator);
        try w.writeAll(fraction);
    }
    if (exponent) |e| try w.print("e{s}{d}", .{ if (e >= 0) "+" else "", e });
    if (abbreviation.len > 0) {
        if (o.space_separated orelse false) try w.writeByte(' ');
        try w.writeAll(abbreviation);
    }
    var result: []const u8 = w.buffered();
    var dest = Writer.fixed(buf);
    if ((o.force_sign orelse false) or v < 0) {
        const numeric = if (result.len == 0) @as(f64, 0) else std.fmt.parseFloat(f64, result) catch std.math.nan(f64);
        if (numeric == 0) {
            for (result) |c| if (c != '-') try dest.writeByte(c);
            return dest.buffered();
        }
        if (v > 0) try dest.writeByte('+') else if (v < 0 and o.negative == .parenthesis) {
            try dest.writeByte('(');
            if (std.mem.startsWith(u8, result, "-")) result = result[1..];
            try dest.writeAll(result);
            try dest.writeByte(')');
            return dest.buffered();
        }
    }
    try dest.writeAll(result);
    return dest.buffered();
}
fn allZero(s: []const u8) bool {
    for (s) |c| if (c != '0') return false;
    return true;
}
