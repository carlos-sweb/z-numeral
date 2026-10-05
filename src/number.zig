const std = @import("std");
const dec = @import("decimal.zig");
const t = @import("types.zig");
/// Tagged numeric value. Exact arithmetic never silently converts to floating point.
pub const Value = union(enum) {
    signed: i128,
    unsigned: u128,
    decimal: dec.Decimal,
    float: f64,
    /// Return the internal exact decimal representation, checking unsupported scale or non-finite floats.
    pub fn toD(self: Value) t.Error!dec.D {
        return switch (self) {
            .signed => |v| dec.from(v),
            .unsigned => |v| dec.from(v),
            .decimal => |v| dec.from(v),
            .float => |v| dec.from(v),
        };
    }
    /// Convert explicitly to f64; the conversion may lose precision.
    pub fn toFloat(self: Value) f64 {
        return switch (self) {
            .signed => |v| @floatFromInt(v),
            .unsigned => |v| @floatFromInt(v),
            .decimal => |v| v.toFloat(),
            .float => |v| v,
        };
    }
    /// Construct a numeric value or validated formatter from the supplied argument; no allocation.
    pub fn init(value: anytype) t.Error!Value {
        const T = @TypeOf(value);
        if (T == Value) return value;
        if (T == Number) return value.inner;
        if (T == dec.Decimal) return .{ .decimal = try dec.Decimal.fromD(try value.toD()) };
        return switch (@typeInfo(T)) {
            .float => |info| blk: {
                if (info.bits != 32 and info.bits != 64) @compileError("numeral supports f32 and f64");
                const v: f64 = @floatCast(value);
                break :blk if (std.math.isFinite(v)) .{ .float = v } else error.NonFinite;
            },
            .comptime_float => if (std.math.isFinite(@as(f64, value))) .{ .float = value } else error.NonFinite,
            .int => |i| if (i.signedness == .signed) .{ .signed = value } else .{ .unsigned = value },
            .comptime_int => if (value < 0) .{ .signed = value } else .{ .unsigned = value },
            else => @compileError("expected numeric value"),
        };
    }
};
/// Convert an internal decimal to a public representable value; check scale and coefficient bounds.
pub fn fromD(d: dec.D, prefer_signed: bool) t.Error!Value {
    const v = try dec.Decimal.fromD(d);
    if (v.scale != 0) return .{ .decimal = v };
    if (v.negative) {
        const limit = @as(u128, 1) << 127;
        if (v.magnitude > limit) return .{ .decimal = v };
        return .{ .signed = if (v.magnitude == limit) std.math.minInt(i128) else -@as(i128, @intCast(v.magnitude)) };
    }
    if (prefer_signed and v.magnitude <= std.math.maxInt(i128)) return .{ .signed = @intCast(v.magnitude) };
    return .{ .unsigned = v.magnitude };
}
pub const Number = struct {
    inner: Value,
    /// Construct a numeric value or validated formatter from the supplied argument; no allocation.
    pub fn init(v: anytype) t.Error!Number {
        return .{ .inner = try Value.init(v) };
    }
    /// Return the current numeric value without allocating or modifying it.
    pub fn value(self: Number) Value {
        return self.inner;
    }
    /// Return the borrowed base-1024 binary suffix for the current value.
    pub fn binaryByteUnits(self: Number) t.Error![]const u8 {
        return @import("root.zig").byteUnits(self.inner, .binary, null);
    }
    /// Return the borrowed base-1000 decimal suffix for the current value.
    pub fn decimalByteUnits(self: Number) t.Error![]const u8 {
        return @import("root.zig").byteUnits(self.inner, .decimal, null);
    }
    /// Return the borrowed byte suffix, using the selected base or legacy general units.
    pub fn byteUnits(self: Number) t.Error![]const u8 {
        return @import("root.zig").byteUnits(self.inner, .general, null);
    }
    /// Copy the current numeric value; no shared mutable state or allocations.
    pub fn clone(self: Number) Number {
        return self;
    }
    /// Replace the stored value; exact mode leaves it unchanged if validation fails.
    pub fn set(self: *Number, v: anytype) t.Error!void {
        self.inner = try Value.init(v);
    }
    /// Explicit conversion, which may lose precision.
    pub fn toFloat(self: Number) f64 {
        return self.inner.toFloat();
    }
    /// Add the operand; exact Number mutates only on success, Decimal returns a new value.
    pub fn add(self: *Number, v: anytype) t.Error!void {
        const other = try Value.init(v);
        self.inner = try operation(self.inner, other, .add);
    }
    /// Subtract the operand; exact Number mutates only on success, Decimal returns a new value.
    pub fn subtract(self: *Number, v: anytype) t.Error!void {
        const other = try Value.init(v);
        self.inner = try operation(self.inner, other, .subtract);
    }
    /// Multiply by the operand; exact Number mutates only on success, Decimal returns a new value.
    pub fn multiply(self: *Number, v: anytype) t.Error!void {
        const other = try Value.init(v);
        self.inner = try operation(self.inner, other, .multiply);
    }
    /// Divide by the operand; exact mode requires scale and rounding and reports division by zero.
    pub fn divide(self: *Number, v: anytype, scale: u8, rounding: t.Rounding) t.Error!void {
        if (scale > 38) return error.PrecisionOutOfRange;
        const other = try Value.init(v);
        if (self.inner == .float or other == .float) {
            if (self.inner != .float or other != .float) return error.MixedNumericTypes;
            if (other.float == 0) return error.DivisionByZero;
            const result = self.inner.float / other.float;
            if (!std.math.isFinite(result)) return error.NonFinite;
            self.inner = .{ .float = result };
            return;
        }
        const result = try dec.divideD(try self.inner.toD(), try other.toD(), scale, rounding);
        self.inner = try resultValue(result, self.inner, other);
    }
    /// Return the absolute difference without modifying the stored value.
    pub fn difference(self: Number, v: anytype) t.Error!Value {
        const other = try Value.init(v);
        if (self.inner == .float or other == .float) {
            if (self.inner != .float or other != .float) return error.MixedNumericTypes;
            const r = @abs(self.inner.float - other.float);
            if (!std.math.isFinite(r)) return error.NonFinite;
            return .{ .float = r };
        }
        var b = try other.toD();
        b.negative = !b.negative;
        var d = try dec.addD(try self.inner.toD(), b);
        d.negative = false;
        if (self.inner == .decimal or other == .decimal) return .{ .decimal = try dec.Decimal.fromD(d) };
        return fromD(d, false);
    }
};
fn resultValue(d: dec.D, a: Value, b: Value) t.Error!Value {
    if (a == .decimal or b == .decimal) return .{ .decimal = try dec.Decimal.fromD(d) };
    const v = try fromD(d, a == .signed and b == .signed);
    if (a == .signed and b == .signed and (v == .unsigned or v == .decimal)) {
        if (v == .decimal and v.decimal.scale != 0) return v;
        return error.Overflow;
    }
    if (a == .unsigned and b == .unsigned and d.negative) return error.Overflow;
    return v;
}
fn operation(a: Value, b: Value, op: enum { add, subtract, multiply }) t.Error!Value {
    if (a == .float or b == .float) {
        if (a != .float or b != .float) return error.MixedNumericTypes;
        const r = switch (op) {
            .add => a.float + b.float,
            .subtract => a.float - b.float,
            .multiply => a.float * b.float,
        };
        if (!std.math.isFinite(r)) return error.NonFinite;
        return .{ .float = r };
    }
    const x = try a.toD();
    var y = try b.toD();
    if (op == .subtract) y.negative = !y.negative;
    const d = if (op == .multiply) try dec.multiplyD(x, y) else try dec.addD(x, y);
    return resultValue(d, a, b);
}
