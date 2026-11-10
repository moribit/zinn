//! Explicit build_file keeps presenter child builds on this custom entry point.
const std = @import("std");
pub fn build(b: *std.Build) void {
    @import("build.zig").configure(b, b.path("custom.build.zig"));
}
