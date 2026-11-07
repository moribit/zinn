//! ELF32 load-segment accounting; metadata, debug sections and file headers are excluded.
const std = @import("std");
pub const Target = struct {
    flash_origin: u32 = 0,
    flash_bytes: u32 = 16384,
    reserved_flash_bytes: u32 = 64,
    ram_origin: u32 = 0x20000000,
    ram_bytes: u32 = 2048,
    stack_bytes: u32 = 512,
    pub fn validate(self: Target) !void {
        if (self.flash_bytes == 0 or self.ram_bytes == 0 or self.reserved_flash_bytes >= self.flash_bytes or self.stack_bytes > self.ram_bytes) return error.InvalidTargetBudget;
        const fe = @as(u64, self.flash_origin) + self.flash_bytes;
        const re = @as(u64, self.ram_origin) + self.ram_bytes;
        if (fe > 0x1_0000_0000 or re > 0x1_0000_0000 or (@as(u64, self.flash_origin) < re and @as(u64, self.ram_origin) < fe)) return error.InvalidTargetBudget;
    }
};
pub const Report = struct {
    flash: u64 = 0,
    static_ram: u64 = 0,
    pub fn check(self: Report, target: Target) !void {
        try target.validate();
        if (self.flash > target.flash_bytes - target.reserved_flash_bytes) return error.FlashBudgetExceeded;
        if (self.static_ram > target.ram_bytes - target.stack_bytes) return error.SramBudgetExceeded;
    }
};
fn read(data: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, data[at..][0..4], .little);
}
pub fn inspect(data: []const u8, target: Target) !Report {
    try target.validate();
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
        const file_offset = read(data, at + 4);
        const virtual = read(data, at + 8);
        const physical = read(data, at + 12);
        const file_size = read(data, at + 16);
        const memory_size = read(data, at + 20);
        const flags = read(data, at + 24);
        const alignment = read(data, at + 28);
        if (file_size > memory_size or @as(u64, file_offset) + file_size > data.len) return error.InvalidSegments;
        if (alignment > 1 and ((alignment & (alignment - 1)) != 0 or virtual % alignment != file_offset % alignment)) return error.InvalidSegmentAlignment;
        if (memory_size == 0) continue;
        load_count += 1;
        const ve = @as(u64, virtual) + memory_size;
        const fe = @as(u64, target.flash_origin) + target.flash_bytes - target.reserved_flash_bytes;
        const re = @as(u64, target.ram_origin) + target.ram_bytes;
        const in_flash = virtual >= target.flash_origin and ve <= fe;
        const in_ram = virtual >= target.ram_origin and ve <= re;
        if (!in_flash and !in_ram) return error.VirtualAddressOutsideMemory;
        if ((flags & 3) == 3 or (in_ram and flags & 1 != 0)) return error.ExecutableWritableSegment;
        if (in_flash and flags & 2 != 0) return error.WritableFlashSegment;
        if (in_flash and (file_size != memory_size or physical != virtual)) return error.InvalidFlashSegment;
        if (file_size > 0) {
            if (physical < target.flash_origin or @as(u64, physical) + file_size > fe) return error.LoadAddressOutsideFlash;
            result.flash = @max(result.flash, @as(u64, physical) - target.flash_origin + file_size);
        } else if (physical != virtual) return error.InvalidZeroFillSegment;
        if (in_ram) result.static_ram = @max(result.static_ram, ve - target.ram_origin);
        for (0..i) |previous| {
            const pa = offset + previous * stride;
            if (read(data, pa) != 1) continue;
            const pv = read(data, pa + 8);
            const pm = read(data, pa + 20);
            const pp = read(data, pa + 12);
            const pf = read(data, pa + 16);
            if (pm > 0 and @as(u64, virtual) < @as(u64, pv) + pm and @as(u64, pv) < ve) return error.OverlappingVirtualSegments;
            if (file_size > 0 and pf > 0 and @as(u64, physical) < @as(u64, pp) + pf and @as(u64, pp) < @as(u64, physical) + file_size) return error.OverlappingLoadSegments;
        }
    }
    if (load_count == 0) return error.NoLoadSegments;
    return result;
}
