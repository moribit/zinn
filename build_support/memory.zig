const std = @import("std");
const progress = @import("progress.zig");
pub const Options = struct {
    name: []const u8,
    elf: std.Build.LazyPath,
    flash_origin: u32 = 0,
    ram_origin: u32 = 0x20000000,
    target_name: []const u8 = "CH32V003",
    flash_bytes: u32 = 16384,
    ram_bytes: u32 = 2048,
    stack_bytes: u32 = 512,
    isr_bytes: u32 = 0,
    reserved_flash_bytes: u32 = 64,
    progress: progress.Mode = .auto,
};
pub const Check = struct { step: *std.Build.Step, run: *std.Build.Step.Run, json: std.Build.LazyPath, text: std.Build.LazyPath };
pub fn addMemoryCheck(b: *std.Build, dependency: ?*std.Build.Dependency, options: Options) Check {
    const pkg = if (dependency) |d| d.builder else b;
    const size_tool = b.addExecutable(.{ .name = b.fmt("{s}-size", .{options.name}), .root_module = b.createModule(.{ .root_source_file = pkg.path("tools/size.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "budget", .module = b.createModule(.{ .root_source_file = pkg.path("src/budget.zig"), .target = b.graph.host, .optimize = .safe }) }} }) });
    const size = b.addRunArtifact(size_tool);
    size_tool.root_module.addImport("progress", b.createModule(.{ .root_source_file = pkg.path("src/host/progress.zig"), .target = b.graph.host, .optimize = .safe }));
    progress.configure(size, options.progress, b.fmt("Zinn: memory budget verification {s}", .{options.name}));
    size.addFileArg(options.elf);
    size.addArgs(&.{ b.fmt("{d}", .{options.flash_bytes}), b.fmt("{d}", .{options.ram_bytes}), b.fmt("{d}", .{std.math.add(u32, options.stack_bytes, options.isr_bytes) catch @panic("stack plus ISR allowance overflow")}), b.fmt("{d}", .{options.reserved_flash_bytes}) });
    if (options.flash_origin != 0 or options.ram_origin != 0x20000000 or !std.mem.eql(u8, options.target_name, "CH32V003"))
        size.addArgs(&.{ b.fmt("{d}", .{options.flash_origin}), b.fmt("{d}", .{options.ram_origin}), options.target_name });
    const size_json = size.captureStdOut(.{});
    const size_text = size.captureStdErr(.{});
    const check = b.step(b.fmt("{s}-memory", .{options.name}), "Check caller final ELF, including all statics and stack/ISR allowance");
    check.dependOn(&b.addInstallFile(size_json, b.fmt("reports/{s}-memory.json", .{options.name})).step);
    check.dependOn(&b.addInstallFile(size_text, b.fmt("reports/{s}-memory.txt", .{options.name})).step);
    return .{ .step = check, .run = size, .json = size_json, .text = size_text };
}
