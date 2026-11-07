const z = @import("zinn");
comptime {
    _ = z.Tensor(i8, &.{});
}
