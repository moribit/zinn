# UART protocol and board adapters

[Protocol](../../src/protocol.zig), [Service](../../src/service.zig), [benchmark](../../src/benchmark.zig), [CH32V003 adapter](../../src/targets/ch32v003_uart.zig). See [tutorial](../tutorials/uart.md) for wiring/commands; this page owns the byte contract.

## Transport API

`protocol.Receiver(comptime N:usize) type`: N1..65535 at comptime. init(model_id:u32,timeout_ticks:u32,frame_ticks:u32) returns Self with a fixed [N]i8 input,12B header and counters. feed(byte:u8,now:u32)/poll(now:u32) return Event (.none/.request/.failure); reset clears parsing state. Input is valid only after a request event; next receive overwrites it. Clock differences wrap u32; provide nonzero deadlines shorter than one timer wrap.

`protocol.request(out:[]u8,opcode:Opcode,sequence:u16,model:u32,input:[]const i8) ![]const u8` writes a borrowed frame; info requires empty input, other opcodes nonempty, max65535. InvalidRequestLength/FrameBufferTooSmall on failure. Caller must keep out alive through transmission. `response(out,...,metrics:Metrics,logits:[]const i8) ![]const u8` similarly encodes fixed metrics/logits. `decodeResponse(bytes:[]const u8) !Response` requires exact frame/length/version/opcode/CRC; InvalidResponse otherwise; returned logits borrow bytes. crc(bytes) u16 has check vector123456789→29B1hex. [Compiled examples/tests](../../src/protocol_tests.zig) cover corruption, wrong identity/length, partial input, resync, random streams and timer wrap.

`Service(comptime M:type,comptime Board:type) type` has init(self:*Self,model_id:u32) and step(self:*Self) void. M supplies input/output lengths, Workspace/workspace_bytes and infer. Maximum255 classes. Service owns receiver/input, workspace, outputs, TX buffer and9 timing samples: instantiate globally for firmware. Input transfer is not a hidden heap/stack buffer. Generic Board callbacks:

| Declaration | Contract |
|---|---|
| pub const clock_hz | Timer ticks/second;48MHz for provided CH32 adapter |
| init() u32 | Initialize board; return adapter setup ticks |
| now() u32 | Monotonic wrapping timer |
| read() union(enum){none,byte:u8,failure} | Nonblocking byte/error poll |
| write(bytes:[]const u8) bool | Synchronous bounded send; false on failure |
| highWater() u16 | Conservative stack watermark; FFFFhex unavailable |

The provided adapter uses50ms idle and250ms total receive deadlines,115200 polling UART and100ms TXE deadline per byte. Service drops a failed TX (no retry queue); host must time out/retry. Port errors reset receive. Override board_adapter LazyPath in addProject; HAL stays outside the portable core. [Mock service test](../../src/service.zig) is a concrete adapter example.

## Wire v1

All multibyte integers little-endian; stop-and-wait, no authentication, encryption or replay prevention.

| Header offset | Size | Meaning |
|---|---:|---|
| 0 | 2 | ASCII ZI |
| 2 | 1 | version1 |
| 3 | 1 | infer1,info2,benchmark3; response request OR80hex |
| 4 | 2 | sequence |
| 6 | 4 | model_id; only info allows0 discovery |
| 10 | 2 | payload length |
| 12 | variable | request input bytes or response metrics/logits |
| end | 2 | CRC16-CCITT-FALSE(poly1021,initialFFFF) over header+payload |

Request input must be exactly N signed i8 bytes, or0 for info. Model_id fingerprints the quantized model, not an authenticated identity. Response payload has44B metrics followed by signed i8 logits:

| Payload offset | Type | Meaning |
|---|---|---|
| 0,1 | u8,u8 | status,class (255 when no classification) |
| 2 | u16 | measured iterations |
| 4,8 | u32,u32 | clock_hz,timer-read overhead |
| 12,16,20 | u32 each | inference min/median/max ticks |
| 24,26 | u16,u16 | stack watermark,workspace bytes |
| 28,32,36 | u32 each | adapter init,input transfer,preprocessing ticks |
| 40,42 | u16,u16 | logit count,input length |
| 44 | i8[] | every logit; empty for info/errors |

Status0..7: ok,bad_version,bad_opcode,bad_length,wrong_model,bad_crc,timeout,uart_error. Error responses never infer; partial headers may not have a usable sequence, so retry with a fresh frame. Normal infer does not time the kernel (timing metrics0); benchmark warms up once, samples9 timer-overhead reads and9 inferences, subtracts the minimum read overhead saturating at0, sorts and returns min/median/max. Includes requantization/int4 decode. Transfer/setup/preprocessing are separate; preprocessing0 because wire input is already quantized. Model has no runtime initialization phase.

The provided stack paint runs after board init, protects64B below current SP and reports conservative since-ready usage including the protected area; not startup maximum. Response checker preserves phase timing/workspace/stack fields and converts median ticks to ns from clock_hz, but marks physical_execution_attested=false even for file captures. Host simulation uses fake ticks, never hardware performance.
