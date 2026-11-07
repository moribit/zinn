const std = @import("std");
const audit = @import("stack_audit");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) return error.ExpectedDisassemblyEntryAllowance;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.arena.allocator(), .limited(16 * 1024 * 1024));
    const upper = try audit.bound(init.arena.allocator(), bytes, args[2]);
    const allowance = try std.fmt.parseInt(u64, args[3], 10);
    std.debug.print("static normal-path stack upper={d}B allowance={d}B (IRQs excluded; not a high-water measurement)\n", .{ upper, allowance });
    if (upper > allowance) return error.StaticStackAllowanceExceeded;
}
