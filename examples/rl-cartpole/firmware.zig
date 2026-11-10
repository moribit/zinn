//! Integer policy only. Application/debugger supplies encoded normalized states.
const hw = @import("ch32fun");
const M = @import("policy").Model;
comptime {
    M.checkBudget(.{});
}
pub const ch32fun_swio_log_enabled = false;
var workspace: M.Workspace = .{};
pub export var cartpole_input: [4]i8 = .{ 0, 0, 5, 0 };
pub export var cartpole_scores: [2]i8 = .{ 0, 0 };
pub export var cartpole_action: u8 = 0;
pub fn main() noreturn {
    hw.system.init(.{});
    while (true) {
        const input: *volatile [4]i8 = &cartpole_input;
        const sample = input.*;
        var result: [2]i8 = undefined;
        M.infer(&sample, &result, &workspace);
        const scores: *volatile [2]i8 = &cartpole_scores;
        scores.* = result;
        const action: *volatile u8 = &cartpole_action;
        action.* = if (result[1] > result[0]) 1 else 0;
    }
}
