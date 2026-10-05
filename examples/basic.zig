const std = @import("std");
const numeral = @import("numeral");
pub fn main(init: std.process.Init) !void {
    var buf: [256]u8 = undefined;
    const number = try numeral.formatBuf(&buf, 1234567, numeral.pattern("0,0.00"));
    try std.Io.File.stdout().writeStreamingAll(init.io, number);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
    const money = try numeral.formatAlloc(init.gpa, try numeral.Decimal.parse("1234.50"), .{ .output = .currency, .mantissa = 2, .thousand_separated = true, .locale = try numeral.locales.get("es-CL") });
    defer init.gpa.free(money);
    try std.Io.File.stdout().writeStreamingAll(init.io, money);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
    const legacy = try numeral.compat.formatAlloc(init.gpa, 0.974878234, numeral.pattern("0.000%"));
    defer init.gpa.free(legacy);
    try std.Io.File.stdout().writeStreamingAll(init.io, legacy);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
    _ = try numeral.unformat("1.234,50", .{ .locale = try numeral.locales.get("es-CL") });
    var writer = std.Io.Writer.fixed(&buf);
    try numeral.formatTo(&writer, std.math.maxInt(u128), .{});
    const formatter = try numeral.Formatter.init(.{ .locale = try numeral.locales.get("fr-FR") });
    _ = try formatter.formatBuf(&buf, 1234.5, try formatter.named("fullWithTwoDecimals"));
}
