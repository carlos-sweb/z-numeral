//! z-numeral: exact and numbro-compatible number formatting for Zig 0.16.0.
const std = @import("std");
pub const version = "0.1.0";
pub const reference_version = "numbro@2.5.0";
pub const types = @import("types.zig");
pub const Options = types.Options;
pub const Error = types.Error;
pub const FormatError = @import("format.zig").FormatError;
pub const Locale = types.Locale;
pub const Rounding = types.Rounding;
pub const Output = types.Output;
pub const Base = types.Base;
pub const Position = types.Position;
pub const Negative = types.Negative;
pub const Average = types.Average;
pub const Abbreviations = types.Abbreviations;
pub const NamedFormat = types.NamedFormat;
pub const Decimal = @import("decimal.zig").Decimal;
pub const Value = @import("number.zig").Value;
pub const Number = @import("number.zig").Number;
pub const locales = @import("locales.zig");
pub const parsePattern = @import("pattern.zig").parsePattern;
pub const pattern = @import("pattern.zig").pattern;
pub const formatAlloc = @import("format.zig").formatAlloc;
pub const formatBuf = @import("format.zig").formatBuf;
pub const formatTo = @import("format.zig").formatTo;
pub const compat = @import("compat.zig");
pub const ParseOptions = @import("parse.zig").ParseOptions;
pub const unformat = @import("parse.zig").unformat;
/// True when a complete localized input is valid under the requested options.
pub fn validate(text: []const u8, options: ParseOptions) bool {
    _ = unformat(text, options) catch return false;
    return true;
}
/// Return the unit selected for a byte count, without allocating.
pub fn byteUnits(value: anytype, base: Base, locale: ?*const Locale) Error![]const u8 {
    const d = try @import("decimal.zig").from(value);
    const l = locale orelse try locales.get("en-US");
    try l.validate();
    const factor: @import("decimal.zig").Wide = if (base == .decimal) 1000 else 1024;
    const integral = try d.integer();
    var divisor: @import("decimal.zig").Wide = 1;
    var power: usize = 0;
    while (power < 8 and integral >= divisor * factor) {
        divisor *= factor;
        power += 1;
    }
    return if (base == .binary) l.binary_suffixes[power] else l.decimal_suffixes[power];
}
/// Reusable configuration. All option slices and custom locales are borrowed.
pub const Formatter = struct {
    options: Options = .{},
    /// Construct a numeric value or validated formatter from the supplied argument; no allocation.
    pub fn init(options: Options) Error!Formatter {
        try options.validate();
        return .{ .options = options };
    }
    /// Allocate formatted UTF-8 output with gpa; the caller frees the returned slice. Errors include OutOfMemory.
    pub fn formatAlloc(self: Formatter, gpa: std.mem.Allocator, value: anytype, options: Options) Error![]u8 {
        return @import("format.zig").formatAlloc(gpa, value, Options.merge(self.options, options));
    }
    /// Format into the caller buffer and return its used slice; report BufferTooSmall on insufficient capacity.
    pub fn formatBuf(self: Formatter, buf: []u8, value: anytype, options: Options) Error![]u8 {
        return @import("format.zig").formatBuf(buf, value, Options.merge(self.options, options));
    }
    /// Write a formatted numeric value to the borrowed writer; propagate validation and WriteFailed errors.
    pub fn formatTo(self: Formatter, w: *std.Io.Writer, value: anytype, options: Options) @import("format.zig").FormatError!void {
        return @import("format.zig").formatTo(w, value, Options.merge(self.options, options));
    }
    /// Resolve a named locale format; return UnknownFormat if the name is absent.
    pub fn named(self: Formatter, name: []const u8) Error!Options {
        const l = self.options.locale orelse try locales.get("en-US");
        return Options.merge(self.options, try l.named(name));
    }
};
test {
    std.testing.refAllDecls(@This());
    _ = @import("tests.zig");
}
