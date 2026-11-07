pub const Shape = struct {
    height: usize,
    width: usize,
    channels: usize,
    pub fn len(comptime self: Shape) usize {
        if (self.height == 0 or self.width == 0 or self.channels == 0) @compileError("image dimensions must be positive");
        return self.height * self.width * self.channels;
    }
};
pub const Kind = enum { dense, conv2d, average_pool2d };
pub fn inputIndex(comptime S: type, comptime l: usize, out: usize, k: usize) ?usize {
    const spec = S.layers[l];
    if (spec.kind == .dense) return k;
    const src = S.shapes[l];
    const dst = S.shapes[l + 1];
    const c = if (spec.kind == .conv2d) k % src.channels else out % dst.channels;
    const pixel = if (spec.kind == .conv2d) k / src.channels else k;
    const y = @as(isize, @intCast((out / dst.channels / dst.width) * spec.stride + pixel / spec.kernel)) - @as(isize, @intCast(spec.padding));
    const x = @as(isize, @intCast((out / dst.channels % dst.width) * spec.stride + pixel % spec.kernel)) - @as(isize, @intCast(spec.padding));
    if (y < 0 or x < 0 or y >= src.height or x >= src.width) return null;
    return (@as(usize, @intCast(y)) * src.width + @as(usize, @intCast(x))) * src.channels + c;
}
pub fn weightIndex(comptime S: type, comptime l: usize, out: usize, k: usize) usize {
    const row = if (S.layers[l].kind == .conv2d) out % S.shapes[l + 1].channels else out;
    return row * S.fanins[l] + k;
}
pub fn biasIndex(comptime S: type, comptime l: usize, out: usize) usize {
    return if (S.layers[l].kind == .conv2d) out % S.shapes[l + 1].channels else out;
}
