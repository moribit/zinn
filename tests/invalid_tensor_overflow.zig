const z = @import("zinn");
comptime {
    _ = z.Tensor(i8, &.{ @import("std").math.maxInt(usize), 2 });
}
