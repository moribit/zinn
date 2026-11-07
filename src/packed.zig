pub const Format = enum { int8, int4 };
pub fn get(comptime format: Format, weights: []const i8, bytes: []const u8, index: usize) i8 {
    if (format == .int8) return weights[index];
    const nibble: u8 = (bytes[index / 2] >> @as(u3, @intCast((index % 2) * 4))) & 15;
    return @intCast(if (nibble >= 8) @as(i16, nibble) - 16 else @as(i16, nibble));
}
pub fn validate(comptime format: Format, comptime count: usize, comptime weights: []const i8, comptime bytes: []const u8) void {
    if (format == .int8) {
        if (weights.len != count or bytes.len != 0) @compileError("weight shape mismatch for int8");
    } else {
        if (weights.len != 0 or bytes.len != (count + 1) / 2) @compileError("packed int4 weight shape mismatch");
        if (count % 2 != 0 and bytes[bytes.len - 1] & 240 != 0) @compileError("unused int4 high nibble must be zero");
    }
}
pub fn encode(values: []const i8, bytes: []u8) !void {
    if (bytes.len != (values.len + 1) / 2) return error.PackedShapeMismatch;
    for (values) |v| if (v < -8 or v > 7) return error.Int4OutOfRange;
    @memset(bytes, 0);
    for (values, 0..) |v, i| bytes[i / 2] |= (@as(u8, @bitCast(v)) & 15) << @as(u3, @intCast((i % 2) * 4));
}
