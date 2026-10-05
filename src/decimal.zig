const std = @import("std");
const t = @import("types.zig");
pub const Error = t.Error;
pub const Rounding = t.Rounding;
pub const Wide = u4096;
/// Return a checked decimal power for an exponent up to 1000; larger powers report Overflow.
pub fn pow10(n: usize) Error!Wide {
    if (n > 1000) return error.Overflow;
    var p: Wide = 1;
    for (0..n) |_| p *= 10;
    return p;
}
pub const D = struct {
    negative: bool = false,
    magnitude: Wide = 0,
    scale: i16 = 0,
    /// Remove redundant coefficient zeroes and normalize zero without allocating.
    pub fn normalize(self: D) D {
        var d = self;
        if (d.magnitude == 0) return .{};
        while (d.scale > 0 and d.magnitude % 10 == 0) {
            d.magnitude /= 10;
            d.scale -= 1;
        }
        return d;
    }
    /// Return the absolute integral part using checked scaling; report Overflow if it exceeds the wide representation.
    pub fn integer(self: D) Error!Wide {
        return if (self.scale >= 0) self.magnitude / try pow10(@intCast(self.scale)) else checkedMul(self.magnitude, try pow10(@intCast(-self.scale)));
    }
    /// Scale or round an internal decimal using the requested rule; return Overflow if multiplication exceeds capacity.
    pub fn rescale(self: D, scale: i16, mode: Rounding) Error!D {
        var d = self;
        if (scale >= d.scale) {
            d.magnitude = try checkedMul(d.magnitude, try pow10(@intCast(scale - d.scale)));
        } else {
            const factor = try pow10(@intCast(d.scale - scale));
            d.magnitude = roundQuotient(d.magnitude / factor, d.magnitude % factor, factor, d.negative, mode);
        }
        d.scale = scale;
        if (d.magnitude == 0) d.negative = false;
        return d;
    }
    /// Convert explicitly to f64; the conversion may lose precision.
    pub fn toFloat(self: D) f64 {
        // Conversion through decimal text avoids premature overflow of the wide
        // coefficient for tiny or huge finite floating-point values.
        var buf: [1500]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{s}{d}e{d}", .{ if (self.negative) "-" else "", self.magnitude, -self.scale }) catch unreachable;
        return std.fmt.parseFloat(f64, s) catch unreachable;
    }
};
/// Multiply wide coefficients, reporting Overflow rather than wrapping.
pub fn checkedMul(a: Wide, b: Wide) Error!Wide {
    const r = @mulWithOverflow(a, b);
    if (r[1] != 0) return error.Overflow;
    return r[0];
}
/// Round an unsigned quotient and remainder with an explicit sign and rounding rule.
pub fn roundQuotient(q: Wide, rem: Wide, divisor: Wide, negative: bool, mode: Rounding) Wide {
    if (rem == 0) return q;
    const above = rem > divisor - rem;
    const tie = rem == divisor - rem;
    const up = switch (mode) {
        .half_even => above or (tie and q % 2 == 1),
        .half_away => above or tie,
        .js => above or (tie and !negative),
        .trunc => false,
        .floor => negative,
        .ceil => !negative,
    };
    return q + @intFromBool(up);
}
/// Fixed-scale decimal. The coefficient is always unsigned; sign is separate.
/// Constructors normalize trailing zeroes and reject scales above 38.
pub const Decimal = struct {
    negative: bool = false,
    magnitude: u128 = 0,
    scale: u8 = 0,
    /// Construct a numeric value or validated formatter from the supplied argument; no allocation.
    pub fn init(negative: bool, magnitude: u128, scale: u8) Error!Decimal {
        if (scale > 38) return error.PrecisionOutOfRange;
        return fromD(.{ .negative = negative, .magnitude = magnitude, .scale = scale });
    }
    /// Parse decimal ASCII notation, including an exponent; report invalid syntax, overflow or unsupported precision.
    pub fn parse(s: []const u8) Error!Decimal {
        return fromD(try parseD(s));
    }
    /// Convert an internal decimal to a public representable value; check scale and coefficient bounds.
    pub fn fromD(value: D) Error!Decimal {
        var d = value.normalize();
        if (d.scale < 0) {
            d.magnitude = try checkedMul(d.magnitude, try pow10(@intCast(-d.scale)));
            d.scale = 0;
        }
        if (d.scale > 38) return error.PrecisionOutOfRange;
        if (d.magnitude > std.math.maxInt(u128)) return error.Overflow;
        return .{ .negative = d.negative, .magnitude = @intCast(d.magnitude), .scale = @intCast(d.scale) };
    }
    /// Return the internal exact decimal representation, checking unsupported scale or non-finite floats.
    pub fn toD(self: Decimal) Error!D {
        if (self.scale > 38) return error.PrecisionOutOfRange;
        return (D{ .negative = self.negative, .magnitude = self.magnitude, .scale = self.scale }).normalize();
    }
    /// Convert explicitly to f64; the conversion may lose precision.
    pub fn toFloat(self: Decimal) f64 {
        return (D{ .negative = self.negative, .magnitude = self.magnitude, .scale = self.scale }).toFloat();
    }
    /// Add the operand; exact Number mutates only on success, Decimal returns a new value.
    pub fn add(self: Decimal, other: Decimal) Error!Decimal {
        return fromD(try addD(try self.toD(), try other.toD()));
    }
    /// Subtract the operand; exact Number mutates only on success, Decimal returns a new value.
    pub fn subtract(self: Decimal, other: Decimal) Error!Decimal {
        var b = try other.toD();
        b.negative = !b.negative;
        return fromD(try addD(try self.toD(), b));
    }
    /// Multiply by the operand; exact Number mutates only on success, Decimal returns a new value.
    pub fn multiply(self: Decimal, other: Decimal) Error!Decimal {
        return fromD(try multiplyD(try self.toD(), try other.toD()));
    }
    /// Divide by the operand; exact mode requires scale and rounding and reports division by zero.
    pub fn divide(self: Decimal, other: Decimal, scale: u8, rounding: Rounding) Error!Decimal {
        if (scale > 38) return error.PrecisionOutOfRange;
        return fromD(try divideD(try self.toD(), try other.toD(), scale, rounding));
    }
};
/// Add signed wide decimal values using checked arithmetic.
pub fn addD(a: D, b: D) Error!D {
    const scale = @max(a.scale, b.scale);
    const x = try a.rescale(scale, .trunc);
    const y = try b.rescale(scale, .trunc);
    var r = D{ .scale = scale };
    if (x.negative == y.negative) {
        const sum = @addWithOverflow(x.magnitude, y.magnitude);
        if (sum[1] != 0) return error.Overflow;
        r.magnitude = sum[0];
        r.negative = x.negative;
    } else if (x.magnitude >= y.magnitude) {
        r.magnitude = x.magnitude - y.magnitude;
        r.negative = x.negative;
    } else {
        r.magnitude = y.magnitude - x.magnitude;
        r.negative = y.negative;
    }
    return r.normalize();
}
/// Multiply signed wide decimal values using checked arithmetic.
pub fn multiplyD(a: D, b: D) Error!D {
    return (D{ .magnitude = try checkedMul(a.magnitude, b.magnitude), .negative = a.negative != b.negative, .scale = a.scale + b.scale }).normalize();
}
/// Divide to an explicit scale using the chosen rounding rule; report DivisionByZero or Overflow.
pub fn divideD(a: D, b: D, scale: i16, rounding: Rounding) Error!D {
    if (b.magnitude == 0) return error.DivisionByZero;
    const delta = scale + b.scale - a.scale;
    const numerator = if (delta >= 0) try checkedMul(a.magnitude, try pow10(@intCast(delta))) else a.magnitude;
    const denominator = if (delta < 0) try checkedMul(b.magnitude, try pow10(@intCast(-delta))) else b.magnitude;
    const neg = a.negative != b.negative;
    return (D{ .magnitude = roundQuotient(numerator / denominator, numerator % denominator, denominator, neg, rounding), .negative = neg, .scale = scale }).normalize();
}
/// Parse ASCII decimal notation, including an exponent. No allocation.
pub fn parseD(text: []const u8) Error!D {
    if (text.len == 0 or text.len > 1500) return error.InvalidNumber;
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    var s = text;
    var neg = false;
    if (s[0] == '-' or s[0] == '+') {
        neg = s[0] == '-';
        s = s[1..];
    }
    var mag: Wide = 0;
    var scale: i16 = 0;
    var point = false;
    var digits: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == 'e' or c == 'E') break;
        if (c == '.' and !point) {
            point = true;
            continue;
        }
        if (c < '0' or c > '9') return error.InvalidNumber;
        const m = @mulWithOverflow(mag, 10);
        const a = @addWithOverflow(m[0], c - '0');
        if (m[1] != 0 or a[1] != 0) return error.Overflow;
        mag = a[0];
        digits += 1;
        if (point) scale += 1;
    }
    if (digits == 0) return error.InvalidNumber;
    if (i < s.len) {
        const exp = std.fmt.parseInt(i16, s[i + 1 ..], 10) catch return error.InvalidNumber;
        if (exp < -400 or exp > 400) return error.PrecisionOutOfRange;
        scale -= exp;
    }
    if (scale < -400 or scale > 400) return error.PrecisionOutOfRange;
    return (D{ .negative = neg, .magnitude = mag, .scale = scale }).normalize();
}
/// Convert a supported numeric value to its exact decimal representation; reject non-finite floats.
pub fn from(value: anytype) Error!D {
    const T = @TypeOf(value);
    if (T == Decimal) return value.toD();
    if (T == @import("number.zig").Value) return value.toD();
    if (T == @import("number.zig").Number) return value.inner.toD();
    switch (@typeInfo(T)) {
        .int => |info| {
            if (info.bits > 128) @compileError("numeral supports integers up to 128 bits");
            return .{ .negative = info.signedness == .signed and value < 0, .magnitude = @abs(value) };
        },
        .comptime_int => {
            if (value < -(@as(comptime_int, 1) << 127) or value > std.math.maxInt(u128)) @compileError("integer outside 128-bit range");
            return .{ .negative = value < 0, .magnitude = if (value < 0) -value else value };
        },
        .float, .comptime_float => {
            const Float = if (T == comptime_float) f64 else T;
            if (@typeInfo(Float).float.bits != 32 and @typeInfo(Float).float.bits != 64) @compileError("numeral supports f32 and f64");
            const x: Float = value;
            if (!std.math.isFinite(x)) return error.NonFinite;
            var buf: [800]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{e}", .{x}) catch unreachable;
            return parseD(s);
        },
        else => @compileError("expected integer, float or Decimal"),
    }
}
test "decimal arithmetic and ties" {
    const a = try Decimal.parse("0.1");
    const b = try Decimal.parse("0.2");
    try std.testing.expectEqual(try Decimal.parse("0.3"), try a.add(b));
    try std.testing.expectEqual(try Decimal.parse("0.333333"), try (try Decimal.parse("1")).divide(try Decimal.parse("3"), 6, .half_even));
    try std.testing.expectEqual(@as(Wide, 2), (try (try parseD("2.5")).rescale(0, .half_even)).magnitude);
    try std.testing.expectEqual(@as(Wide, 3), (try (try parseD("2.5")).rescale(0, .half_away)).magnitude);
    try std.testing.expectEqual(@as(Wide, 2), (try (try parseD("-2.5")).rescale(0, .js)).magnitude);
}
