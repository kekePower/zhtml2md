# zhtml2md

Pure Zsh 5.8+ conversion of UTF-8 HTML into compact, deterministic
Markdown for AI-agent workflows. No external commands, parsers, codecs,
or `zmodload` modules are used at load time or at conversion time.

```zsh
source /path/to/zhtml2md/zhtml2md.zsh
zhtml2md -- page.html > page.md
```

or via the CLI:

```sh
bin/zhtml2md -- page.html > page.md
```

In the preferred pipeline, `zoup` selects and cleans content and
`zhtml2md` converts the retained semantic HTML; the converter also works
standalone for its documented HTML subset.

Version **1.0.0-rc.1** is a locally verified v1 candidate. Milestones 0–6
implement the supported HTML contract, hardening, zoup integration coverage,
full-conversion benchmarks, notices and release checks. The offline suite runs
on actual Zsh 5.8 and 5.9.2 binaries on Linux. See the
[acceptance review](docs/release-readiness.md) and
[implementation contract](docs/implementation-plan.md).

## Documentation

- [docs/usage.md](docs/usage.md) - interface, statuses, limits
- [docs/supported-html.md](docs/supported-html.md) - accepted subset and
  deviations
- [docs/development.md](docs/development.md) - verified shell mechanics
  and contributor rules
- [docs/benchmarks.md](docs/benchmarks.md) - full conversion timings, peak memory, tokens and preservation
- [docs/zoup-integration.md](docs/zoup-integration.md) - optional cleaner API and tested upstream contract
- [docs/implementation-plan.md](docs/implementation-plan.md) - the v1
  contract

## Verifying a checkout

```zsh
zsh -df tests/run.zsh     # offline fixture + integration suite
zsh -df bench/run.zsh 20  # full offline benchmark; can take over 30 minutes
```

Optional checks and contribution instructions are in
[CONTRIBUTING.md](CONTRIBUTING.md). The real zoup check is optional; the
standalone suite never requires its installation.

## License

Project code: [Apache-2.0](LICENSE). Vendored WHATWG entity data has its
upstream notices in [data/README.md](data/README.md),
[data/LICENSE.WHATWG](data/LICENSE.WHATWG) and [NOTICE](NOTICE).
