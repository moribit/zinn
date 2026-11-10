# Visual progress bars

Historical visual-bar verification. For the subsequent command, ETA and summary changes, see [CLI consistency report](cli-consistency-report.md).

Host-only, standard-library implementation, Zig0.17.0. Baseline: `4bae530`.
Numerical APIs, checkpoint v1, exported model and CSV/JSON formats are unchanged.

## Before and after

Previously the training presenter streamed one plain line per retained epoch:

```text
epoch bars-real training 33% 1719/5157 elapsed=0.6s eta=1.1s rate=3060.0batches/s epoch=1 epochs=3 loss=0.34544 lr=0.05000 val_acc=89.32000 val_loss=0.37727 best=1
```

In a recognized TTY, auto now keeps a model header and redraws the same line.
Actual snapshots from a macOS PTY,80 columns, official MNIST training data,
three epochs, seed42, the existing validation split and256→16→10 MLP:

```text
training bars-tty-latest: checking build cache
Model: 256 -> dense(16) -> dense(10)
E1/3 B814/1719 [#---------] 16% L0.328 ETA 1s
E2/3 B821/1719 [####------] 49% L0.506 V89.3% Best89.3% ETA 1s
E3/3 B1719/1719 [##########] 100% L0.267 V90.7% Best90.7% ETA 0s
```

The three bar snapshots above are successive contents of one physical line,
not three permanent log lines. `L` is the latest batch loss during an epoch,
then training-set loss at its boundary. `V` and `Best` update at epoch boundaries
and persist across subsequent batches. These numbers are display verification,
not a new accuracy benchmark. Preparation/cache checks have no guessed percent.

An actual fresh four-file HTTPS MNIST download showed:

```text
MNIST: 4 files
[1/4] train-images-idx3-ubyte.gz
[######----------] 3.71/9.45MiB 39% 4.02MiB/s ETA 1s
[################] 9.45/9.45MiB 100% 4.89MiB/s ETA 0s
```

Again the progress snapshots replace one line. After successful validation and
atomic replacement, the last line is retained. The overall summary records
downloaded/cached file counts. A40-column forced re-download retained byte
progress and omitted speed/ETA, e.g. `[###--] 6.45/9.45MiB 68%`.
An existing valid dataset printed four `cached filename size` lines and
`MNIST 4/4: 0 downloaded, 4 cached`; no download bars were fabricated.

## Drawing and caching

- `auto` requires stderr TTY, no CI marker and a recognized TERM family:
  xterm/screen/tmux/rxvt/vt100/linux/ansi. Otherwise it safely uses plain.
- One line uses CR and ANSI erase-line. ASCII bars need no Unicode/font support.
  A retained handle to stderr's terminal is queried once per frame and shared
  by formatting/drawing, reserving one column; COLUMNS
  is only a fallback. Lower-priority whole training fields are omitted when
  space runs out. Shrinking a reflowing terminal clears the previous owned rows.
- The renderer never changes raw mode, cursor visibility or alternate screen.
  Completion/failure finalizes the line. SIGINT need not run Zig defers, but it
  cannot leave those terminal modes changed or print a false success.
- The training process emits bounded JSON-lines Event snapshots at most5Hz
  for ordinary batch updates. It continues saving the existing plain log.
  Epoch/lifecycle updates can bypass throttling. The presenter parses complete
  frames, preserves validation/best values, and draws them separately.
- Journal/Receipt and the actual cacheable native fitting Run remain intact.
  Only presentation runs every invocation. A cache hit prints cached/path
  summaries rather than replaying old events. No RNG or forward pass is added.
- Presenter and downloader have Zig Progress IPC disabled. The inherited Run
  holds Zig Build's stdio lock. The presenter's child build uses TERM=dumb and
  no inherited ZIG_PROGRESS; visual-mode build diagnostics are relayed after
  finalizing the active line. Compiler progress percentages are never invented.
- stdout remains reserved for existing machine-readable output. Plain keeps its
  existing log syntax; off suppresses Zinn rendering, including metadata.

## Verification

```sh
zig build test
zig build test -Doptimize=safe
bash tests/progress_cli.sh zig /tmp/zinn-visual-cli
bash tests/progress_pty.sh zig /tmp/zinn-visual-pty
zig build firmware firmware-trained firmware-production deploy size -Dprogress=off
```

The offline PTY suite uses the OS-provided `script` utility and stty, with macOS
and Linux command variants. It exercises actual training at40/60/80/120 columns,
download-shaped progress fixtures,120→40 resize, SIGINT and failure finalization. It compares
checkpoint/CSV across widths. GitHub Actions runs both CLI and PTY suites on
Linux/macOS and retains their transcripts; remote CI has not been run locally.

The CLI suite covers fresh/cached fits, plain/non-TTY auto/off, concurrent
same-project cache hits and invalid training. Across modes it compares
checkpoint/CSV/stdout, generated Zig source, model JSON and integer verification
summaries; failure must never claim cached success. Pure tests cover capability
fallback, bounded bars and retained validation state, alongside existing
download HTTP/gzip/IDX/MD5/atomic-replacement fixtures.

Manual macOS checks used actual PTYs, not just COLUMNS: real MNIST training,
fresh/reused/forced four-file downloads,120→40 resize, and Ctrl+C during an active
training bar. Resize reduced the displayed fields; interruption returned a
nonzero status and no completion summary. A temporary Python standard-library
PTY driver was used for resize/SIGINT automation only; it is not a project,
build, training or CI dependency.

Local results:49/49 unit tests in Debug and ReleaseSafe,18 compile-fail cases,
two executable documentation API tests, and241 local links passed. The CLI and
PTY suites passed. Source/JSON equality and exact independent-reference checks
held across modes. The fresh concurrent fit produced one completed run and one
cached run; already-cached concurrent fits also remained consistent.
The retained pre-change two-epoch fixture and three-epoch real-MNIST checkpoints
and curve CSVs were also compared with the new runs: all were byte-identical.

XOR production remains1508B Flash/16B static RAM. Its512B stack allowance is a
budget, not a stack measurement. No MCU execution or new inference timing was
measured. The progress path is host-only.

## Remaining limits

Actual Linux terminal emulators and remote GitHub Actions remain unverified in
this local macOS session. TERM is a capability hint, not a terminal emulator
probe. Cursor reflow on resize varies between terminal implementations; widths
below40 and persistent long model/path headers can wrap. Same-project presenters
serialize their journals; separate processes/projects writing to the same TTY
are not coordinated by a global terminal lock. SIGKILL cannot finalize a line.

Other evaluate/export steps still use saved logs/native Build status. The prior
presenter's build-script/option-forwarding limits remain documented in
[progress controls](progress.md). Event serialization is throttled, not free:
the presenter polls at100ms and allocates/frees parsed frames on the host; long
jobs/slow filesystems require their own overhead measurements.
