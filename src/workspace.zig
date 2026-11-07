pub fn Workspace(comptime width: usize) type {
    return struct { buffers: [2][width]i8 = undefined };
}
