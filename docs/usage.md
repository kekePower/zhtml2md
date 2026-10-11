# zhtml2md usage

`zhtml2md` converts UTF-8 HTML into compact, deterministic Markdown.
It is a pure Zsh 5.8+ library with a small CLI wrapper. The definitive
behavior contract is docs/implementation-plan.md; this guide covers the
interface.

The v1 candidate implements the documented interface and HTML subset.
It is verified on Linux with Zsh 5.8 and 5.9.2. See supported-html.md for
rendering rules and fallbacks, benchmarks.md for measured costs, and
release-readiness.md for the completed acceptance review.

## Installation

Copy the repository layout intact. `zhtml2md.zsh`, `lib/`, `data/`, and `bin/`
must remain siblings; the library locates its files relative to its own
path, so it works from any working directory. Nothing is downloaded,
generated, or compiled on first use.

For example, create a user-owned installation directory and copy the whole
checkout into it (including LICENSE, NOTICE and data/LICENSE.WHATWG). Then
source its `zhtml2md.zsh`, or add its `bin` directory to PATH for the CLI.
The CLI's `env zsh` shebang selects Zsh from PATH; an explicit invocation such
as `/absolute/path/to/zsh -df /path/to/bin/zhtml2md -- page.html` selects a
particular interpreter. Linux is tested; macOS support is not yet claimed.

For a pipeline with an upstream cleaner, see zoup-integration.md. zoup is
optional; no special cleaned-input mode is needed.

## Library

```zsh
source /path/to/zhtml2md/zhtml2md.zsh

zhtml2md < page.html > page.md
zhtml2md -- page.html > page.md

local markdown
if markdown=$(zhtml2md -- page.html); then
  # command substitution removes trailing newlines
  print -r -- $markdown
fi
```

Loading is silent and idempotent. The library preserves the caller's
options, aliases, traps, locale, `IFS`, working directory, `path`,
`fpath`, and file descriptors, across loading, successful calls, and
failed calls. It defines the `zhtml2md` function, `_zhtml2md_*` helpers,
and `_ZHTML2MD_*` installation metadata; nothing else. The component parser
also uses a lazily initialized `_ZHTML2MD_ENTITIES` cache and readiness
flag. The cache is immutable by
convention and is not a configuration
interface. Only fd 0 is
consumed, and only when stdin is the selected input.

Repeated conversions in one shell are safe; conversion state is local to
each invocation.

## CLI

```text
zhtml2md [--strict] [--] [FILE|-]
zhtml2md --help
zhtml2md --version
```

- No operand, or `-`: read stdin through EOF.
- One file operand: opened read-only on a descriptor owned by the
  converter. Filenames are literal data: spaces, newlines, and glob
  characters need no special handling; a path beginning with `-`
  requires `--`.
- `--strict`: fail on a documented recoverable syntax defect instead of
  applying the documented repair.
- `--help` / `--version`: print and exit; they cannot be combined with
  conversion arguments or with each other.
- Unknown options, duplicate options, or multiple operands: usage error,
  status 2.

## Output, buffering, and status

Markdown is written to stdout only. Diagnostics go to stderr.
Conversion output is buffered until reading, validation, parsing, and
rendering have all succeeded, so a failed conversion emits no partial
document. This does not make output files transactional: a caller's
`> page.md` redirection may truncate the file before conversion starts,
and a write failure during final emission can leave partial data.

| Status | Meaning |
| --- | --- |
| 0 | success (including documented tolerant repairs) |
| 1 | input/output failure, initialization failure, internal failure |
| 2 | invalid arguments |
| 3 | unsupported encoding, forbidden input bytes, strict-mode rejection |
| 4 | resource limit exceeded |

Empty input, or input containing only discarded content, succeeds with
zero output bytes. Nonempty output ends in exactly one LF; line endings
are LF.

## Diagnostics

```text
zhtml2md: CATEGORY at byte OFFSET: MESSAGE
```

Offsets are zero-based byte positions in the original input, including
an initial BOM. Operational failures (for example `input-io`,
`output-io`, `invalid-utf8`, `forbidden-control`, `resource-limit`,
`initialization`) may omit the offset. At most 20 warnings are printed;
any remainder is aggregated into one summary line. Source-derived
excerpts are sanitized and bounded to 80 bytes.

## Resource limits (v1, fixed)

| Resource | Limit |
| --- | --- |
| Input | 4,194,304 bytes |
| One ordinary tag candidate including attributes | 65,536 bytes |
| Simultaneously open semantic/discard frames | 256 |
| Final rendered output | 16,777,216 bytes |
| Pending captured payload | 16,777,216 bytes |
| Individual diagnostics | 20, then one summary |

The input reader blocks until EOF; a writer that never finishes is the
caller's responsibility.
