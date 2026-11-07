//! Scale = multiplier / 2^shift. Round nearest, ties away from zero.
pub const Params = struct {
    multiplier: u16 = 1,
    shift: u5 = 0,
    input_zero: i8 = 0,
    output_zero: i8 = 0,
    pub fn validate(comptime self: Params) void {
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
