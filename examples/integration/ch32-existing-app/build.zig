const std = @import("std");
const zinn = @import("zinn");
const ch32 = @import("ch32fun_zig");
pub fn build(b: *std.Build) void {
    const dep = b.dependency("zinn", .{});
    const trained = zinn.addModel(b, dep, .{
        .name = "sensor",
        .model = b.path("model.zig"),
        .dataset = .{ .csv = .{ .training = b.path("train.csv"), .evaluation = b.path("validation.csv") } },
        .training = .{ .epochs = 2000, .validation_count = 0, .decay_every = 0 },
        .format = .int4,
    });
    // The application owns its firmware, runtime, GPIO and main loop.
    const hal = b.dependency("ch32fun_zig", .{});
    const fw = ch32.addFirmware(b, hal, .{ .name = "existing-app", .root_source_file = b.path("main.zig") });
    const gpio_options = b.addOptions();
    gpio_options.addOption(u4, "led_pin", b.option(u4, "led-pin", "Application GPIO pin, independent of model generation") orelse 1);
    fw.root_module.import_table.get("app").?.addImport("gpio_options", gpio_options.createModule());
    fw.root_module.import_table.get("app").?.addImport("sensor_model", trained.createModule(b, ch32.ch32Target(b), .small));
    const check = zinn.addMemoryCheck(b, dep, .{ .name = "existing-app", .elf = fw.getEmittedBin(), .flash_bytes = b.option(u32, "flash-bytes", "Flash capacity") orelse 16384, .stack_bytes = 512, .isr_bytes = 64 });
    _ = zinn.addMemoryCheck(b, dep, .{ .name = "custom-map", .elf = fw.getEmittedBin(), .target_name = "application-elf32", .stack_bytes = 512, .isr_bytes = 64 });
    b.getInstallStep().dependOn(check.step);
    b.installArtifact(fw);
}
