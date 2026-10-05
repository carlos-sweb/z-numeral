const std = @import("std");
const t = @import("types.zig");
const dec = @import("decimal.zig");
pub const formatAlloc = @import("format.zig").compatAlloc;
pub const formatBuf = @import("format.zig").compatBuf;
pub const formatTo = @import("format.zig").compatTo;
/// Read complete localized text with explicit parse options; return a tagged number or f64, with typed errors.
pub fn unformat(s: []const u8, options: @import("parse.zig").ParseOptions) t.Error!f64 {
    return @import("parse.zig").compatUnformat(s, options);
}
/// Check options or input for validity without allocating; see the signature for error vs boolean result.
pub fn validate(text: []const u8, options: @import("parse.zig").ParseOptions) bool {
    _ = unformat(text, options) catch return false;
    return true;
}
/// Return the borrowed byte suffix, using the selected base or legacy general units.
pub fn byteUnits(value: f64, base: t.Base, locale: ?*const t.Locale) t.Error![]const u8 {
    const l = locale orelse try @import("locales.zig").get("en-US");
    try l.validate();
    if (std.math.isNan(value)) return if (base == .binary) l.binary_suffixes[0] else l.decimal_suffixes[0];
    if (!std.math.isFinite(value)) return if (base == .binary) l.binary_suffixes[8] else l.decimal_suffixes[8];
    return @import("root.zig").byteUnits(value, base, l);
}
pub const Number = struct {
    inner: f64,
    /// Construct a numeric value or validated formatter from the supplied argument; no allocation.
    pub fn init(v: f64) Number {
        return .{ .inner = v };
    }
    /// Return the current numeric value without allocating or modifying it.
    pub fn value(self: Number) f64 {
        return self.inner;
    }
    /// Return the borrowed base-1024 binary suffix for the current value.
    pub fn binaryByteUnits(self: Number) t.Error![]const u8 {
        return @import("compat.zig").byteUnits(self.inner, .binary, null);
    }
    /// Return the borrowed base-1000 decimal suffix for the current value.
    pub fn decimalByteUnits(self: Number) t.Error![]const u8 {
        return @import("compat.zig").byteUnits(self.inner, .decimal, null);
    }
    /// Return the borrowed byte suffix, using the selected base or legacy general units.
    pub fn byteUnits(self: Number) t.Error![]const u8 {
        return @import("compat.zig").byteUnits(self.inner, .general, null);
    }
    /// Copy the current numeric value; no shared mutable state or allocations.
    pub fn clone(self: Number) Number {
        return self;
    }
    /// Replace the stored value; exact mode leaves it unchanged if validation fails.
    pub fn set(self: *Number, v: f64) void {
        self.inner = v;
    }
    /// Add the operand; exact Number mutates only on success, Decimal returns a new value.
    pub fn add(self: *Number, v: f64) void {
        self.inner = arithmetic(self.inner, v, .add);
    }
    /// Subtract the operand; exact Number mutates only on success, Decimal returns a new value.
    pub fn subtract(self: *Number, v: f64) void {
        self.inner = arithmetic(self.inner, v, .subtract);
    }
    /// Multiply by the operand; exact Number mutates only on success, Decimal returns a new value.
    pub fn multiply(self: *Number, v: f64) void {
        self.inner = arithmetic(self.inner, v, .multiply);
    }
    /// Divide by the operand; exact mode requires scale and rounding and reports division by zero.
    pub fn divide(self: *Number, v: f64) void {
        self.inner = arithmetic(self.inner, v, .divide);
    }
    /// Return the absolute difference without modifying the stored value.
    pub fn difference(self: Number, v: f64) f64 {
        return @abs(arithmetic(self.inner, v, .subtract));
    }
};
fn arithmetic(a: f64, b: f64, op: enum { add, subtract, multiply, divide }) f64 {
    if (!std.math.isFinite(a) or !std.math.isFinite(b) or (op == .divide and b == 0)) return switch (op) {
        .add => a + b,
        .subtract => a - b,
        .multiply => a * b,
        .divide => a / b,
    };
    const x = dec.from(a) catch unreachable;
    var y = dec.from(b) catch unreachable;
    if (op == .subtract) y.negative = !y.negative;
    const result = switch (op) {
        .add, .subtract => dec.addD(x, y),
        .multiply => dec.multiplyD(x, y),
        .divide => dec.divideD(x, y, 20, .half_away),
    };
    return if (result) |d| d.toFloat() else |_| switch (op) {
        .add => a + b,
        .subtract => a - b,
        .multiply => a * b,
        .divide => a / b,
    };
}

/// Reusable compatible formatter. Configuration and custom locales are borrowed.
pub const Formatter = struct {
    options: t.Options = .{},
    /// Construct a numeric value or validated formatter from the supplied argument; no allocation.
    pub fn init(options: t.Options) t.Error!Formatter {
        try options.validate();
        return .{ .options = options };
    }
    /// Allocate formatted UTF-8 output with gpa; the caller frees the returned slice. Errors include OutOfMemory.
    pub fn formatAlloc(self: Formatter, gpa: std.mem.Allocator, value: f64, options: t.Options) t.Error![]u8 {
        return @import("compat.zig").formatAlloc(gpa, value, t.Options.merge(self.options, options));
    }
    /// Format into the caller buffer and return its used slice; report BufferTooSmall on insufficient capacity.
    pub fn formatBuf(self: Formatter, buf: []u8, value: f64, options: t.Options) t.Error![]u8 {
        return @import("compat.zig").formatBuf(buf, value, t.Options.merge(self.options, options));
    }
    /// Write a formatted numeric value to the borrowed writer; propagate validation and WriteFailed errors.
    pub fn formatTo(self: Formatter, w: *std.Io.Writer, value: f64, options: t.Options) @import("format.zig").FormatError!void {
        return @import("compat.zig").formatTo(w, value, t.Options.merge(self.options, options));
    }
    /// Resolve a named locale format; return UnknownFormat if the name is absent.
    pub fn named(self: Formatter, name: []const u8) t.Error!t.Options {
        const l = self.options.locale orelse try @import("locales.zig").get("en-US");
        return t.Options.merge(self.options, try l.named(name));
    }
};
