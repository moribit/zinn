const std = @import("std");
const b = @import("budget.zig");
test "target budgets include stack and Flash reservation and reject exceeded limits" {
    try (b.Report{ .flash = 16320, .static_ram = 1536 }).check(.{});
    try std.testing.expectError(error.FlashBudgetExceeded, (b.Report{ .flash = 16321 }).check(.{}));
    try std.testing.expectError(error.SramBudgetExceeded, (b.Report{ .static_ram = 1537 }).check(.{}));
    try std.testing.expectError(error.InvalidTargetBudget, (b.Report{}).check(.{ .ram_bytes = 128 }));
    try (b.Report{ .flash = 17000, .static_ram = 4000 }).check(.{ .flash_bytes = 32768, .ram_bytes = 8192 });
    try std.testing.expectError(error.ExpectedElf32LittleEndian, b.inspect("bad", .{}));
}
test "ELF accounting includes Flash LMA and RAM gaps, rejects malformed segment" {
    var elf: [256]u8 = @splat(0);
    @memcpy(elf[0..6], "\x7fELF\x01\x01");
    std.mem.writeInt(u32, elf[28..32], 52, .little);
    std.mem.writeInt(u16, elf[42..44], 32, .little);
    std.mem.writeInt(u16, elf[44..46], 1, .little);
    std.mem.writeInt(u32, elf[52..56], 1, .little);
    std.mem.writeInt(u32, elf[56..60], 128, .little);
    std.mem.writeInt(u32, elf[60..64], 0x20000010, .little);
    std.mem.writeInt(u32, elf[64..68], 100, .little);
    std.mem.writeInt(u32, elf[68..72], 4, .little);
    std.mem.writeInt(u32, elf[72..76], 12, .little);
    const r = try b.inspect(&elf, .{});
    try std.testing.expectEqual(@as(u64, 104), r.flash);
    try std.testing.expectEqual(@as(u64, 28), r.static_ram);
    std.mem.writeInt(u32, elf[68..72], 1000, .little);
    try std.testing.expectError(error.InvalidSegments, b.inspect(&elf, .{}));
}
