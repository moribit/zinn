const z = @import("zinn");
const model = @import("trained_model");
const board = @import("board_adapter");
pub const ch32fun_swio_log_enabled = false;
comptime {
    model.Model.checkBudget(.{});
}
var server: z.Service(model.Model, board) = undefined;
pub fn main() noreturn {
    server.init(model.model_id);
    board.paintStack();
    while (true) server.step();
}
