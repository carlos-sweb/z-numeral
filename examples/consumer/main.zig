const std = @import("std");
const numeral = @import("numeral");

pub fn main(init: std.process.Init) !void {
    var buffer: [128]u8 = undefined;
    const result = try numeral.formatBuf(&buffer, 1234567, numeral.pattern("0,0.00"));
    try std.Io.File.stdout().writeStreamingAll(init.io, result);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
