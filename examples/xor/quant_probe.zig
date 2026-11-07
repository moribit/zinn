//! Diagnostic only. Cycle values require actual CH32V003 execution.
const z = @import("zinn");
const fun = @import("ch32fun");
var value: i32 = -123456;
var multiplier: u16 = 34567;
var shift: u5 = 27;
noinline fn requantize(input: i32, m: u16, s: u5) i8 {
    return z.quant.requantize(input, .{ .multiplier = m, .shift = s });
}
noinline fn saturate(input: i32) i8 {
    return @intCast(@max(-128, @min(127, input)));
}
pub fn run() void {
    const iterations = 64;
    var checksum: i32 = 0;
    const start = fun.time.nowCycles();
    asm volatile ("" ::: .{ .memory = true });
    for (0..iterations) |_| {
        const v: *volatile i32 = &value;
        const m: *volatile u16 = &multiplier;
        const s: *volatile u5 = &shift;
        checksum += requantize(v.*, m.*, s.*);
    }
    asm volatile ("" ::: .{ .memory = true });
    const elapsed = fun.time.nowCycles() -% start;
    fun.swio_log.info("requant i64: n={d} raw_cycles={d} checksum={d} expected=-2048", .{ iterations, elapsed, checksum });
    checksum = 0;
    const baseline = fun.time.nowCycles();
    asm volatile ("" ::: .{ .memory = true });
    for (0..iterations) |_| {
        const v: *volatile i32 = &value;
        checksum += saturate(v.*);
    }
    asm volatile ("" ::: .{ .memory = true });
    const baseline_elapsed = fun.time.nowCycles() -% baseline;
    fun.swio_log.info("saturate i32: n={d} raw_cycles={d} checksum={d} expected=-8192", .{ iterations, baseline_elapsed, checksum });
}
