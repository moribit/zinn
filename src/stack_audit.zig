//! Optional host analysis of LLVM RV32 disassembly; conservative acyclic call-chain bound.
const std = @import("std");
const Function = struct { name: []const u8, frame: u64 = 0, indirect: bool = false, calls: std.ArrayList([]const u8) = .empty };
fn symbol(line: []const u8) ?[]const u8 {
    const start = std.mem.indexOfScalar(u8, line, '<') orelse return null;
    const end = std.mem.indexOfScalarPos(u8, line, start, '>') orelse return null;
    return line[start + 1 .. end];
}
fn index(functions: []const Function, name: []const u8) ?usize {
    for (functions, 0..) |f, i| if (std.mem.eql(u8, f.name, name)) return i;
    return null;
}
pub fn bound(allocator: std.mem.Allocator, disassembly: []const u8, entry: []const u8) !u64 {
    var functions: std.ArrayList(Function) = .empty;
    defer {
        for (functions.items) |*f| f.calls.deinit(allocator);
        functions.deinit(allocator);
    }
    var current: ?usize = null;
    var lines = std.mem.splitScalar(u8, disassembly, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.endsWith(u8, line, ">:")) {
            const name = symbol(line).?;
            if (std.mem.startsWith(u8, name, ".L")) continue;
            current = functions.items.len;
            try functions.append(allocator, .{ .name = name });
            continue;
        }
        const ci = current orelse continue;
        // llvm-objdump separates address/encoding/mnemonic by whitespace.
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        var words = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
        _ = words.next() orelse continue; // encoded instruction
        const op = words.next() orelse continue;
        const operands = std.mem.trim(u8, words.rest(), " \t");
        const f = &functions.items[ci];
        if (std.mem.startsWith(u8, operands, "sp,")) {
            if (std.mem.eql(u8, op, "addi")) {
                var operands_it = std.mem.splitScalar(u8, operands, ',');
                _ = operands_it.next();
                const source = std.mem.trim(u8, operands_it.next() orelse "", " \t");
                const immediate = std.mem.trim(u8, operands_it.next() orelse "", " \t");
                if (!std.mem.eql(u8, source, "sp")) {
                    f.indirect = true;
                    continue;
                }
                const amount = std.fmt.parseInt(i64, immediate, 0) catch {
                    f.indirect = true;
                    continue;
                };
                if (amount < 0) f.frame += @intCast(-amount);
            } else f.indirect = true;
        }
        if (std.mem.eql(u8, op, "jal") or std.mem.eql(u8, op, "jalr") or std.mem.eql(u8, op, "j") or std.mem.eql(u8, op, "jr") or std.mem.startsWith(u8, op, "b")) {
            if (symbol(line)) |target| {
                var parts = std.mem.splitScalar(u8, target, '+');
                const name = parts.first();
                // Intra-function branches are not recursion. Calls to the entry are.
                if (std.mem.eql(u8, name, f.name) and (std.mem.eql(u8, op, "j") or std.mem.eql(u8, op, "jr") or std.mem.startsWith(u8, op, "b"))) continue;
                try f.calls.append(allocator, name);
            } else if (!std.mem.startsWith(u8, op, "b") and !(std.mem.eql(u8, op, "jr") and std.mem.eql(u8, operands, "ra"))) f.indirect = true;
        } else if (std.mem.eql(u8, op, "jr") and !std.mem.eql(u8, std.mem.trim(u8, operands, " \t"), "ra")) f.indirect = true;
    }
    const start = index(functions.items, entry) orelse return error.StackEntryNotFound;
    const reachable = try allocator.alloc(bool, functions.items.len);
    defer allocator.free(reachable);
    @memset(reachable, false);
    reachable[start] = true;
    for (0..functions.items.len) |_| for (functions.items, 0..) |f, i| {
        if (reachable[i]) for (f.calls.items) |name| {
            const j = index(functions.items, name) orelse return error.UnknownStackCallee;
            reachable[j] = true;
        };
    };
    const known = try allocator.alloc(?u64, functions.items.len);
    defer allocator.free(known);
    @memset(known, null);
    for (0..functions.items.len) |_| {
        var progress = false;
        for (functions.items, 0..) |f, i| {
            if (!reachable[i] or known[i] != null) continue;
            if (f.indirect) {
                if (!@import("builtin").is_test) std.debug.print("stack audit unresolved in {s}\n", .{f.name});
                return error.UnknownDynamicStackOrIndirectCall;
            }
            var maximum: u64 = 0;
            var ready = true;
            for (f.calls.items) |name| {
                const j = index(functions.items, name).?;
                if (known[j]) |size| maximum = @max(maximum, size) else ready = false;
            }
            if (ready) {
                known[i] = f.frame + maximum;
                progress = true;
            }
        }
        if (known[start]) |size| return size;
        if (!progress) break;
    }
    return error.RecursiveOrUnknownStackBound;
}
test "static stack includes nested callees and excludes unreachable interrupts" {
    const text = "0 <entry>:\n 0: 1171 addi sp, sp, -4\n 2: 000000ef jal 8 <child>\n 4: 8082 ret\n8 <child>:\n 8: 1101 addi sp, sp, -32\n a: 8082 ret\n10 <irq>:\n 10: 9782 jalr a5\n";
    try std.testing.expectEqual(@as(u64, 36), try bound(std.testing.allocator, text, "entry"));
    try std.testing.expectError(error.UnknownDynamicStackOrIndirectCall, bound(std.testing.allocator, text, "irq"));
    try std.testing.expectError(error.RecursiveOrUnknownStackBound, bound(std.testing.allocator, "0 <entry>:\n0: 000000ef jal 0 <entry>\n", "entry"));
}
