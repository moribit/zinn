//! Scale = multiplier / 2^shift. Round nearest, ties away from zero.
pub const Params = struct {
    multiplier: u16 = 1,
    shift: u5 = 0,
    input_zero: i8 = 0,
    output_zero: i8 = 0,
    /// Optional compile-time real-value metadata. All three or none.
    input_scale: ?f32 = null,
    weight_scale: ?f32 = null,
    output_scale: ?f32 = null,
    pub fn validate(comptime self: Params) void {
        const std = @import("std");
        const scales = .{ self.input_scale, self.weight_scale, self.output_scale };
        if (self.input_scale != null or self.weight_scale != null or self.output_scale != null) {
            inline for (scales) |scale| {
                const value = scale orelse @compileError("quantization scales must be specified together");
                if (!std.math.isFinite(value) or value <= 0) @compileError("quantization scale must be finite and positive");
            }
            const ratio = @as(f64, self.input_scale.?) * self.weight_scale.? / self.output_scale.?;
            const actual = @as(f64, @floatFromInt(self.multiplier)) / @as(f64, @floatFromInt(@as(u64, 1) << self.shift));
            if (@abs(actual - ratio) > ratio * 0.0001) @compileError("requantization coefficient disagrees with scales");
        }
        if (self.multiplier == 0) @compileError("quantization multiplier must be positive");
    }
};
pub fn requantize(value: i32, p: Params) i8 {
    const product = @as(i64, value) * p.multiplier;
    const magnitude: i64 = if (product < 0) -product else product;
    const half: i64 = if (p.shift == 0) 0 else @as(i64, 1) << (p.shift - 1);
    const rounded = (magnitude + half) >> p.shift;
    const signed = (if (product < 0) -rounded else rounded) + p.output_zero;
    return @intCast(@max(-128, @min(127, signed)));
}
pub fn relu(value: i8, zero: i8) i8 {
    return @max(value, zero);
}
