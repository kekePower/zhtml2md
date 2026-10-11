# v1 candidate acceptance review

Candidate: **1.0.0-rc.1**, reviewed on Linux on 2026-10-11. Milestones 0–6
are complete, including the minimum-version change
to Zsh 5.8. This records local readiness; it does not publish or tag a release.

## Evidence against the completion contract

| Criterion | Artifact / verification |
| --- | --- |
| Sourceable library and CLI, statuses 0–4 | zhtml2md.zsh, bin/zhtml2md, exact I/O/argument fixtures and failure integrations |
| Pure Zsh loading, input, parsing, rendering, static data | tools/audit-runtime; cold empty PATH/module-path tests on 5.8 and 5.9.2; constant-path sources; TSV parsed as data |
| Documented supported subset and fallbacks | docs/supported-html.md; reviewed golden fixtures; optional independent CommonMark/GFM checks |
| Text, hierarchy, destinations, code, numbering, cells | 52 prose/code and 108 structural golden fixtures; five source/clean contract pairs; bench/seeds and exact benchmark expected outputs |
| Every strict/tolerant repair | 80 tokenizer/frame cases; public recovery pairs; 2,352 deterministic mutation checks under timeout |
| Limits, UTF-8 and buffered failures | encoding fixtures; exact input/tag/depth/output/capture boundaries; nested record ownership; zero stdout on rejected conversions |
| Caller-state and descriptor preservation | hostile aliases/options/traps/locale/regex tests, disabled aliases, repeated sourcing; 100 complete conversions with fixed persistent state and descriptors |
| Minimum and development stable versions | mandatory suite run with actual upstream Zsh 5.8 and local Zsh 5.9.2 binaries; CI builds pinned upstream versions |
| Runtime purity | no external executable work; eight builtin-only loader snapshot children, nine via CLI; zero children in conversion; dynamic module lookup disabled |
| Optional zoup interoperability | docs/zoup-integration.md; tests/contracts; optional-zoup.zsh verified against 0.1.0 / b9dd8c0 on both versions; standalone tests do not require zoup |
| Reproducible benchmark and preservation | bench/gen-corpus.zsh, run.zsh, worker.zsh, report.py, seeds, raw samples and hashed results; docs/benchmarks.md; named optional token counts |
| Installation, licensing and provenance | README, docs/usage.md, CONTRIBUTING, Apache-2.0 LICENSE, NOTICE, data/README.md and retained WHATWG license |
| Installed-copy examples outside checkout | copied layout from a foreign cwd, repeated library loading with empty lookup, CLI/library byte agreement |

## Local validation results

The final mandatory offline suite passes **307 checks, zero failures** on
each of actual upstream Zsh 5.8 and development Zsh 5.9.2. This includes
the mutation worker's 2,352 invariant checks and 14 hardening assertions.
Optional independent Markdown checks validate 22 semantic facts.
Runtime source/process audits pass on both shells, and the actual zoup check
passes five source/clean pairs on both.
All seven 4 MiB corpus cases also match their independently authored expected
Markdown on Zsh 5.8 with empty PATH and module_path.

The sourceable library is tested with no command or module lookup. Test setup,
benchmark timers, source builds, strace, Python, independent Markdown and token
checks are development tooling; they are not production dependencies.

## Performance envelope and remaining limitations

The full-conversion report records 20 warm runs for every corpus family/size,
plus load/first/CLI timing and optional peak RSS. Measurements are specific to
the documented workstation; byte and token changes are separate metrics.
Valid complex-table fallbacks can grow in size to preserve relationships.

The earlier no-process-at-load engineering target is explicitly clarified:
module-free alias-state snapshots create bounded, builtin-only Zsh children.
No external executable processes or native modules do conversion work; the
conversion loop creates no processes. The measured load cost is included in
the report. No data or HTML is evaluated in those snapshots.

Linux is verified. macOS is not claimed. The GitHub Actions workflow is
configured and its YAML/shell steps are checked locally; a hosted workflow run
has not been observed. zoup compatibility is pinned to the tested version.
This remains a converter for its documented subset, with the documented
recovery and fixed limits rather than browser-equivalent parsing.
