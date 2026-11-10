const M = @import("sensor_model").Model;
var workspace: M.Workspace = .{};
export fn classify(input: *const [M.input_len]i8, output: *[M.output_len]i8) void {
    M.infer(input, output, &workspace);
}
