const std = @import("std");
pub const Mode = enum { auto, plain, off };
pub fn configure(run: *std.Build.Step.Run, mode: Mode, name: []const u8) void {
    run.setEnvironmentVariable("ZINN_PROGRESS", @tagName(mode));
    if (mode != .auto) run.disable_zig_progress = true;
    run.rename_step_with_output_arg = false;
    run.step.name = name;
}
