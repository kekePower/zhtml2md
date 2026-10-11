# zhtml2md

Pure Zsh 5.9+ conversion of UTF-8 HTML into compact, deterministic
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

Status: early implementation. Milestones 0-1 (runtime mechanics,
library/CLI, I/O contract, encoding validation) are complete and
verified. Milestones 2-3 connect the tokenizer, entity decoder, and iterative
recovery to Markdown rendering for prose, headings, emphasis, links, images,
code, and textual form/definition fallbacks. Nested list numbering and table
rendering remain milestone 4; this is not a complete v1 release. The
contract is [docs/implementation-plan.md](docs/implementation-plan.md).

## Documentation

- [docs/usage.md](docs/usage.md) - interface, statuses, limits
- [docs/supported-html.md](docs/supported-html.md) - accepted subset and
  deviations
- [docs/development.md](docs/development.md) - verified shell mechanics
  and contributor rules
- [docs/benchmarks.md](docs/benchmarks.md) - parser-only measurements;
  complete conversion report pending
- [docs/implementation-plan.md](docs/implementation-plan.md) - the v1
  contract

## Verifying a checkout

```zsh
zsh -df tests/run.zsh     # offline fixture + integration suite
zsh -df bench/run.zsh     # benchmark skeleton
```
