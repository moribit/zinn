//! Integration entry point: debugger/application supplies encoded inputs.
const fun = @import("ch32fun");
const m = @import("trained_model");
comptime {
    m.Model.checkBudget(.{});
}
pub const ch32fun_swio_log_enabled = false;
var workspace: m.Model.Workspace = undefined;
pub export var zinn_input: [m.Model.input_len]i8 = @splat(0);
pub export var zinn_output: [m.Model.output_len]i8 = @splat(0);
pub fn main() noreturn {
    fun.system.init(.{});
    while (true) {
        const input: *volatile [m.Model.input_len]i8 = &zinn_input;
        const output: *volatile [m.Model.output_len]i8 = &zinn_output;
        const sample = input.*;
        var result: [m.Model.output_len]i8 = undefined;
        m.Model.infer(&sample, &result, &workspace);
        output.* = result;
    }
}
