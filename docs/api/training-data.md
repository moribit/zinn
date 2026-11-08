# Training and datasets

Host only. [Trainer source](../../src/train.zig), [fit](../../src/fit.zig), [data](../../src/data.zig), [executable examples](../../examples/docs/api.zig).

Additive observed variants and fit.Options.observer/model_name are documented in [host progress](../progress.md). Old methods/signatures remain available with observation disabled by default; callbacks do not cause extra evaluation passes or change checkpoint v1.

## Trainer

`Trainer(comptime S:type) type` returns parameters:[S.parameter_count]f32, seed:u32, epochs:u32, and Sample `{input:[S.input_len]f32,target:[S.output_len]f32}`. No implicit dataset allocation; training does use large local activation/gradient arrays, unsuitable for MCU stacks.

| Method | Returns / behavior |
|---|---|
| init(seed:u32) | Self; deterministic initial parameters |
| forward(self:*const Self,input:*const [S.input_len]f32,activations:*Activations) | void; caller-owned `[S.layer_count+1][S.max_width]f32` |
| predict(self:*const Self,input:*const [S.input_len]f32) | `[S.output_len]f32` logits/activations |
| gradient(self:*const Self,sample:Sample,result:*[S.parameter_count]f32) | f32 MSE; use gradientWithLoss(...,loss_kind) for CE |
| trainEpoch(self:*Self,samples:[]const Sample,rate:f32) | !f32; one batch update, MSE (legacy name) |
| trainBatch(self:*Self,samples:[]const Sample,rate:f32,loss_kind:Loss) | !f32; averaged loss, one SGD update |
| evaluate(self:*const Self,samples:[]const Sample) | !Evaluation `{loss:f32,correct:usize}`, MSE |
| evaluateWithLoss(self:*const Self,samples:[]const Sample,loss_kind:Loss) | !Evaluation; mse or cross_entropy |
| encode(self:*const Self) | `[checkpoint_len]u8` |
| decode(self:*Self,bytes:[]const u8) | !void; checked replacement |

Loss is mse/cross_entropy. trainBatch validates nonempty samples, finite positive rate, finite input/targets/updates/loss; CE requires unactivated final logits and nonnegative targets summing to1 within1e-4. Errors include InvalidTrainingOptions, CrossEntropyRequiresLogits, InvalidClassTarget, NonFiniteInput/Parameters/Loss. Evaluate rejects empty/nonfinite inputs/results, but callers must still provide meaningful targets. Low-level forward/predict/gradient are arithmetic primitives, not validated dataset boundaries. epochs counts **optimizer updates**, not dataset passes. Decode checks exact length/magic/schema/checksum/finite parameters (InvalidCheckpoint, CheckpointSchemaMismatch, CheckpointChecksumMismatch, NonFiniteParameters); it preserves format v1.

## fit helper

`fit.split(comptime Sample:type,samples:[]Sample,validation_count:usize,seed:u32)` returns `!struct{training:[]Sample,validation:[]const Sample}` views into the same mutated array. It shuffles deterministically when count>0; count>=len or empty input gives InvalidValidationCount. Caller owns/frees the original allocation. Do not alias validation into mutable training.

`fit.train(comptime T:type,model:*T,training:[]T.Sample,validation:[]const T.Sample,options:fit.Options,curve:*std.Io.Writer) !fit.Result` fits mini-batches with CE, shuffles training, records per-epoch CSV and restores best validation accuracy (ties: lower CE). No validation means keep final model. Options: epochs20,batch32,rate.05,seed42,decay_every10,decay.3;0 period disables decay. Result has best_epoch, counts and best_validation_loss/correct. Invalid options/empty training or rate underflow fail. Model-copy/gradient/activation memory is host-oriented; no MCU inference dependency.

## Dataset APIs

| Signature | Ownership and errors |
|---|---|
| data.csv(comptime T:type,allocator:Allocator,text:[]const u8,header:bool) ![]T.Sample | Caller frees returned samples. Class then exactly input_len finite features; blank/CRLF allowed; rejects quotes, bad labels/columns/features/empty data |
| data.IdxImages.init(bytes:[]const u8) !IdxImages | Borrowed view; verifies big-endian magic2051, positive dimensions/count and exact payload length |
| images.image(index:usize) ![]const u8 | Borrowed image; SampleOutOfBounds |
| data.IdxLabels.init(bytes:[]const u8) !IdxLabels | Borrowed values; magic2049/count/payload checks |
| data.unpackGzip(allocator,bytes:[]const u8,limit:usize) ![]u8 | Caller frees; bounded decompression, CRC/length/trailing-data checks |
| data.resizeArea(pixels:[]const u8,height:usize,width:usize,output:[]f32,out_h:usize,out_w:usize) !void | Caller output; area resize then /255; shape/length/dimension limit4096 checks |
| data.mnist(comptime T:type,allocator,images:IdxImages,labels:IdxLabels,maximum:usize) ![]T.Sample | Caller frees; area28→16, one-hot10; validates all labels even for subset |
| data.mnistProcessed(...,preprocess:data.Preprocess) ![]T.Sample | Same; .area/.nearest explicit |

MNIST requires28×28 source, matching counts, labels0..9, maximum>0; T must have256 inputs/10 targets. IDX views require original bytes to outlive access. Gzip buffers and sample arrays are separate allocations. CSV quoted fields and general-purpose image decoding are unsupported. Keep normalization identical in training/calibration/production. Code examples for CSV, malformed input, IDX and quantization are in the compiled sample linked above and [dataset tests](../../src/data_tests.zig).
