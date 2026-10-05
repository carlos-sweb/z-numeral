const std = @import("std");
const t = @import("types.zig");
const dec = @import("decimal.zig");
const locales = @import("locales.zig");
const Writer = std.Io.Writer;
const D = dec.D;
const Wide = dec.Wide;
pub const FormatError = t.Error || Writer.Error;
const builtin = t.Options{ .mantissa = -1, .characteristic = 0, .negative = .sign, .thousand_separated = false, .space_separated = false, .average = false, .force_sign = false, .optional_mantissa = true, .space_separated_abbreviation = false };

/// Write a formatted numeric value to the borrowed writer; propagate validation and WriteFailed errors.
pub fn formatTo(w: *Writer, value: anytype, options: t.Options) FormatError!void {
    return render(w, try dec.from(value), options);
}
/// Format into the caller buffer and return its used slice; report BufferTooSmall on insufficient capacity.
pub fn formatBuf(buf: []u8, value: anytype, options: t.Options) t.Error![]u8 {
    var w = Writer.fixed(buf);
    formatTo(&w, value, options) catch |err| {
        if (err == error.WriteFailed) return error.BufferTooSmall;
        return @errorCast(err);
    };
    return w.buffered();
}
/// Allocate formatted UTF-8 output with gpa; the caller frees the returned slice. Errors include OutOfMemory.
pub fn formatAlloc(gpa: std.mem.Allocator, value: anytype, options: t.Options) t.Error![]u8 {
    var w = Writer.Allocating.init(gpa);
    defer w.deinit();
    formatTo(&w.writer, value, options) catch |err| {
        if (err == error.WriteFailed) return error.OutOfMemory;
        return @errorCast(err);
    };
    return w.toOwnedSlice();
}
/// Write numbro-compatible f64 output to a borrowed writer; propagate typed errors.
pub fn compatTo(w: *Writer, value: f64, options: t.Options) FormatError!void {
    return @import("compat_format.zig").render(w, value, options);
}
/// Format a compatible f64 into a borrowed buffer; return its slice or BufferTooSmall.
pub fn compatBuf(buf: []u8, value: f64, options: t.Options) t.Error![]u8 {
    var w = Writer.fixed(buf);
    compatTo(&w, value, options) catch |err| {
        if (err == error.WriteFailed) return error.BufferTooSmall;
        return @errorCast(err);
    };
    return w.buffered();
}
/// Allocate numbro-compatible output; the caller frees the slice with gpa.
pub fn compatAlloc(gpa: std.mem.Allocator, value: f64, options: t.Options) t.Error![]u8 {
    var w = Writer.Allocating.init(gpa);
    defer w.deinit();
    compatTo(&w.writer, value, options) catch |err| {
        if (err == error.WriteFailed) return error.OutOfMemory;
        return @errorCast(err);
    };
    return w.toOwnedSlice();
}

fn specialDefaults(l: *const t.Locale, output: t.Output) t.Options {
    return switch (output) {
        .number => .{},
        .currency => l.currency_format,
        .percent => l.percentage_format,
        .byte => l.byte_format,
        .ordinal => l.ordinal_format,
        .time => l.time_format,
    };
}
fn onlyOutput(o: t.Options) bool {
    inline for (@typeInfo(t.Options).@"struct".fields) |f| {
        if (comptime !std.mem.eql(u8, f.name, "output") and !std.mem.eql(u8, f.name, "locale")) {
            if (@field(o, f.name) != null) return false;
        }
    }
    return true;
}

fn render(w: *Writer, original: D, provided: t.Options) FormatError!void {
    try provided.validate();
    const locale = provided.locale orelse try locales.get("en-US");
    var p = provided;
    const output = p.output orelse .number;
    if (onlyOutput(p) and output != .number) p = t.Options.merge(specialDefaults(locale, output), p);
    var o = t.Options.merge(t.Options.merge(builtin, locale.defaults), p);
    try o.validate();
    if (o.rounding_function != null) return error.InvalidOptions;
    if (output == .currency and o.low_precision == null) o.low_precision = false;
    const mode = o.rounding orelse .half_even;
    try w.writeAll(o.prefix orelse "");
    if (output == .time) {
        const d = try original.rescale(0, mode);
        const count = d.magnitude;
        try w.print("{s}{d}:{d:0>2}:{d:0>2}", .{ if (d.negative) "-" else "", count / 3600, (count / 60) % 60, count % 60 });
        try w.writeAll(o.postfix orelse "");
        return;
    }
    var d = original;
    var byte_suffix: []const u8 = "";
    if (output == .percent) d.scale -= 2;
    if (output == .byte) {
        const base = o.base orelse .binary;
        const factor: Wide = if (base == .decimal) 1000 else 1024;
        var divisor: Wide = 1;
        var power: usize = 0;
        const integral = try d.integer();
        while (power < 8 and integral >= divisor * factor) {
            divisor *= factor;
            power += 1;
        }
        const suffixes = if (base == .binary) locale.binary_suffixes else locale.decimal_suffixes;
        byte_suffix = suffixes[power];
        d = try dec.divideD(d, .{ .magnitude = divisor }, 38, mode);
    }
    const average = (o.average orelse false) or o.force_average != null or (o.total_length orelse 0) != 0;
    var abbreviation: []const u8 = "";
    if (average) {
        const unit: ?usize = if (o.force_average) |force| @intFromEnum(force) else try averageUnit(d, o.low_precision orelse true, mode);
        if (unit) |i| {
            abbreviation = (o.abbreviations orelse locale.abbreviations).at(i);
            d.scale += @intCast((i + 1) * 3);
        }
    }
    var mantissa = if (average and p.mantissa == null) @as(i16, 0) else o.mantissa orelse -1;
    const total = o.total_length orelse 0;
    if (total > 0) mantissa = @intCast(total -| digitCount(try d.integer()));
    var exponent: ?i16 = null;
    if (o.exponential orelse false) {
        const digits = digitCount(d.magnitude);
        const exp = if (d.magnitude == 0) 0 else @as(i16, @intCast(digits)) - 1 - d.scale;
        const char: i16 = @intCast(@max(o.characteristic orelse 0, 1));
        exponent = exp - char + 1;
        d.scale += exponent.?;
    }
    if (mantissa < 0) d = d.normalize() else d = try d.rescale(mantissa, mode);
    const optional_mantissa = if (total > 0) false else p.optional_mantissa orelse (mantissa == -1);
    const trim = o.trim_mantissa orelse false;
    var rawbuf: [1500]u8 = undefined;
    const raw = try ascii(&rawbuf, d, if (mantissa >= 0) mantissa else @max(d.scale, 0));
    const dot = std.mem.indexOfScalar(u8, raw, '.');
    var integral: []const u8 = raw[0 .. dot orelse raw.len];
    var fraction: []const u8 = if (dot) |i| raw[i + 1 ..] else "";
    if (trim) {
        while (fraction.len > 0 and fraction[fraction.len - 1] == '0') fraction = fraction[0 .. fraction.len - 1];
    }
    if (optional_mantissa and allZero(fraction)) fraction = "";
    if ((o.optional_characteristic orelse false) and allZero(integral)) integral = "";
    const zero_core = original.magnitude == 0 and o.zero_format != null;
    if (zero_core) {
        integral = o.zero_format.?;
        fraction = "";
        abbreviation = "";
        exponent = null;
    }
    const characteristic = if (zero_core or total > 0) 0 else o.characteristic orelse 0;
    const pad = characteristic -| integral.len;
    var intbuf: [1900]u8 = undefined;
    if (pad + integral.len > intbuf.len) return error.Overflow;
    @memset(intbuf[0..pad], '0');
    @memcpy(intbuf[pad..][0..integral.len], integral);
    integral = intbuf[0 .. pad + integral.len];
    const neg = d.negative;
    const parentheses = neg and o.negative == .parenthesis;
    const force = (o.force_sign orelse false) and !neg and d.magnitude != 0;
    const symbol = o.currency_symbol orelse locale.currency_symbol;
    const position = o.currency_position orelse locale.currency_position;
    const space = o.space_separated orelse false;
    const currency_space = o.space_separated_currency orelse space;
    if (parentheses) try w.writeAll("(");
    if (neg and !parentheses) try w.writeAll("-") else if (force) try w.writeAll("+");
    if (output == .percent and (o.prefix_symbol orelse false)) {
        try w.writeAll("%");
        if (space) try w.writeAll(" ");
    }
    if (output == .currency and position == .prefix) {
        try w.writeAll(symbol);
        if (currency_space) try w.writeAll(" ");
    }
    const group = locale.thousands_size;
    for (integral, 0..) |c, i| {
        if (i > 0 and !zero_core and (o.thousand_separated orelse false) and (integral.len - i) % group == 0) try w.writeAll(locale.thousands);
        try w.writeByte(c);
    }
    if (fraction.len > 0) {
        if (output == .currency and position == .infix) {
            if (currency_space) try w.writeAll(" ");
            try w.writeAll(symbol);
            if (currency_space) try w.writeAll(" ");
        } else try w.writeAll(locale.decimal);
        try w.writeAll(fraction);
    }
    if (exponent) |e| {
        try w.print("e{s}{d}", .{ if (e >= 0) "+" else "", e });
    }
    if (abbreviation.len > 0) {
        if (space) try w.writeAll(" ");
        try w.writeAll(abbreviation);
    }
    if (output == .currency and position == .postfix) {
        if (currency_space) try w.writeAll(" ");
        try w.writeAll(symbol);
    }
    if (output == .percent and !(o.prefix_symbol orelse false)) {
        if (space) try w.writeAll(" ");
        try w.writeAll("%");
    }
    if (output == .byte) {
        if (space) try w.writeAll(" ");
        try w.writeAll(byte_suffix);
    }
    if (output == .ordinal) {
        if (space) try w.writeAll(" ");
        try w.writeAll(try ordinalExact(locale, original));
    }
    if (parentheses) try w.writeAll(")");
    try w.writeAll(o.postfix orelse "");
}
fn averageUnit(d: D, low_precision: bool, mode: t.Rounding) t.Error!?usize {
    var abs = d;
    abs.negative = false;
    const integral = try abs.integer();
    var i: usize = 4;
    while (i > 0) {
        i -= 1;
        const divisor = try dec.pow10((i + 1) * 3);
        if (integral >= divisor) return i;
        if (low_precision and (try dec.divideD(abs, .{ .magnitude = divisor }, 0, mode)).magnitude == 1) return i;
    }
    return null;
}
/// Evaluate a locale ordinal without discarding decimal precision; use its exact callback when supplied.
pub fn ordinalExact(l: *const t.Locale, d: D) t.Error![]const u8 {
    if (l.ordinal_exact_fn) |f| return f(try dec.Decimal.fromD(d));
    if (l.ordinal_fn) |f| return f(d.toFloat());
    const norm = d.normalize();
    const n = try norm.integer();
    const whole = norm.scale <= 0;
    const rem100: u16 = @intCast(n % 100);
    const nonzero = norm.magnitude != 0;
    return switch (l.ordinal_rule) {
        .constant => l.ordinal_constant,
        .english => if (norm.negative or !whole or rem100 / 10 == 1) "th" else switch (rem100 % 10) {
            1 => "st",
            2 => "nd",
            3 => "rd",
            else => "th",
        },
        .spanish => if (!whole) "to" else if (norm.negative and rem100 % 10 != 0) "to" else switch (rem100 % 10) {
            1, 3 => "er",
            2 => "do",
            7, 0 => "mo",
            8 => "vo",
            9 => "no",
            else => "to",
        },
        .french => if (!norm.negative and whole and n == 1) "er" else "ème",
        .dutch => if ((nonzero and (norm.negative or rem100 == 0 or (whole and rem100 == 1))) or (whole and rem100 == 8) or (!norm.negative and rem100 >= 20)) "ste" else "de",
        .turkish => if (whole) l.ordinal(if (norm.negative) -@as(f64, @floatFromInt(@as(u16, @intCast(if (n <= 1000) n else n % 1000 + 1000)))) else @floatFromInt(@as(u16, @intCast(if (n <= 1000) n else n % 1000 + 1000)))) else if (norm.negative or (n < 100 and rem100 / 10 == 0)) "" else l.ordinal(@as(f64, @floatFromInt(rem100 / 10 * 10 + (if (n >= 100) @as(u16, 100) else 0)))),
    };
}
/// Count decimal digits in a nonnegative coefficient (zero has one digit).
pub fn digitCount(n: Wide) u16 {
    var x = n;
    var count: u16 = 1;
    while (x >= 10) {
        x /= 10;
        count += 1;
    }
    return count;
}
fn allZero(s: []const u8) bool {
    for (s) |c| if (c != '0') return false;
    return true;
}
/// Emit an unsigned ASCII decimal at the requested precision into scratch storage.
pub fn ascii(buf: []u8, d: D, precision: i16) FormatError![]u8 {
    const v = try d.rescale(precision, .trunc);
    var digitsbuf: [1500]u8 = undefined;
    const digits = std.fmt.bufPrint(&digitsbuf, "{d}", .{v.magnitude}) catch return error.Overflow;
    var w = Writer.fixed(buf);
    const scale: usize = @intCast(@max(precision, 0));
    if (scale == 0) {
        try w.writeAll(digits);
    } else if (digits.len > scale) {
        try w.writeAll(digits[0 .. digits.len - scale]);
        try w.writeByte('.');
        try w.writeAll(digits[digits.len - scale ..]);
    } else {
        try w.writeAll("0.");
        for (0..scale - digits.len) |_| try w.writeByte('0');
        try w.writeAll(digits);
    }
    return w.buffered();
}
/// Apply a compatible callback or built-in rounding rule to a scaled f64.
pub fn roundedFloat(x: f64, o: t.Options) f64 {
    if (o.rounding_function) |f| return f(x);
    return switch (o.rounding orelse .js) {
        .js => @floor(x) + @as(f64, if (x - @floor(x) >= 0.5) 1 else 0),
        .half_away => @round(x),
        .half_even => blk: {
            const floor = @floor(x);
            const rem = x - floor;
            break :blk if (rem > 0.5 or (rem == 0.5 and @mod(floor, 2.0) == 1)) floor + 1 else floor;
        },
        .trunc => @trunc(x),
        .floor => @floor(x),
        .ceil => @ceil(x),
    };
}
