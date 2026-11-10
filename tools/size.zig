const std = @import("std");
const budget = @import("budget");
const progress = @import("progress");
pub fn main(init: std.process.Init) !void {
    const parsed = try progress.cli(init);
    const args = parsed.args;
    var renderer = progress.Renderer.initJournalToken(init, parsed.mode, parsed.journal, parsed.token);
    defer renderer.deinit();
    var task = renderer.observer().task("Memory budget verification", null);
    errdefer task.fail("ELF memory verification failed");
    if (args.len != 2 and args.len != 6) return error.ExpectedElfAndOptionalFlashRamStackReserved;
    var target: budget.Target = .{};
    if (args.len == 6) {
        target.flash_bytes = try std.fmt.parseInt(u32, args[2], 10);
        target.ram_bytes = try std.fmt.parseInt(u32, args[3], 10);
        target.stack_bytes = try std.fmt.parseInt(u32, args[4], 10);
        target.reserved_flash_bytes = try std.fmt.parseInt(u32, args[5], 10);
    }
    const data = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.arena.allocator(), .limited(16 * 1024 * 1024));
    const report = try budget.inspect(data, target);
    std.debug.print("{s}: Flash={d} B / {d} B (reserved={d}); static SRAM={d} B + stack allowance={d} B / {d} B\n", .{ args[1], report.flash, target.flash_bytes, target.reserved_flash_bytes, report.static_ram, target.stack_bytes, target.ram_bytes });
    report.check(target) catch |err| {
        std.debug.print("target memory check FAILED: {s}; reduce model/workspace/logging or choose a matching target budget\n", .{@errorName(err)});
        return err;
    };
    const json = try std.json.Stringify.valueAlloc(init.arena.allocator(), .{
        .schema_version = @as(u32, 1),
        .artifact = std.fs.path.basename(args[1]),
        .flash_bytes = report.flash,
        .static_ram_bytes = report.static_ram,
        .stack_allowance_bytes = target.stack_bytes,
        .ram_margin_bytes = target.ram_bytes - report.static_ram - target.stack_bytes,
        .flash_limit_bytes = target.flash_bytes - target.reserved_flash_bytes,
        .ram_limit_bytes = target.ram_bytes,
        .hardware_measured = false,
    }, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, json);
    task.finish();
    try progress.writeSummary(init, parsed, .{ .kind = .deploy, .target = "CH32V003", .flash = report.flash, .flash_limit = target.flash_bytes - target.reserved_flash_bytes, .static_ram = report.static_ram, .stack_allowance = target.stack_bytes, .ram_margin = target.ram_bytes - report.static_ram - target.stack_bytes });
    try progress.saveReceipt(init, parsed);
}
