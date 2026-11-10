const hw = @import("ch32fun");
const M = @import("sensor_model").Model;
var workspace: M.Workspace = .{};
// Application/debugger supplies already quantized pseudo-sensor samples.
pub export var sensor_input: [M.input_len]i8 = .{ 0, 127 };
var output: [M.output_len]i8 = undefined;
pub fn main() noreturn {
    hw.system.init(.{});
    hw.gpio.enableAllClocks();
    const led = hw.gpio.pin(.C, @import("gpio_options").led_pin);
    led.configure(.output_pp_10mhz);
    while (true) {
        // Already quantized pseudo-sensor input; replace in the application.
        const input: *volatile [M.input_len]i8 = &sensor_input;
        const sample = input.*;
        M.infer(&sample, &output, &workspace);
        led.write(output[1] > output[0]);
    }
}
