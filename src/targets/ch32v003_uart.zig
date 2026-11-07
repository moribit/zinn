//! Board-specific polling UART adapter. Upstream HAL remains unmodified.
const fun = @import("ch32fun");
pub const clock_hz = 48_000_000;
extern var _ebss: u8;
extern var _stack_top: u8;
var painted_end: usize = 0;
pub fn now() u32 {
    return fun.time.nowCycles();
}
pub fn init() u32 {
    fun.system.init(.{});
    const start = now();
    fun.uart.init(115200);
    fun.gpio.pin(.D, 6).configure(.input_floating);
    fun.registers.usart1().CTLR1 |= fun.registers.USART_CTLR1_RE;
    return now() -% start;
}
pub fn read() union(enum) { none, byte: u8, failure } {
    const u = fun.registers.usart1();
    const status = u.STATR;
    if (status & 0x0f != 0) {
        _ = u.DATAR;
        return .failure;
    }
    if (status & (1 << 5) == 0) return .none;
    return .{ .byte = @truncate(u.DATAR) };
}
pub fn write(bytes: []const u8) bool {
    const u = fun.registers.usart1();
    for (bytes) |byte| {
        const start = now();
        while (u.STATR & fun.registers.USART_STATR_TXE == 0) {
            if (now() -% start >= clock_hz / 10) return false;
        }
        u.DATAR = byte;
    }
    return true;
}
/// Paint only currently unused RAM; protect setup frames by 64 bytes.
/// The result is a conservative since-ready watermark, not startup peak usage.
pub inline fn paintStack() void {
    const sp = asm volatile ("mv %[result], sp"
        : [result] "=r" (-> usize),
    );
    const bottom = @intFromPtr(&_ebss);
    const top = @intFromPtr(&_stack_top);
    if (sp <= bottom + 64 or sp > top) return;
    painted_end = sp - 64;
    var p: [*]volatile u8 = @ptrFromInt(bottom);
    while (@intFromPtr(p) < painted_end) : (p += 1) p[0] = 0xa5;
}
pub fn highWater() u16 {
    if (painted_end == 0) return 0xffff;
    var address = @intFromPtr(&_ebss);
    while (address < painted_end and @as(*volatile u8, @ptrFromInt(address)).* == 0xa5) : (address += 1) {}
    return @intCast(@intFromPtr(&_stack_top) - address);
}
