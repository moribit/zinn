const z = @import("zinn");
comptime {
    _ = z.Tensor(i8, &.{ 2, 0, 3 });
}
