# Target memory budgets

[Model estimate](../../src/model.zig), [ELF checker](../../src/budget.zig), [CLI report](../../tools/size.zig).

`Model.checkBudget(comptime target:Target) void` checks model parameter bytes against Flash minus reservation, and input+output+workspace+stack allowance against RAM. It returns nothing; failures are compile errors. This is **model-only**, excluding startup/runtime/transport/other globals. Example: `M.checkBudget(.{ .flash_bytes=16384,.ram_bytes=2048,.stack_bytes=512 });` inside comptime/function code, as in production firmware. It cannot substitute for final ELF analysis.

Target is defined in src/budget.zig (not re-exported from root). Defaults: flash_origin0,flash_bytes16384,reserved_flash_bytes64,ram_origin0x20000000,ram_bytes2048,stack_bytes512. `Target.validate() !void` rejects invalid/overlapping/wrapping regions and impossible allowances. `inspect(data:[]const u8,target:Target) !Report` checks ELF32 little-endian PT_LOAD spans: full VMA and Flash LMA, filesz<=memsz/file bounds, alignment, overlaps, write/execute policy and zero-fill. `Report.check(target) !void` separately enforces Flash and staticRAM+stack limits. Report fields flash/static_ram are u64 and include placement gaps to the highest occupied end.

Build use:

```sh
zig build size
zig build deploy -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=1 -Dstack-bytes=512
```

Errors include InvalidTargetBudget, ExpectedElf32LittleEndian, InvalidSegments, InvalidSegmentAlignment, VirtualAddressOutsideMemory, LoadAddressOutsideFlash, overlap/invalid-segment errors, FlashBudgetExceeded and SramBudgetExceeded. The same failure may be rejected early as an out-of-range segment rather than a later capacity error. JSON reports distinguish static RAM, allowance, margin and hardware_measured=false. A failed deploy may leave partial artifacts; never flash a build that failed validation.

512B is a **budget**, not measured stack use. Optional stack-audit uses LLVM disassembly for direct normal call paths, fails on reachable unknown/dynamic/recursive paths, excludes interrupts and arbitrary inline-assembly proofs. Stack paint measures only since-ready behavior and is not startup peak. CNN4 UART leaves128B margin after512B allowance; adding buffers/IRQs requires new accounting and physical measurements. Budget flags change checking, not linker placement or MCU capacity. They cannot make a larger model safe by declaring fictitious memory.
