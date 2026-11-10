const Rng = @import("random.zig").Random;
pub fn Transition(comptime inputs: usize) type {
    return struct { state: [inputs]f32, action: usize, reward: f32, next_state: [inputs]f32, terminated: bool, truncated: bool };
}
/// Caller owns fixed-capacity host storage. Sampling is with replacement.
pub fn Replay(comptime inputs: usize) type {
    return struct {
        const Self = @This();
        storage: []Transition(inputs),
        count: usize = 0,
        next: usize = 0,
        pub fn init(storage: []Transition(inputs)) !Self {
            if (storage.len == 0 or storage.len > 0xffff_ffff) return error.InvalidReplayCapacity;
            return .{ .storage = storage };
        }
        pub fn append(self: *Self, item: Transition(inputs)) void {
            self.storage[self.next] = item;
            self.next = (self.next + 1) % self.storage.len;
            self.count = @min(self.count + 1, self.storage.len);
        }
        pub fn sample(self: *const Self, rng: *Rng) !Transition(inputs) {
            if (self.count == 0) return error.EmptyReplay;
            return self.storage[rng.index(self.count)];
        }
    };
}
