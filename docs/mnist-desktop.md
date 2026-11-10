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

- 7 headless tests in Debug/ReleaseSafe: blank/clear, bounded continuous strokes,
  translation invariance, area weights against training preprocessing, pointer/
  focus lifecycle, immediate inference, generated sample logits and a drawn7.
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
