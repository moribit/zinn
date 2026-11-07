pub fn Tensor(comptime T: type, comptime dimensions: []const usize) type {
    const n = comptime blk: {
        if (dimensions.len == 0) @compileError("tensor requires dimensions");
        var checked: usize = 1;
        for (dimensions) |d| {
            const r = @mulWithOverflow(checked, d);
            if (r[1] != 0) @compileError("tensor size overflow");
            checked = r[0];
        }
        break :blk checked;
    };
    return struct {
        pub const shape = dimensions;
        pub const len = n;
        data: [n]T,
    };
}
