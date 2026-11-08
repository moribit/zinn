# Documentation audit — 2026-11-08

Scope: README, docs, examples, public declarations in src/root.zig and their implementations, build.zig, build_support/project.zig, CI, and vendored provenance. Baseline: eb96405. This is a documentation pass; numerical APIs and checkpoint v1 remain unchanged.

| Finding | Resolution |
|---|---|
| Entry page primarily Japanese; no English learning path or Japanese counterpart | English README and matching README_ja; topic index |
| Early benchmarks call 7 tests/current 2ns host XOR and3172B Flash representative | Preserve original as historical; current benchmark page separates accuracy, cross-build and unmeasured hardware |
| Old MNIST page describes all60,000 training/no validation; current default holds5,000 out | Current MNIST tutorial explains split, calibration and explicit final test; legacy page marked historical |
| README has overlapping dedicated and common commands without clear artifacts | Getting Started uses legacy XOR deliberately; CSV/MNIST teach common addProject workflow |
| CLI examples assume repeatable options/checkpoint but do not always state that | Tutorials use fixed options, names and matching checkpoint/schema; list exact output paths |
| Low-level definitions, shape/scale failures, dataset ownership, checkpoint semantics poorly indexed | API topic pages reference exact source and executable samples |
| Documentation links lead to older phase reports as if current | Current results point to benchmarks/practicality report; research records retained with historical notices |
| UART overview duplicated protocol, omitted package/power constraints and response verification context | Tutorial handles wiring/operations; API owns wire table; concepts links rather than duplicating it |
| Upstream snapshot had no formal LICENSE at old pin | Verify upstream d6524ff; synchronize LICENSE, READMEs, package file list; source unchanged; update provenance |
| No contribution, security, conduct, changelog, issue/PR templates | Add policies without inventing private contacts, release history or response guarantees; repository API confirms private reporting disabled2026-11-08 |
| No automatic documentation link/sample checking | Pure Zig checker for local Markdown links/anchors; fenced executable API sample checked by docs-check in CI |

## Validation policy

Commands are checked with Zig0.17.0 on macOS. XOR and toy CSV fitting are short tutorial checks; no real MNIST fitting, data download or physical flash is required by docs-check. MNIST fixture paths exercise both model families/formats but cannot establish accuracy. Prior accuracy/ELF results remain dated experimental evidence, not new hardware measurements. Linux/macOS CI configuration is maintained; a local macOS run does not attest remote CI success.

Relative links and fragment targets are checked across maintained and historical Zinn Markdown. Vendored READMEs refer to omitted upstream examples/tools and remain unmodified; those references belong to the full upstream repository and are excluded from the offline checker. External URLs require network and are outside the checker. WCH pin/voltage information is checked against official source/datasheet references; physical wiring is untested. English/Japanese README claims, benchmark rows, examples and status are reviewed as a pair.

## Follow-up

Keep archived reports in their current locations to preserve links. The former benchmarks page is additionally preserved as benchmarks-initial.md; deployment.md now links to canonical tutorial/API topics, avoiding two maintained wire specifications. Translate legacy research only when useful; English learning/reference pages are authoritative for current commands. Add actual board photos, serial captures and measurements when hardware becomes available. Configure GitHub private vulnerability reporting before advertising a private reporting channel. The code change in this pass is only the additive docs-check Build step/tool/samples and package distribution paths; inference/training APIs and numerical implementations are unchanged.
