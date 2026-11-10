//! Host-only reinforcement learning. Never imported by infer.zig.
pub const centeredActionHead = @import("policy.zig").centeredActionHead;
pub const Random = @import("random.zig").Random;
pub const Replay = @import("replay.zig").Replay;
pub const Transition = @import("replay.zig").Transition;
pub const dqn = @import("dqn.zig");
pub const Dqn = dqn.Dqn;
test {
    _ = @import("tests.zig");
}
