//! Offline Markdown inline-link/fragment and mirrored API-fence checker.
const std = @import("std");
const Checker = struct {
    a: std.mem.Allocator,
    io: std.Io,
    failures: usize = 0,
    links: usize = 0,
    files: usize = 0,
    fn fail(self: *@This(), path: []const u8, target: []const u8) void {
        self.failures += 1;
        std.debug.print("documentation: {s}: unresolved {s}\n", .{ path, target });
    }
    fn read(self: *@This(), path: []const u8) ![]u8 {
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, self.a, .limited(4 * 1024 * 1024));
    }
    fn slug(self: *@This(), heading: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        for (std.mem.trim(u8, heading, " \r#")) |c| {
            if (c == ' ' or c == '\t') try out.append(self.a, '-') else if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c >= 128) try out.append(self.a, std.ascii.toLower(c));
        }
        return out.toOwnedSlice(self.a);
    }
    fn anchor(self: *@This(), bytes: []const u8, fragment: []const u8) !bool {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        var fenced = false;
        var seen: std.StringHashMap(usize) = .init(self.a);
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "```")) {
                fenced = !fenced;
                continue;
            }
            if (fenced or !std.mem.startsWith(u8, line, "#")) continue;
            var n: usize = 0;
            while (n < line.len and line[n] == '#') : (n += 1) {}
            if (n >= line.len or line[n] != ' ') continue;
            const base = try self.slug(line[n + 1 ..]);
            const item = try seen.getOrPut(base);
            if (!item.found_existing) item.value_ptr.* = 0;
            const actual = if (item.value_ptr.* == 0) base else try std.fmt.allocPrint(self.a, "{s}-{d}", .{ base, item.value_ptr.* });
            item.value_ptr.* += 1;
            if (std.mem.eql(u8, actual, fragment)) return true;
        }
        return false;
    }
    fn check(self: *@This(), path: []const u8) !void {
        const bytes = try self.read(path);
        self.files += 1;
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        var fenced = false;
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "```")) {
                fenced = !fenced;
                continue;
            }
            if (fenced) continue;
            var at: usize = 0;
            while (std.mem.indexOfPos(u8, line, at, "](")) |start| {
                const end = std.mem.indexOfScalarPos(u8, line, start + 2, ')') orelse break;
                at = end + 1;
                const target = std.mem.trim(u8, line[start + 2 .. end], " <>");
                if (target.len == 0 or std.mem.indexOf(u8, target, "://") != null or std.mem.startsWith(u8, target, "mailto:")) continue;
                self.links += 1;
                const hash = std.mem.indexOfScalar(u8, target, '#') orelse target.len;
                const file = target[0..hash];
                const resolved = if (file.len == 0) path else try std.fs.path.resolve(self.a, &.{ std.fs.path.dirname(path) orelse ".", file });
                std.Io.Dir.cwd().access(self.io, resolved, .{}) catch {
                    self.fail(path, target);
                    continue;
                };
                if (hash < target.len and std.mem.endsWith(u8, resolved, ".md")) {
                    const contents = if (file.len == 0) bytes else try self.read(resolved);
                    if (!try self.anchor(contents, target[hash + 1 ..])) self.fail(path, target);
                }
            }
        }
    }
    fn mirror(self: *@This(), path: []const u8, marker: []const u8, source: []const u8) !void {
        const bytes = try self.read(path);
        const start = std.mem.indexOf(u8, bytes, marker) orelse return self.fail(path, marker);
        const open = std.mem.indexOfPos(u8, bytes, start, "```zig\n") orelse return self.fail(path, marker);
        const end = std.mem.indexOfPos(u8, bytes, open + 7, "```") orelse return self.fail(path, marker);
        const actual = try self.read(source);
        if (!std.mem.eql(u8, std.mem.trim(u8, bytes[open + 7 .. end], " \r\n"), std.mem.trim(u8, actual, " \r\n"))) self.fail(path, source);
    }
};
pub fn main(init: std.process.Init) !void {
    var c: Checker = .{ .a = init.arena.allocator(), .io = init.io };
    for ([_][]const u8{ "README.md", "README_ja.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "SECURITY.md", "CHANGELOG.md" }) |file| try c.check(file);
    for ([_][]const u8{ "docs", ".github" }) |root| {
        const dir = try std.Io.Dir.cwd().openDir(init.io, root, .{ .iterate = true });
        defer dir.close(init.io);
        var walk = try dir.walk(c.a);
        defer walk.deinit();
        while (try walk.next(init.io)) |entry| if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".md")) {
            try c.check(try std.fs.path.join(c.a, &.{ root, entry.path }));
        };
    }
    try c.mirror("README.md", "<!-- zinn-api-sample -->", "examples/docs/model.zig");
    try c.mirror("README_ja.md", "<!-- zinn-api-sample -->", "examples/docs/model.zig");
    try c.mirror("docs/api/models.md", "<!-- zinn-image-sample -->", "examples/docs/image.zig");
    std.debug.print("documentation: {d} files, {d} local links, {d} failures; 3 mirrored fences\n", .{ c.files, c.links, c.failures });
    if (c.failures != 0) return error.BrokenDocumentation;
}
