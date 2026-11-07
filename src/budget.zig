//! ELF32 load-segment accounting; metadata, debug sections and file headers are excluded.
const std = @import("std");
pub const Target = struct {
    flash_origin: u32 = 0,
    flash_bytes: u32 = 16384,
    reserved_flash_bytes: u32 = 64,
    ram_origin: u32 = 0x20000000,
    ram_bytes: u32 = 2048,
    stack_bytes: u32 = 512,
};
pub const Report = struct {
    flash: u64 = 0,
    static_ram: u64 = 0,
    pub fn check(self: Report, target: Target) !void {
        if (target.reserved_flash_bytes > target.flash_bytes or target.stack_bytes > target.ram_bytes) return error.InvalidTargetBudget;
        if (self.flash > target.flash_bytes - target.reserved_flash_bytes) return error.FlashBudgetExceeded;
        if (self.static_ram > target.ram_bytes - target.stack_bytes) return error.SramBudgetExceeded;
    }
};
fn read(data: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, data[at..][0..4], .little);
}
pub fn inspect(data: []const u8, target: Target) !Report {
    if (data.len < 52 or !std.mem.eql(u8, data[0..6], "\x7fELF\x01\x01")) return error.ExpectedElf32LittleEndian;
    const offset = read(data, 28);
    const stride = std.mem.readInt(u16, data[42..44], .little);
    const count = std.mem.readInt(u16, data[44..46], .little);
    if (stride < 32 or count == 0 or @as(u64, offset) + @as(u64, stride) * count > data.len) return error.InvalidSegments;
    var result: Report = .{};
    var load_count: usize = 0;
    for (0..count) |i| {
        const at = offset + i * stride;
        if (read(data, at) != 1) continue; // PT_LOAD
        load_count += 1;
        const file_offset = read(data, at + 4);
        const virtual = read(data, at + 8);
        const physical = read(data, at + 12);
        const file_size = read(data, at + 16);
        const memory_size = read(data, at + 20);
        if (file_size > memory_size or @as(u64, file_offset) + file_size > data.len) return error.InvalidSegments;
        if (file_size > 0) {
            if (physical < target.flash_origin or physical >= @as(u64, target.flash_origin) + target.flash_bytes) return error.LoadAddressOutsideFlash;
            result.flash = @max(result.flash, @as(u64, physical) - target.flash_origin + file_size);
        }
        if (memory_size > 0 and virtual >= target.ram_origin and virtual < @as(u64, target.ram_origin) + target.ram_bytes) {
            result.static_ram = @max(result.static_ram, @as(u64, virtual) - target.ram_origin + memory_size);
        } else if (memory_size > 0 and (virtual < target.flash_origin or virtual >= @as(u64, target.flash_origin) + target.flash_bytes)) return error.VirtualAddressOutsideMemory;
    }
    if (load_count == 0) return error.NoLoadSegments;
    return result;
}
