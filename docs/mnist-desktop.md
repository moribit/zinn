# MNIST desktop integration verification

The [independent example](../examples/mnist-desktop/README.md) uses the public
mimoc-ui package, pinned to aa61a53e63595f764b96a9dfd09b870d7a2f95d5. The local
mimoc-ui checkout had unrelated changes and was left untouched. No upstream patch
was necessary: the existing Mono1 renderer, Ui buttons, pointer events and macOS
bridge were sufficient. UI/AppKit dependencies exist only in this example.

## Implementation

- build.zig: independent package; bundled-source default; shared addModel for
  optional generation/training; consumer-target Module imports; explicit asset
  refresh, native executable/macOS app bundle and headless test/check steps.
- app.zig: caller-owned input/output/workspace, live stroke events, clear/sample,
  normalized input preview, predicted digit and all ten integer logits.
- canvas.zig: continuous antialiased brush, bounded coordinates, crop/20x20 fit,
  center-of-mass normalization and28→16 area weighting.
- main.zig/Info.plist: existing mimoc-ui AppKit bridge and headless PBM snapshot.
- assets: generated real MLP32 source/checkpoint/metadata, provenance and snapshot.

Zinn's kernels, checkpoint format, training implementation and numerical rules
are unchanged. Floats are used for desktop preprocessing only. There is no idle
inference and no learning in the GUI callback. The shipped model's 1024-sample
calibration and 5000-sample validation export use the existing pipeline.

## Verified locally

macOS arm64 / Zig 0.17.0:

- 13 headless tests in Debug/ReleaseSafe: blank/clear, bounded continuous strokes,
  translation invariance, area weights against training preprocessing, pointer/
  focus lifecycle, immediate inference, generated sample logits and a drawn 7.
- macOS executable and unsigned app bundle build; PBM snapshot renders without
  opening a window. The snapshot is stored in the example guide.
- Actual AppKit window: Tab/Return activates SAMPLE, Escape clears, mouse drags
  update the input and logits; drawing a horizontal and diagonal stroke produces
  a 7 and the app reports 7. This demonstrates interaction, not an accuracy study.
- Independent integer reference: all 5000 validation samples have all logits
  matched, 0 mismatches. Classification validation accuracy is separately 95.14%.
- Linux x86_64-musl headless tests cross-compile; native Linux execution is left
  to CI. No Linux graphical backend is supplied by the pinned mimoc-ui version.

The renderer originally showed unsupported '+' and ',' glyphs as '?'. Labels and
positive integer formatting now use supported glyphs. The UI shows logits as
scores, not calibrated probabilities. A partial stroke can change the result.

## Limits

Only digits 0–9 are modeled. Mouse/trackpad handwriting differs from MNIST scans;
no general handwriting-accuracy percentage is claimed. The fixed logical 480x272
surface clips/letterboxes on resize. The native bridge is macOS-only; Windows and
Linux GUI support require another mimoc-ui platform backend. The app bundle is
unsigned and is not a packaged release. No MCU firmware or hardware is involved.

Normal run needs neither data nor training, but the first build needs access to
the pinned UI dependency. Model replacement requires real MNIST data and matching
MLP32 structure; it must be followed by tests/provenance updates. Training uses
shared native Build caching and the existing progress presenter.

Existing root Debug/ReleaseSafe tests and 18 compile-failure checks remain green;
XOR CH32V003 production cross-build remains 1508B Flash/16B static SRAM. Offline
link/API checks resolve 299 local links across 59 Markdown files. The CI matrix now
runs desktop headless tests on Linux/macOS and builds/renders the macOS app without
opening a GUI. Remote CI status is separate from these completed local checks.

## Relative logit bars

The original layout and controls are retained. Only the 78px interiors of the
right-hand ten bars use new presentation math. Raw values remain int8; inference,
argmax, preprocessing, weights/checkpoint and quantization are unchanged. No
mimoc-ui modification, Softmax or floating-point score scaling was introduced.

[logits.zig](../examples/mnist-desktop/logits.zig) provides pure analyze/barWidth
functions. Width is `(value-min)*width/(max-min)`, rounded to nearest integer
(ties up), with widened arithmetic. Min/max differences and margins can span 255;
255×65535+127 safely fits u32. Values outside the supplied range clamp; equal or
inverted bounds return 0. A tied distribution draws all empty bars; duplicate
maxima in a nonconstant distribution each receive full width. The existing first
maximum prediction and outline are unchanged. Margin is top1−top2 in raw score
units, not confidence/accuracy; no always-visible field was added.

For the example distribution `[2,-31,-35,-13,0,34,-5,-8,20,12]`:

| Digit | Raw int8 logit | Previous width px | Relative width px |
|---|---:|---:|---:|
|5|34|49|78|
|8|20|45|62|
|9|12|42|53|
|0|2|39|42|
|1|-31|29|5|
|2|-35|28|0|

The margin is 14. The bars express that frame's relative score range, not
recognition probabilities. A negative score is not inherently a zero-width bar.

Verified locally with Zig 0.17.0/macOS:

- Debug and ReleaseSafe: 13/13 tests. Added cases cover min/max/midpoint/rounding,
  equal values, full int8 range, all-negative/all-positive values, duplicate
  maxima, margins 0..255 and exhaustive monotonicity over every int8 min/max pair.
- Pixel-level integration checks validate all five interior rows of each bar for
  all 16 bundled samples; every logit and predicted class matches the original
  generated fixtures. SAMPLE wrapping, CLEAR, drawn 7 and input lifecycle pass.
- Before/after PBM snapshots differ in 380 pixels, all confined to bar interiors;
  every other pixel, including raw numbers and prediction outline, is identical.
  The [example screenshot](../examples/mnist-desktop/assets/screenshot.png) is updated.
- In the actual macOS window, SAMPLE/Return updates the relative bars, Escape
  clears the result, and mouse strokes form a 7 correctly classified as 7. The
  maximum row remains outlined and full, with the minimum empty.

Changed files: app.zig (rendering/integration tests), new logits.zig (pure math
and unit tests), build.zig.zon (package file list), screenshot.png, example README,
this report, and CI's formatting list. No model assets or model computation were
changed. Physical trackpad gestures and manual resize were not separately
retested in this small display change; their existing event/resize code is
untouched. Linux native execution remains a CI check rather than a local macOS
claim. No new accuracy or performance measurement is claimed.
