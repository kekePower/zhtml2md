# Contributing

Read AGENTS.md and docs/implementation-plan.md before changing behavior.
The runtime targets native Zsh 5.8+ on Linux. Loading, input handling,
parsing, rendering and entity-data loading use only Zsh code and builtins.
Developer tools may be external; none may become a runtime dependency.

Update the contract and hand-authored fixtures together when behavior changes.
Review expected Markdown for relationships and literal data, including code
whitespace and destinations. Never record implementation output as a golden
oracle. Keep HTML out of evaluation, unchecked arithmetic and dynamic names.
Preserve caller options, aliases, traps, locale, paths and owned descriptors.
Git attributes disable line-ending conversion and whitespace linting for
byte-exact fixture data; intentional CRLF, tabs and trailing spaces are facts
under test. Source and documentation still receive ordinary whitespace checks.

```zsh
zsh -df tests/run.zsh
ZHTML2MD_TEST_ZSH=/absolute/path/to/zsh-5.8/Src/zsh \
  /absolute/path/to/zsh-5.8/Src/zsh -df tests/run.zsh
```

The mandatory offline suite and generators are Zsh. Their filesystem/timeout
setup uses development utilities from coreutils (`mkdir`, `rm`, `cp`, `cat`,
`chmod`, `timeout`); the converter under test does not. The runner parses all
shipped Zsh test, runtime and benchmark files before exercising exact-byte
fixtures, recovery, limits, adverse callers, installed layout and mutations.
The mutation worker has a 120-second development timeout, including cleanup.

Optional development checks:

```sh
python3 -m venv /tmp/zhtml2md-verify
/tmp/zhtml2md-verify/bin/pip install markdown-it-py==3.0.0
/tmp/zhtml2md-verify/bin/python tools/check-markdown
python3 tools/audit-runtime            # strace adds Linux process evidence
zsh -df tests/optional-zoup.zsh /path/to/zoup
zsh -df bench/gen-corpus.zsh
zsh -df bench/run.zsh 20 > /tmp/benchmark.tsv
```

Benchmark generation is deterministic and uses synthetic seeds committed
under bench/seeds. `bench/generated` is ignored and can be regenerated.
GNU time supplies optional peak RSS; `zsh/datetime` is used only by the
measurement driver. Record all samples, the environment and input/output
hashes; run at least 20 warm measurements. Avoid simultaneous benchmark jobs
and separate cleanup savings from conversion savings. Token counts require a
named, versioned optional tokenizer; byte counts are not token estimates.

The GitHub Actions workflow builds checksum-pinned upstream Zsh 5.8 and
5.9.2, runs the offline suite and independent Markdown/runtime audits. Network
access is used only for CI tool setup, not the converter or measurements.
Release checks and known limits are recorded in docs/release-readiness.md.
