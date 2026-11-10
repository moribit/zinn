pub const Random = struct {
    state: u32,
    pub fn init(seed: u32) Random {
        return .{ .state = if (seed == 0) 0x6d2b79f5 else seed };
    }
    pub fn next(self: *Random) u32 {
        var x = self.state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.state = x;
        return x;
    }
    pub fn unit(self: *Random) f32 {
        return @as(f32, @floatFromInt(self.next() >> 8)) / 16777216;
    }
    pub fn index(self: *Random, maximum: usize) usize {
        const bound: u32 = @intCast(maximum);
        const threshold = (0 -% bound) % bound;
        while (true) {
            const x = self.next();
            if (x >= threshold) return x % bound;
        }
    }
};
