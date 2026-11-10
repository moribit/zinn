//! One bounded physical line: no cursor hiding, alternate screen or raw mode.
const std = @import("std");
pub fn supported(term: []const u8, ci: bool, tty: bool) bool {
    if (ci or !tty) return false;
    for ([_][]const u8{ "xterm", "screen", "tmux", "vt100", "linux", "ansi", "rxvt" }) |prefix| if (std.mem.startsWith(u8, term, prefix)) return true;
    return false;
}
pub fn columns(io: std.Io, fallback: usize) usize {
    return fileColumns(io, .stderr(), fallback);
}
fn fileColumns(_: std.Io, file: std.Io.File, fallback: usize) usize {
    if (@import("builtin").os.tag != .windows) {
        var size: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        // This terminal query is an immediate, nonblocking standard-library
        // system call; it does not participate in the output relay's I/O work.
        const result = std.posix.system.ioctl(file.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&size));
        // The provider writes through an opaque ioctl argument. Read back the
        // device-owned result from memory rather than retaining an initializer.
        const cols = @as(*volatile std.posix.winsize, &size).col;
        if (result == 0 and cols > 1) return @min(160, cols - 1);
    }
    return @max(1, @min(160, fallback));
}
pub const Line = struct {
    io: std.Io,
    enabled: bool,
    fallback: usize = 78,
    active: bool = false,
    previous_width: usize = 0,
    previous_length: usize = 0,
    size_file: ?std.Io.File = null,
    pub fn init(process: std.process.Init, auto: bool) Line {
        var self: Line = .{ .io = process.io, .enabled = auto and supported(process.environ_map.get("TERM") orelse "dumb", process.environ_map.get("CI") != null, std.Io.File.stderr().isTty(process.io) catch false), .fallback = std.fmt.parseInt(usize, process.environ_map.get("COLUMNS") orelse "78", 10) catch 78 };
        // Retain the actual stderr terminal, not /dev/tty (which may refer to
        // an outer terminal under a PTY relay such as `script`).
        if (self.enabled) self.size_file = std.Io.Dir.cwd().openFile(process.io, "/dev/fd/2", .{}) catch null;
        self.enabled = self.enabled and self.size_file != null;
        return self;
    }
    pub fn width(self: *const Line) usize {
        return fileColumns(self.io, self.size_file orelse .stderr(), if (self.active) self.previous_width else self.fallback);
    }
    pub fn draw(self: *Line, text: []const u8) void {
        self.drawWidth(text, self.width());
    }
    /// Format and draw against one size snapshot, even if the terminal changes
    /// between operations or a subsequent device query temporarily fails.
    pub fn drawWidth(self: *Line, text: []const u8, current_width: usize) void {
        if (!self.enabled) return;
        const file = std.Io.File.stderr();
        // Reflow can turn our one previous line into multiple physical rows.
        // Clear only those owned rows, keeping persistent model/file headers.
        if (self.active and current_width < self.previous_width) {
            for (0..((self.previous_length -| 1) / (current_width + 1))) |_| file.writeStreamingAll(self.io, "\r\x1b[2K\x1b[1A") catch return;
        }
        file.writeStreamingAll(self.io, "\r\x1b[2K") catch return;
        const length = @min(text.len, current_width);
        file.writeStreamingAll(self.io, text[0..length]) catch return;
        self.active = true;
        self.previous_width = current_width;
        self.previous_length = length;
    }
    pub fn finish(self: *Line) void {
        if (self.active) std.Io.File.stderr().writeStreamingAll(self.io, "\n") catch {};
        self.active = false;
    }
    pub fn deinit(self: *Line) void {
        self.finish();
        if (self.size_file) |file| file.close(self.io);
        self.size_file = null;
        self.enabled = false;
    }
};
pub fn bar(w: *std.Io.Writer, fraction: ?f64, cells: usize) !void {
    try w.writeByte('[');
    const filled: usize = if (fraction) |f| @intFromFloat(@min(1, @max(0, f)) * @as(f64, @floatFromInt(cells))) else 0;
    for (0..cells) |i| try w.writeByte(if (fraction == null and i == 0) '?' else if (i < filled) '#' else '-');
    try w.writeByte(']');
}
test "terminal capabilities and bounded ASCII bars" {
    try std.testing.expect(supported("xterm-256color", false, true));
    try std.testing.expect(!supported("dumb", false, true));
    try std.testing.expect(!supported("unknown", false, true));
    try std.testing.expect(!supported("xterm", true, true));
    var b: [32]u8 = undefined;
    var w: std.Io.Writer = .fixed(&b);
    try bar(&w, 0.5, 10);
    try std.testing.expectEqualStrings("[#####-----]", w.buffered());
}
