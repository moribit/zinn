const std = @import("std");
fn u16le(data: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .little);
}
fn u32le(data: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, data[offset..][0..4], .little);
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedElf;
    const data = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.arena.allocator(), .limited(1024 * 1024));
    if (data.len < 52 or !std.mem.eql(u8, data[0..6], "\x7fELF\x01\x01")) return error.ExpectedElf32LittleEndian;
    const offset = u32le(data, 32);
    const stride = u16le(data, 46);
    const count = u16le(data, 48);
    if (stride < 40 or @as(u64, offset) + @as(u64, stride) * count > data.len) return error.InvalidSections;
    var flash: u32 = 0;
    var ram: u32 = 0;
    for (0..count) |i| {
        const at = offset + i * stride;
        if (u32le(data, at + 8) & 2 == 0) continue; // SHF_ALLOC
        const address = u32le(data, at + 12);
        const size = u32le(data, at + 20);
        if (address >= 0x20000000 and address < 0x20000800) ram += size;
        if (u32le(data, at + 4) != 8) flash += size; // NOBITS has no Flash payload
    }
    const stack_budget = 512;
    std.debug.print("Flash={d}/16320 B (+64 B reserved); static RAM={d} B; stack allowance={d} B; SRAM budget={d}/2048 B\n", .{ flash, ram, stack_budget, ram + stack_budget });
    std.debug.print("Baseline delta: Flash={d} B; static RAM={d} B\n", .{ @as(i64, flash) - 3172, @as(i64, ram) - 12 });
    if (flash > 16320 or ram + stack_budget > 2048) return error.MemoryBudgetExceeded;
}
