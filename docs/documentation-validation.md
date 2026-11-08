# Documentation validation

Use Zig0.17.0 and run `zig build docs-check`. No extra package, Markdown utility, Python, data download or physical flash is required.

The checker scans root README/policy files, docs/ and .github/ Markdown. It checks inline relative link/image paths and heading fragments (including duplicate heading suffixes), ignoring fenced examples and external/mailto URLs. It compares marked README English/Japanese model fences and the ImageDefinition fence byte-for-byte with compiled example sources. Separate Zig tests exercise model definitions, training/checkpoint roundtrip, CSV, calibration/source export/int8/int4, Dense/Conv/Pool/workspace/Tensor and protocol APIs. Existing integration CI compiles generated source and the standalone addProject package.

Scope limits: this is a small repository-specific checker, not a full CommonMark renderer. Reference-style links, HTML anchors, URL percent decoding and external availability are not supported/validated; use inline links and ordinary GitHub heading anchors in maintained docs. Vendored READMEs are unmodified upstream documents, excluded because the source snapshot intentionally omits upstream tools/examples to which they refer. Their full repository links/provenance are in UPSTREAM.md. The checker always runs despite build caching so documentation-only edits are rechecked.

## Validation record — 2026-11-08

This section records the OSS documentation pass at36b73ec, before the progress feature. Current progress-specific checks and limitations are recorded in [host progress](progress.md#verification-and-overhead); file/link counts below preserve the original pass's evidence.

Compiler:0.17.0, macOS arm64. README/Getting Started XOR train/evaluate/quantize/e2e/deploy/size, explicit checkpoint loading, both XOR formats, external CSV train/evaluate/deploy/infer-host/simulate-uart and tutorial fixture MNIST MLP int8/CNN int4/UART benchmark paths passed. Core Debug/ReleaseSafe tests and18 compile-fail cases passed (core test result reused unchanged cached binaries). Two new executable API tests passed. Formatting and git diff whitespace checks passed.

Final offline documentation check: **45 Markdown files,224 local links,0 failures,3 mirrored code fences**. Negative probes confirmed missing files, missing heading fragments and README/source drift each fail; probes were removed/restored before the final passing run. English/Japanese README feature claims, representative rows, quick-start commands and model fence were reviewed together; the code fences are also mechanically equal. Linux is covered by updated CI configuration; this local record does not assert a remote run.

No actual MNIST download/training study, real UART exchange, flash or hardware measurement is performed for documentation validation. Previously recorded accuracy is cited with its original date. CLI examples that require data/hardware are explicitly labeled as opt-in.

## Keeping documentation synchronized

Update both READMEs for claims, tables, commands and status. Keep the marked model fences synchronized with examples/docs/model.zig; docs-check rejects drift. Review English/Japanese meaning as well as syntax: automatic code matching cannot validate translation semantics. New conceptual snippets should be complete compilable samples or clearly identified excerpts linked to executable examples. Avoid copying a full protocol specification into tutorials; api/uart.md is canonical.
