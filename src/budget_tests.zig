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

fn fixture() [512]u8 {
    var elf: [512]u8 = @splat(0);
    @memcpy(elf[0..6], "\x7fELF\x01\x01");
    std.mem.writeInt(u32, elf[28..32], 52, .little);
    std.mem.writeInt(u16, elf[42..44], 32, .little);
    std.mem.writeInt(u16, elf[44..46], 1, .little);
    set(&elf, 0, 0, 1);
    set(&elf, 0, 4, 256);
    set(&elf, 0, 8, 0);
    set(&elf, 0, 12, 0);
    set(&elf, 0, 16, 16);
    set(&elf, 0, 20, 16);
    set(&elf, 0, 24, 5);
    return elf;
}
fn set(bytes: []u8, segment: usize, field: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[52 + segment * 32 + field ..][0..4], value, .little);
}
test "ELF rejects full-span boundary crossings, reservations and executable RAM" {
    var elf = fixture();
    set(&elf, 0, 8, 16312);
    set(&elf, 0, 12, 16312);
    try std.testing.expectError(error.VirtualAddressOutsideMemory, b.inspect(&elf, .{}));
    elf = fixture();
    set(&elf, 0, 8, 0x200007f8);
    set(&elf, 0, 24, 6);
    try std.testing.expectError(error.VirtualAddressOutsideMemory, b.inspect(&elf, .{}));
    elf = fixture();
    set(&elf, 0, 8, 0x20000000);
    set(&elf, 0, 12, 16312);
    set(&elf, 0, 24, 6);
    try std.testing.expectError(error.LoadAddressOutsideFlash, b.inspect(&elf, .{}));
    elf = fixture();
    set(&elf, 0, 8, 0x20000000);
    try std.testing.expectError(error.ExecutableWritableSegment, b.inspect(&elf, .{}));
    elf = fixture();
    set(&elf, 0, 20, 32);
    try std.testing.expectError(error.InvalidFlashSegment, b.inspect(&elf, .{}));
    elf = fixture();
    set(&elf, 0, 28, 3);
    try std.testing.expectError(error.InvalidSegmentAlignment, b.inspect(&elf, .{}));
    try std.testing.expectError(error.InvalidTargetBudget, b.inspect(&elf, .{ .flash_origin = 0xfffffff0 }));
    try std.testing.expectError(error.InvalidTargetBudget, b.inspect(&elf, .{ .ram_origin = 100 }));
}
test "ELF rejects virtual and physical aliases, and zero-fill LMA outside RAM" {
    var elf = fixture();
    std.mem.writeInt(u16, elf[44..46], 2, .little);
    for (0..8) |i| set(&elf, 1, i * 4, std.mem.readInt(u32, elf[52 + i * 4 ..][0..4], .little));
    try std.testing.expectError(error.OverlappingVirtualSegments, b.inspect(&elf, .{}));
    set(&elf, 1, 8, 0x20000000);
    set(&elf, 1, 24, 6);
    try std.testing.expectError(error.OverlappingLoadSegments, b.inspect(&elf, .{}));
    set(&elf, 1, 16, 0);
    try std.testing.expectError(error.InvalidZeroFillSegment, b.inspect(&elf, .{}));
}

test "ELF Flash cannot be writable even without execute permission" {
    var elf = fixture();
    set(&elf, 0, 24, 6);
    try std.testing.expectError(error.WritableFlashSegment, b.inspect(&elf, .{}));
}
