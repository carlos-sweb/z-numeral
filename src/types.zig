const std = @import("std");
pub const Error = error{ InvalidPattern, InvalidOptions, UnknownLocale, InvalidNumber, InvalidUtf8, InvalidGrouping, PrecisionOutOfRange, Overflow, DivisionByZero, NonFinite, MixedNumericTypes, UnknownFormat, BufferTooSmall, OutOfMemory };
pub const Output = enum { number, currency, percent, byte, time, ordinal };
pub const Base = enum { binary, decimal, general };
pub const Position = enum { prefix, infix, postfix };
pub const Negative = enum { sign, parenthesis };
pub const Average = enum { thousand, million, billion, trillion };
pub const Rounding = enum { half_even, half_away, trunc, floor, ceil, js };
pub const Abbreviations = struct {
    thousand: []const u8 = "k",
    million: []const u8 = "m",
    billion: []const u8 = "b",
    trillion: []const u8 = "t",
    /// Return a borrowed abbreviation by scale index (thousand through trillion).
    pub fn at(self: @This(), i: usize) []const u8 {
        return switch (i) {
            0 => self.thousand,
            1 => self.million,
            2 => self.billion,
            else => self.trillion,
        };
    }
};
/// Partial options. Null means inherit; explicit false/zero overrides defaults.
/// All slices and locale pointers are borrowed for the duration of a call.
pub const Options = struct {
    output: ?Output = null,
    base: ?Base = null,
    characteristic: ?u16 = null,
    prefix: ?[]const u8 = null,
    postfix: ?[]const u8 = null,
    force_average: ?Average = null,
    average: ?bool = null,
    currency_position: ?Position = null,
    currency_symbol: ?[]const u8 = null,
    total_length: ?u16 = null,
    mantissa: ?i16 = null,
    optional_mantissa: ?bool = null,
    trim_mantissa: ?bool = null,
    optional_characteristic: ?bool = null,
    thousand_separated: ?bool = null,
    abbreviations: ?Abbreviations = null,
    negative: ?Negative = null,
    force_sign: ?bool = null,
    space_separated: ?bool = null,
    space_separated_currency: ?bool = null,
    space_separated_abbreviation: ?bool = null,
    exponential: ?bool = null,
    prefix_symbol: ?bool = null,
    low_precision: ?bool = null,
    rounding: ?Rounding = null,
    /// Compatibility callback, receiving the scaled f64 just as Math.round does.
    rounding_function: ?*const fn (f64) f64 = null,
    locale: ?*const Locale = null,
    zero_format: ?[]const u8 = null,
    /// Overlay non-null fields on base options, preserving explicit false, zero and empty strings.
    pub fn merge(base: Options, overlay: Options) Options {
        var result = base;
        inline for (@typeInfo(Options).@"struct".fields) |field| {
            if (@field(overlay, field.name)) |v| @field(result, field.name) = v;
        }
        return result;
    }
    /// Check options or input for validity without allocating; see the signature for error vs boolean result.
    pub fn validate(self: Options) Error!void {
        if (self.mantissa) |m| {
            if (m < -1 or m > 38) return error.PrecisionOutOfRange;
        }
        if ((self.characteristic orelse 0) > 400 or (self.total_length orelse 0) > 38) return error.PrecisionOutOfRange;
        inline for (.{ "prefix", "postfix", "currency_symbol", "zero_format" }) |f| {
            if (@field(self, f)) |s| if (!std.unicode.utf8ValidateSlice(s)) return error.InvalidUtf8;
        }
        if (self.abbreviations) |a| for (0..4) |i| {
            if (!std.unicode.utf8ValidateSlice(a.at(i))) return error.InvalidUtf8;
        };
        if ((self.total_length orelse 0) > 0 and (self.exponential orelse false)) return error.InvalidOptions;
        if (self.base != null and self.output != null and self.output != .byte) return error.InvalidOptions;
        if (self.prefix_symbol != null and self.output != null and self.output != .percent) return error.InvalidOptions;
        if (self.locale) |l| try l.validate();
    }
};
pub const NamedFormat = struct { name: []const u8, options: Options };
pub const OrdinalRule = enum { constant, english, spanish, french, dutch, turkish };
pub const Locale = struct {
    tag: []const u8,
    thousands: []const u8 = ",",
    decimal: []const u8 = ".",
    thousands_size: u8 = 3,
    abbreviations: Abbreviations = .{},
    currency_symbol: []const u8 = "$",
    currency_code: []const u8 = "USD",
    currency_position: Position = .prefix,
    defaults: Options = .{},
    currency_format: Options = .{},
    ordinal_format: Options = .{},
    byte_format: Options = .{},
    percentage_format: Options = .{},
    time_format: Options = .{},
    formats: []const NamedFormat = &.{},
    binary_suffixes: [9][]const u8 = .{ "B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB" },
    decimal_suffixes: [9][]const u8 = .{ "B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB" },
    ordinal_rule: OrdinalRule = .english,
    ordinal_constant: []const u8 = "",
    /// Optional floating-point callback. Exact mode prefers ordinal_exact_fn,
    /// then falls back to this explicitly floating-point callback.
    ordinal_fn: ?*const fn (f64) []const u8 = null,
    /// Optional callback preserving the full fixed-scale decimal in exact mode.
    ordinal_exact_fn: ?*const fn (@import("decimal.zig").Decimal) []const u8 = null,
    /// Check options or input for validity without allocating; see the signature for error vs boolean result.
    pub fn validate(self: *const Locale) Error!void {
        if (self.thousands_size == 0 or self.thousands_size > 38 or self.decimal.len == 0 or std.mem.eql(u8, self.thousands, self.decimal)) return error.InvalidOptions;
        for ([_][]const u8{ self.tag, self.thousands, self.decimal, self.currency_symbol, self.currency_code, self.ordinal_constant, self.abbreviations.thousand, self.abbreviations.million, self.abbreviations.billion, self.abbreviations.trillion }) |s| if (!std.unicode.utf8ValidateSlice(s)) return error.InvalidUtf8;
        for (self.binary_suffixes) |s| if (!std.unicode.utf8ValidateSlice(s)) return error.InvalidUtf8;
        for (self.decimal_suffixes) |s| if (!std.unicode.utf8ValidateSlice(s)) return error.InvalidUtf8;
    }
    /// Return a borrowed locale ordinal suffix for the supplied f64.
    pub fn ordinal(self: *const Locale, n: f64) []const u8 {
        if (self.ordinal_fn) |f| return f(n);
        const b = @rem(n, 10.0);
        const rem = @rem(n, 100.0);
        return switch (self.ordinal_rule) {
            .constant => self.ordinal_constant,
            .english => if (@trunc(rem / 10) == 1) "th" else if (b == 1) "st" else if (b == 2) "nd" else if (b == 3) "rd" else "th",
            .spanish => if (b == 1 or b == 3) "er" else if (b == 2) "do" else if (b == 7 or b == 0) "mo" else if (b == 8) "vo" else if (b == 9) "no" else "to",
            .french => if (n == 1) "er" else "ème",
            .dutch => if ((n != 0 and rem <= 1) or rem == 8 or rem >= 20) "ste" else "de",
            .turkish => turkish(n),
        };
    }
    /// Resolve a named locale format; return UnknownFormat if the name is absent.
    pub fn named(self: *const Locale, name: []const u8) Error!Options {
        for (self.formats) |f| if (std.mem.eql(u8, f.name, name)) return f.options;
        return error.UnknownFormat;
    }
};
fn turkish(n: f64) []const u8 {
    if (n == 0) return "'ıncı";
    const a = @rem(n, 10.0);
    const b = @rem(n, 100.0) - a;
    if (a == 1 or a == 5 or a == 8) return "'inci";
    if (a == 2 or a == 7) return "'nci";
    if (a == 3 or a == 4) return "'üncü";
    if (a == 6) return "'ncı";
    if (a == 9 or b == 10 or b == 30) return "'uncu";
    if (b == 20 or b == 50) return "'nci";
    if (b == 40 or b == 60 or b == 90) return "'ıncı";
    if (b == 70 or b == 80) return "'inci";
    return if (n >= 100) "'üncü" else "";
}
