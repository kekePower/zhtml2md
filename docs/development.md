# zhtml2md development notes

This file records the runtime mechanics established by milestone 0
probing, the design decisions that follow from them, and the rules
contributors must follow when changing the library. Everything here was
verified empirically on Zsh 5.9.2 (x86_64-mageia-linux-gnu); re-verify
before relying on it on other versions or platforms.

## Environment baseline

- Minimum supported runtime: Zsh 5.9. Development host: Zsh 5.9.2 on
  Linux. No `zmodload` module and no external command may become a
  runtime dependency of loading or conversion.
- All library code runs under `emulate -L zsh -o no_multibyte` with a
  local `LC_ALL=C`. Strings are byte strings; subscripts and `${#var}`
  are byte-oriented.

## Reading input (verified)

- Use `IFS= read -r -u FD -k 65536 chunk`. Without `-u`, `read -k` tries
  to read from the terminal, not stdin.
- Short final reads can return status 1 while retaining the partial
  chunk, including regular files when read via `builtin read`. Do not
  depend on a successful status for partial data. The reader loop must
  therefore be
  `while read ... || (( ${#chunk} > 0 )); do (( ${#chunk} == 0 )) && break; ... done`.
- NUL bytes survive `read -k` (zsh metafies them) and round-trip through
  parameter storage and `printf '%s'`. They are detected and rejected
  during validation.
- Throughput: reading 1 MiB in 64 KiB chunks takes ~10-16 ms.
- Empty file: the first read fails with an empty chunk. Exact-size EOF
  (file length a multiple of the chunk size) yields one extra failed
  empty read. Both are handled by the loop above.

## Byte-level operations (verified)

- Byte value of a one-character string: `(( #c ))` yields 0-255 under
  `no_multibyte`.
- Emit a byte: `builtin printf '\xHH'` (octal `\0ooo` also works).
- NUL detection: `[[ $s == *$'\x00'* ]]` works; the offset is
  `${#${s%%$'\x00'*}}`. NOTE: `${s[(i)$'\0']}` cannot match the metafied
  NUL and must not be used.
- Forbidden-control detection: a bracket range pattern such as
  `$'[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]'` works under a C locale; the
  prefix strip `${s%%${~pat}*}` gives the zero-based offset.

## Loading safety (verified)

- Alias expansion is the parse-time hazard. The loader guard is a first
  line with quoted command words (quoting defeats alias expansion),
  followed by disabling alias expansion for the rest of the parse:

  ```zsh
  'builtin' 'typeset' _zhtml2md_X_loadopt=${options[aliases]:-off}
  'builtin' 'setopt' 'noaliases'
  ```

  The capture MUST come before `setopt noaliases`; reading the option
  afterwards captures the value we just changed. (This bug was observed
  in practice.)
- `LOCAL_OPTIONS` does not restore options when a file is sourced at top
  level (there is no function scope). Each sourced file restores the
  caller's ALIASES setting manually at its end, from a per-file
  uniquely-named capture parameter, and unsets it.
- Verified hostile aliases on `local`, `integer`, `emulate`, `builtin`,
  `typeset`, `print`, `printf`, `source`, and the library's own function
  names do not affect loading or execution (tests/integration/loading.zsh).
- RUNTIME HAZARD: zsh re-parses `$( )` command-substitution bodies when
  they execute, honoring aliases armed after the function was parsed.
  Rule: production library code contains no command substitutions at all
  (checked with `grep -n '\$(' zhtml2md.zsh bin lib`); keep it that way.
  Test code quotes command words inside substitutions.
- Self-location: `${${(%):-%N}:A}` resolves the sourced file to an
  absolute path from any cwd, through relative or absolute source paths.
  When a script is found via PATH, `$0`/`%N` is already the resolved
  absolute path.
- `typeset -r` redeclaration fails, so repeated sourcing guards
  constants with `(( ${+name} ))`.
- Bare `local name` outside a function prints the current value if the
  parameter exists. Keep all library code inside functions; in scripts,
  always assign at declaration.

## Performance hazards (measured)

- Character-by-character loops cost ~78 us/byte (5.1 s for 64 KiB).
  Never loop per byte over bulk text. Bounded per-byte work (tag syntax,
  character references, UTF-8 sequences) is fine.
- Front-strip consumption with `${rest%%...*}` plus `${rest[n,-1]}`
  tail copies is quadratic: measured 55 s for 0.5 MiB. Never do this on
  the whole document.
- C-level splitting is fast: `${(@ps:<:)s}` on 1 MiB takes ~10 ms;
  per-segment `${(@ps:&:)seg}` over the whole document ~90 ms. The
  tokenizer (milestone 2) splits the input on `<` once at C level and
  then processes bounded segments.
- Profiling the tokenizer revealed growing costs when selecting segments
  from large indexed arrays. The lexer now stores segments and delimiter
  offsets in associations keyed by trusted generated integer strings.
  Ordinary token lookups select an entry without copying the full source
  or selecting repeatedly from a growing indexed array. Stack arrays are
  bounded to 256 slots and remain indexed by depth.
- Ordinary candidates start at 256 bytes and grow geometrically to the
  tag limit plus one byte. Each lexical state can grow the window;
  `<` inside quotes stays in the same candidate. Short tags do not copy
  a full 64 KiB window.
- `${var%%$'\n'##}` (and likely other `##`-repeat trailing strips) is
  pathological: the OOM killer terminates the process around 500 KiB of
  non-matching tail. Use `[[ $s =~ $'\n+$' ]]` (libc regex, linear) and
  slice once with `MBEGIN`.
- `${var//[ $'\t\n']/}` class substitution is quadratic on large
  whitespace runs (OOM-killed at 4 MiB). Use a single `[[ ... ]]`
  pattern scan for membership questions.
- A bare `exec {fd}< file 2>/dev/null` applies the `2>` redirection to
  the whole shell permanently. Wrap in a brace group:
  `{ exec {fd}< "$f" ; } 2>/dev/null`.
- `printf '%s' "$out"` detects write failure (e.g. /dev/full) with
  status 1.

## UTF-8 validation strategy

ASCII fast path: one C-level bracket-pattern scan. Detailed validation
uses a bounded 4 KiB window to locate non-ASCII bytes, then checks each
sequence arithmetically (length from the leading byte; continuation
ranges; E0/ED/F0/F4 second-byte restrictions, which exclude overlong
forms, surrogates, and values above U+10FFFF). Dense non-ASCII runs are
walked sequentially so the window is not re-sliced per character.

Known worst case: megabytes of dense non-ASCII text cost a few
arithmetic operations per character and are much slower than ASCII.
This is bounded and correct; the milestone 5 benchmark decides whether
optimization is needed. Typical prose/markup (the benchmark family) is
mostly ASCII.

## Verification commands

```zsh
zsh -df tests/gen-fixtures.zsh   # regenerate fixtures (review the diff!)
zsh -df tests/gen-entity-fixtures.zsh # regenerate hand-authored entity cases
zsh -df tests/gen-parser-fixtures.zsh # regenerate reviewed token/frame events
zsh -df tests/run.zsh            # parse checks + fixtures + integration
zsh -df bench/run.zsh            # benchmark skeleton
zsh -df bench/parser.zsh         # parser-only warm timing probe
```

`tests/run.zsh` is the mandatory offline runner: it parse-checks every
shipped Zsh file with `zsh -f -n`, runs every fixture in a separate
`zsh -df` process, and runs the integration scripts (hostile loading,
empty-PATH purity, I/O errors, resource-limit boundaries).

## Fixture format

`tests/fixtures/NAME.{html,md,status}` are required; `.opts`, `.stderr`,
`.stdin`, `.noinput` are optional markers. See the header comment of
tests/run.zsh. Expected Markdown is authored by hand from
docs/implementation-plan.md, never generated from implementation output.

## Current status

Milestones 0-3 are complete. The public renderer consumes parser events
for prose, headings, links/images, emphasis, literal code, metadata discards,
and textual form/definition fallbacks. ASCII prose whitespace collapses;
code whitespace survives; nonempty output ends in exactly one LF.
Milestone 4 still needs complete list numbering/hierarchy and table/span
relationships. No v1 release or complete conversion performance claim
follows from the current implementation.

## Entity component protocol

`_zhtml2md_decode_entities TEXT ORIGINAL_BYTE_OFFSET` writes a
caller-local `_zhtml2md_decoded`, leaving it empty on failure. It uses the
same diagnostic counters as the public pipeline. Call it directly, not
through command substitution, only for eligible tokenizer text/attribute
values. It does not normalize whitespace or produce Markdown.

`_zhtml2md_entities_init` locates `data/entities.tsv` through the library's
installation directory and reads at most 128 KiB plus one byte. It checks
framing, field counts, ASCII names, unique names, Unicode scalars, and
the exact 2,125-entry count before publishing `_ZHTML2MD_ENTITIES` and
`_ZHTML2MD_ENTITIES_READY`. Failures publish no cache and always close the
owned descriptor; repaired installations can retry. Sourcing and text
without ampersands do not read the data.

Numeric parsing validates digits before arithmetic, strips long leading
zero runs with a C-level scan, and accumulates at most seven significant
digits before saturating above the Unicode range. UTF-8 encoding uses
validated integer byte arithmetic and generated octal escapes with
`printf -v '%b'`. That conversion requires `\0ooo`, not `\ooo`; exact-byte
fixtures catch this distinction. Regex scratch parameters (`MATCH`,
`MBEGIN`, `MEND`, `match`, `mbegin`, `mend`) are local to helpers so a
caller using regex results does not lose them.

The decoder splits on `&` once, accounts decoded fragments against the
capture limit, and joins once. All 2,125 named values have an independent
UTF-8 fixture oracle. Component tests also cover all forbidden C0/DEL
references, C1 replacements, long numeric candidates, capture boundaries,
malformed/missing data, retries, hostile aliases/options, and empty PATH.
Run them through the mandatory offline runner; no Python or network is
needed. The independent oracle's provenance is in tests/entities/README.md.

## Tokenizer/frame protocol

`_zhtml2md_parse` reads the usual invocation-local input/BOM/strict and
diagnostic context after bounded reading and UTF-8 validation. It owns
all lexical state, frame arrays, and event parameters. No per-conversion
state survives the call except the immutable entity cache.

`_zhtml2md_lex_next` produces `token_kind`, `token_name`, `token_data`,
`token_start/end`, `token_self/literal`, the associative `token_attrs`
and `token_attr_offsets`, and source-ordered `token_attr_names`, all with
the `_zhtml2md_` prefix. Source ranges are zero-based with exclusive ends,
including BOM bytes. Discarded script/style/title body tokens carry a
range without copying their payload. Text and attributes decode only
after their lexical context is known; duplicate values are ignored.

Parallel stack arrays retain IDs, tags, discard and synthetic flags at
each active depth. IDs are monotonic; slots are released on pop. The
fixed `_zhtml2md_parse_event` sink receives `event_kind/name/data/attrs`,
`event_start/end`, `event_id/parent`, and `event_discard/synthetic/literal`
in the parser's dynamic scope. It dispatches to `_zhtml2md_render_event`
when the invocation-local renderer is active, otherwise returns success.
It is not a public hook. Tests replace it inside isolated processes to collect
reviewed events. The parser propagates sink failures and emits no
conversion stdout itself.

The diagnostic order is pinned: sibling-scope repair, paragraph repair,
then source-ordered attribute decoding/validation. Generated closes at a
trigger have a zero-width range there. EOF warnings use the input-end
offset, one per open source frame; discard owners use
`unterminated-discard`. Synthetic containers and the intrinsic plaintext
EOF termination do not warn. Closing source tags cannot match a synthetic
container. The paragraph-breaking set is explicit in
`_zhtml2md_breaks_p`; unknown elements infer no boundary.

80 hand-authored lexical/frame fixtures include tolerant/strict pairs.
Boundary integration covers exact 64 KiB tags, depth 256, synthetic and
discard depth, candidate growth, large comments/raw bodies, numeric
limits, warnings, Unicode/code bytes, nested scopes, literal payloads,
sink failures, aliases/options, repeated calls, and empty PATH. Fixture
recording uses quoting only for comparison, never as executable data.
Every tokenizer transition advances its source cursor, scans a bounded
candidate/window, consumes a token, or reaches EOF; stack repair loops
strictly decrease bounded depth.

Initial parser-only timings and their limitations are recorded in
docs/benchmarks.md. They do not measure complete Markdown conversion.

## Markdown rendering mechanics

`_zhtml2md_markdown` owns all `_zhtml2md_r_*` state in its dynamic scope.
Root output and each lookahead capture own a linked list of fragments,
stored under generated numeric association keys. Appending a short event
does not recopy the entire document. A capture is joined and its live charge
released before its transformed result transfers to the parent. Empty
ancestor captures retain no copies of child payloads. Output and live capture
charges are checked separately, including generated separators/delimiters
and the final LF. A failed conversion never emits the buffered Markdown.

Pending spaces and block boundaries emit only with subsequent content.
Leading/trailing block whitespace does not require a final Markdown regex
sweep. Prose normalization/escaping and raw CRLF normalization use bounded
4,096-byte windows; newline and backtick runs carry across window boundaries.
Even unusually long fences use binary doubling of a literal backtick rather
than global substitution over a multi-megabyte space run. Regex scratch
parameters remain local. Code and destination contexts never pass through
prose escaping. Escaping source ampersands prevents Markdown from expanding
a once-decoded entity a second time.

Adjacent code captures merge through the previous fragment's known delimiter
width, without retaining a second raw-code copy. Emphasis uses conservative
plain-text fallbacks at punctuation/Unicode edges, inside other emphasis,
or beside colliding generated markers. Fences and block-bearing links cannot
be forced into headings/inline syntax; their child blocks survive instead.

52 hand-authored Markdown fixtures and rendering integration checks cover
these decisions. The integration checks call the public function repeatedly
in the same shell under adverse options, verify untouched regex scratch and
unrelated parameters, exercise real 16 MiB counters, and run cold full
conversion from another directory with command lookup unavailable.
