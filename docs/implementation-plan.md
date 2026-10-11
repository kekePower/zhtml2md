# zhtml2md implementation plan

Status: active implementation contract. Milestone 0 (runtime mechanics,
recorded in docs/development.md) and milestone 1 (library and I/O
contract) are complete and verified. Milestone 2's tokenizer, entity
decoder, and iterative structural recovery are complete. Milestone 3
connects these components to the public Markdown renderer and is complete.
Milestones 4-6 remain pending; list/table relationships are not yet rendered
by this development version. Their retained text has paragraph boundaries.

Prepared: 2026-10-10. Milestone 0-1 implementation: 2026-10-10.
Entity component implementation: 2026-10-10.
Tokenizer/frame component implementation: 2026-10-10.
Public prose/inline/code rendering: 2026-10-10.

## 1. Intended outcome

Build `zhtml2md`: a reusable, sourceable Zsh library that converts UTF-8 HTML into compact, deterministic Markdown for AI-agent workflows. Ship a small command-line wrapper around the same converter. All conversion, input handling, and runtime data loading must use pure Zsh shell code and builtins.

The preferred workflow is:

```text
HTML acquisition → zoup cleanup → semantic HTML → zhtml2md → Markdown → agent
```

`zoup` decides which content belongs in the document. `zhtml2md` converts the retained content into Markdown while preserving its text, order, relationships, and useful destinations. The converter must also work without `zoup` for its documented HTML subset.

The end result is a versioned library and CLI, documented behavior, an offline fixture suite, a reproducible benchmark, and evidence that the shipped runtime uses no external conversion programs. A smaller representation is desirable, but semantic correctness takes priority over minimum byte count. Token reduction must be measured with a named tokenizer before being reported as a token metric.

This document specifies v1. It is a plan, not a claim that any acceptance criterion already passes.

## 2. Goals

1. **Pure Zsh runtime.** No Python, Lua, Rust, JavaScript, C helper, `sed`, `awk`, `grep`, external parser, external codec, or required `zmodload` module in loading or conversion. Zsh's own executable and builtins are the only runtime requirements. Vendored static entity data is permitted.
2. **Reusable loading.** A caller can source one library file, call `zhtml2md` repeatedly, and continue using its shell without altered options, traps, aliases, working directory, locale, search paths, or leaked file descriptors.
3. **Useful semantic coverage.** Preserve prose, headings, emphasis, links, image descriptions, lists, quotes, code, definition lists, and table data.
4. **Reliable lexical handling.** Recognize quoted tag attributes, comments, raw-text elements, character references, mixed-case tag names, void elements, and ordinary HTML whitespace.
5. **Explicit recovery.** Apply a small, documented set of deterministic repairs for imperfect HTML. Offer strict operation for callers that require the input to satisfy that contract.
6. **Composability.** Read a file or stdin; write only Markdown to stdout; send diagnostics to stderr; return documented status codes.
7. **Deterministic output.** Identical supported input and options produce identical UTF-8 bytes regardless of the caller's locale and ordinary Zsh options.
8. **Bounded work.** Enforce input, tag-size, nesting, and output limits; avoid recursive parsing and repeated rescanning of the entire document.
9. **Evidence for agent use.** Demonstrate text and structural preservation alongside measured representation sizes on representative documents.

## 3. Non-goals for v1

- Browser-equivalent HTML tree construction, the complete HTML error-recovery algorithm, CSS layout, or JavaScript execution.
- Article extraction, relevance scoring, deduplication, navigation removal, ad removal, or summarization. These belong in `zoup` or another caller.
- HTTP fetching, authentication, redirects, cookies, content negotiation, rendering, or URL discovery.
- CSS visibility analysis. A `hidden` attribute or `display:none` alone does not instruct this converter to remove text.
- Resolving relative URLs against the source page, honoring `<base>`, or rewriting destinations.
- Character-set sniffing and conversion of non-UTF-8 documents.
- XML/XHTML conformance, SVG drawing interpretation, MathML rendering, or accessibility-tree construction.
- A DOM API, selectors, mutable document objects, or a BeautifulSoup replacement.
- Round-tripping Markdown back to the original HTML or retaining presentation attributes.
- Embedding raw HTML in generated Markdown as a fallback.
- Streaming output before the full conversion succeeds; concurrent use from multiple threads in one shell process.
- Bash/POSIX-shell compatibility, Oh My Zsh integration, native `zmodload` modules, or required compiled `.zwc` files.
- A plugin/hook system, multiple Markdown dialects, configurable formatting styles, or broad configuration through global variables.
- A promised percentage of token reduction or an unmeasured throughput claim.

## 4. Supported environment and distribution

Target Zsh 5.9 and later stable releases. The local development installation is Zsh 5.9.2. Use no development-only language features. Linux is the initial supported platform. Before claiming macOS support, run the same suite on its supported Zsh version and verify path and input behavior there.

The library is a sourceable collection of shell functions, not a native binary module. Sourcing is the required v1 loading mechanism. Keep a future autoload adapter possible without making it a separate v1 deliverable. Zsh's function-loading mechanisms are documented in the [Zsh function manual](https://zsh.sourceforge.io/Doc/Release/Functions.html).

Installation consists of copying the repository layout intact. Runtime files must locate sibling code and data relative to the library's own location, never relative to the caller's current directory. Do not download, generate, compile, or install anything on first use.

Developer tools for documentation, CI, independent Markdown verification, and optional token measurement may be external programs. They are not runtime dependencies. Keep the mandatory fixture runner and fixture generators in Zsh so contributors can verify the core contract with Zsh alone.

## 5. Public interface

### 5.1 Library

Planned usage after implementation:

```zsh
source /path/to/zhtml2md/zhtml2md.zsh

zhtml2md < page.html > page.md
zhtml2md -- page.html > page.md

local markdown
if markdown=$(zhtml2md -- page.html); then
  # Use the Markdown here. Command substitution removes trailing newlines.
fi
```

The library exports `zhtml2md` and namespaced implementation helpers. It does not change `fpath`, register hooks, define aliases, start jobs, or produce load-time output. Sourcing the same file twice must succeed without accumulating state.

Conversion state is local to each invocation. Helpers intentionally share a documented, namespaced dynamic-scope context declared by the top-level function. Do not use command substitution for internal tokenizer/renderer calls: it creates subshells and obscures shared state.

Only immutable, namespaced installation metadata and entity lookup data may persist across calls. A failed initialization must not mark the library ready. Entity data should load lazily on the first conversion and remain read-only by convention.

### 5.2 CLI

```text
zhtml2md [--strict] [--] [FILE|-]
zhtml2md --help
zhtml2md --version
```

- No operand, or `-`: read stdin through EOF.
- One file operand: open it read-only, using a descriptor owned by the converter.
- `--`: end option parsing, allowing paths beginning with `-`.
- `--strict`: fail on a documented recoverable syntax defect instead of applying repair.
- `--help` and `--version`: print the requested information without reading input. They cannot be combined with conversion arguments.
- Unknown options, duplicate singleton options, or multiple operands: usage error.
- Output redirection is the caller's responsibility; v1 has no `--output` option.
- v1 has fixed resource limits and no environment-variable configuration.

The CLI wrapper locates and sources the library, forwards arguments unchanged, and returns the library's status. It must contain no separate conversion implementation.

### 5.3 Output and status

| Status | Meaning | Conversion stdout |
| --- | --- | --- |
| `0` | Successful conversion, including documented tolerant repairs | Markdown, possibly empty |
| `1` | Input/output failure, runtime initialization failure, or internal failure | Empty before final emission; an output write failure may leave partial data |
| `2` | Invalid arguments | Empty |
| `3` | Unsupported encoding, forbidden input bytes, or malformed input rejected by strict mode | Empty |
| `4` | Resource limit exceeded | Empty |

Empty input or a document containing only discarded content succeeds with zero output bytes. Nonempty Markdown ends in exactly one LF. Generated prose and structure use LF line endings. Do not wrap paragraphs to a configured width or add a banner, source URL, metadata block, or summary.

Buffer output until input validation, parsing, and rendering succeed. This prevents parse failures from publishing a plausible but incomplete document. It does not make caller-owned output files transactional: shell redirection may truncate a destination before conversion starts, and a write failure can happen during final emission. Document that distinction in the usage guide.

Tolerant repairs produce bounded diagnostics on stderr and still return `0`. Report at most 20 individual warnings and then one count summary. Include a stable category and zero-based byte offset in the original input, including any initial BOM; never echo the whole document. Normalize line endings during text handling rather than replacing the source buffer and invalidating offsets. Strict mode fails at the first recoverable syntax defect with status `3`. Documented rendering fallbacks for valid unsupported structures are successful conversions, not syntax repairs.

## 6. Contract with zoup

This is a proposed interoperability contract. No inspection or implementation of `zoup` is assumed by this plan.

### 6.1 What zoup supplies

- UTF-8 HTML, either a fragment or a complete document, preferably with balanced semantic elements.
- The selected text in source order.
- Structural elements such as headings, paragraphs, lists, quotes, code, and tables.
- Relevant attributes: `href`, `src`, `alt`, `start`, `value`, `reversed`, `rowspan`, and `colspan` when used. A `language-*` class on code is optional.
- Original meaningful whitespace in code and around inline elements.
- Entity references or decoded text escaped correctly as HTML. For example, a literal `<` must remain distinguishable from a tag opener.

Removing a wrapper must preserve the text nodes and their whitespace. `a<span>b</span>` means `ab`; `a <span>b</span>` means `a b`. Neither project should blindly insert spaces at every tag or delete source spaces between inline elements.

### 6.2 What zhtml2md does independently

- Converts the retained structure to the documented Markdown representation.
- Ignores comments, declarations, document-head content, and the bodies of `script`, `style`, and `template` as its fixed conversion policy.
- Preserves navigation, header, footer, aside, and hidden text if supplied. Selecting or removing them remains `zoup`'s responsibility.
- Does not require a special cleaned-input mode. Use the same parser for cleaned and ordinary HTML.
- Does not attempt to recover text already removed by `zoup`.

### 6.3 Integration evidence

Maintain pairs of original HTML and agreed cleaned HTML, with expected Markdown for the cleaned form. Label them as contract fixtures until they are verified against an actual `zoup` release. Once `zoup` exposes its API, add an optional pipeline check and record the tested version. Its executable must never become a requirement for the standalone fixture suite.

## 7. HTML and Markdown behavior

### 7.1 General parsing rules

Accept HTML fragments and complete documents. Fold ASCII tag and attribute names to lowercase; preserve text, attribute values, and case-sensitive entity names. Honor single-quoted, double-quoted, and unquoted attributes; a `>` inside a quoted value does not close a tag. For duplicate attributes, retain the first value.

Recognize the HTML void-element set so those elements do not create stack frames. A self-closing slash on a non-void HTML element does not implicitly close it. Document this behavior, especially `<div/>` and `<script/>`.

Use explicit raw-text handling for `script` and `style`, and text-only handling for `textarea`, `title`, and `plaintext`. `title` is discarded as metadata. `textarea` text is preserved in a code block. `plaintext` consumes the rest of the input as literal code text. Script handling deliberately does not implement the full browser script-data escape algorithm; matching an appropriate closing end tag terminates the discarded region. Define this deviation in the supported-HTML guide.

EOF terminates `plaintext` normally, including in strict mode. Its
intrinsic EOF termination is not a missing-end-tag repair; outer open
source elements still require the normal EOF recovery. Entities are
decoded in `textarea`, but not in `plaintext` or discarded raw bodies.
Raw closing names match case-insensitively only when followed by ASCII
whitespace, `/`, or `>`; unfinished closing candidates remain raw body.

Plausible ordinary markup starts with `<` followed by an ASCII letter,
or `</` followed by an ASCII letter. A lone `<` or `</` at EOF is an
incomplete candidate. Ordinary tag names run through the first ASCII
whitespace, `/`, or `>`; unknown names remain literal data. Complete
attribute syntax is tokenized permissively without adding repairs to
section 7.7. An unquoted value includes `/`, so `<img src=x/>` retains
`src=x/`. Outside a value, `/` followed by optional ASCII whitespace and
`>` sets the lexical self-closing flag; it still cannot close a non-void
element. End-tag attributes have no semantic effect.

Comments terminate at the first literal `-->`. Other `<!` and `<?`
declarations terminate at the first unquoted `>`; this does not implement
XML internal subsets or the full browser bogus-comment algorithm.

Skip comments and doctype/declarations without rendering them. For discarded `template` regions, track nested templates and the same comment/raw-text rules so embedded text cannot prematurely end the region. `noscript` text is retained: the converter executes no JavaScript.

Structural recovery searches stop at an owned discard boundary. Starts
inside a discarded region cannot close paragraphs/list/table members
outside it, and end tags inside it cannot match retained outer frames.
The matching end tag for the discard owner itself may close that owner.

Unknown elements normally unwrap to their children. The generic block-container set is `address`, `article`, `aside`, `div`, `fieldset`, `figcaption`, `figure`, `footer`, `form`, `header`, `hgroup`, `main`, `nav`, and `section`; these create block boundaries. Elements with dedicated rendering rules create their own boundaries. Unknown elements introduce no inferred boundary. Preserve fallback text in SVG/MathML and other unsupported elements without interpreting their drawing or layout attributes.

This is a bounded tokenizer and semantic stack, not an implementation of the complete tree-building standard. The distinction is explicit in the [HTML parsing specification](https://html.spec.whatwg.org/multipage/parsing.html).

### 7.2 Rendering matrix

The output dialect is a CommonMark-compatible core with GFM pipe tables. Pin the reference versions in developer documentation; no user-selectable dialect in v1.

| Input | Required v1 representation |
| --- | --- |
| `h1`–`h6` | ATX headings with the corresponding level |
| `p`, recognized block containers | Paragraph boundaries; no invented headings |
| `br`, `hr` | Markdown hard break; standalone thematic break |
| `strong`, `b`; `em`, `i` | Strong/emphasis markers when representable; retain all text in a documented fallback |
| `a[href]` | Inline link with preserved decoded destination; empty labels use the destination as text |
| `a` without a usable `href` | Render its child content |
| `img` | Image Markdown when both description and destination exist; description alone without a destination; destination text when description is empty |
| `ul`, `ol`, `li` | Nested lists with continuation indentation and explicit ordered item numbers |
| `blockquote` | Prefix every rendered line, including blank lines, with the appropriate quote depth |
| `code` outside `pre` | Inline code when single-line content is representable; fenced-code fallback otherwise |
| `pre`, `pre > code` | Fenced code; preserve code whitespace; choose a fence longer than conflicting content |
| `textarea`, `plaintext` | Literal fenced code using their text-only parsing rules |
| Simple rectangular `table` | GFM pipe table with a separate header row |
| Complex `table` | Row/cell list fallback described below; retain span metadata |
| `dl`, `dt`, `dd` | Term paragraph followed by description blockquotes in source order |
| `details`, `summary` | Preserve summary and body in source order, including closed bodies |
| `input`, `select`, `option`, form containers | Preserve available textual values/labels; never submit or invent a live control |
| `del`, `s`, `sup`, `sub`, other unsupported inline formatting | Preserve child text without inventing unsupported syntax |
| `head`, `script`, `style`, `template`, comments, declarations | No rendered content |

For form controls, render `input`'s textual `value` for `text`, `search`, `email`, `url`, `tel`, `number`, and date/time-like types, plus explicit values for `button`, `submit`, and `reset`. A missing/unknown type uses the text fallback. Omit `hidden`/`password` inputs and non-text control state. Render all supplied `option` labels in order, separated into list items so adjacent labels cannot merge. Labels are ordinary retained content. This is a textual fallback, not a reconstruction of a form's accessible name or submitted state. Do not invent default button labels.

### 7.3 Whitespace and Markdown escaping

- Normalize CRLF and lone CR to LF before rendering.
- Outside literal code, collapse HTML ASCII whitespace runs to one pending space; emit it only where text adjacency requires it. Do not collapse all Unicode whitespace.
- Preserve non-breaking spaces decoded from entities; do not silently rewrite them to ordinary spaces.
- Delay block separators until content is emitted. Suppress leading/trailing blank blocks and avoid excess separators without running a global regex over the final Markdown.
- Inside code, preserve spaces, tabs, blank lines, and trailing spaces. Remove at most the single initial LF immediately after an opening `pre`, as an explicit HTML handling rule.
- Escape text according to its output context: prose, heading, emphasis, link label, destination, image description, list line, or table cell. Do not perform one global escape pass.
- Prevent source text from accidentally becoming a heading, list, quote, thematic break, link, raw HTML, or formatting marker. Test block-start contexts separately from inline contexts.
- For empty or whitespace-only emphasis, emit the literal child whitespace without empty delimiters. Move boundary whitespace outside emphasis markers; use plain-text fallback when delimiters would change the intended text.
- The initial renderer uses emphasis markers only with ASCII word edges;
  punctuation/Unicode edges, nested emphasis, and colliding adjacent markers
  use plain child text. Adjacent inline code spans combine their contents
  into one span rather than creating an ambiguous backtick run.
- Collapse heading-internal line breaks to spaces. If an inline formatting/link capture contains block structure that cannot fit its Markdown syntax, preserve the child blocks and append any destination separately rather than forcing them into inline syntax.
- A heading containing code that needs a fence uses child-block fallback,
  without ATX markers; preserving the code's line breaks takes precedence.
- Choose inline-code delimiters from the longest contained backtick run and apply required boundary padding. Use a fenced block when inline Markdown cannot preserve the content.
- Empty fenced content needs no invented blank content line. Nonempty
  fenced content without a terminal LF gains the framing LF required before
  its closing fence; all existing content whitespace is retained.
- Emit no raw HTML, including `<br>` inside tables. A cell needing an internal hard break uses the complex-table fallback.

Use the [CommonMark specification](https://spec.commonmark.org/0.31.2/) to check emitted delimiters, escaping, and code representations, and the [GFM table specification](https://github.github.com/gfm/#tables-extension-) for the simple-table syntax. These references govern output syntax; they do not turn the converter into a full Markdown parser.

### 7.4 Links and images

Decode character references in attribute values once. Escape Markdown destination delimiters without fetching, resolving, or normalizing URLs. Preserve relative paths, fragments, query strings, and explicit schemes as data. No scheme filtering or browser-sanitizer guarantee is part of v1.

Destinations containing controls, line breaks, or characters that cannot be represented without altering the destination must fall back to readable description/label plus a code representation of the destination, using a fence if inline code cannot preserve it. Preserve the information; do not silently drop the destination or embed raw HTML. Document that such a fallback is not a clickable Markdown link.

Ignore presentation attributes and optional link titles in v1. A code-language hint may come only from a `language-*` class token containing ASCII letters, digits, `_`, `+`, or `-`, with at most 32 characters. Otherwise omit the hint. Do not interpret a class as shell syntax.

### 7.5 Lists and tables

For unordered lists use `-`. For ordered lists honor validated `start` and `li value` values. Accept signed decimal values in the range -999999999 to 999999999 after bounded textual validation. Determine subsequent item numbers without evaluating source expressions. Buffer each ordered list's item metadata to classify its numbering; when `reversed` has no explicit start, use the item count. `reversed` is a boolean attribute: its presence activates descending numbering regardless of its string value. CommonMark renderers infer consecutive numbering rather than respecting each marker's value. Therefore use a native ordered list only for nonnegative, ascending-by-one sequences with at most nine digits per marker. For negative, descending, discontinuous, or wider numbers, use an unordered list with explicit literal number labels, preserving every supplied/generated number.

Indent list continuation content by the actual marker width. Cover multiline paragraphs, code blocks, quotes, and nested lists. An orphan `li` has the documented tolerant repair described below.

A simple table has no nested tables, non-unit spans, block content, multiline code, internal hard breaks, or inconsistent row widths. Missing span attributes mean one. Accept bounded decimal `rowspan` values from 0 to 65534 and `colspan` values from 1 to 1000; `rowspan=0` retains its meaning as a span through the remaining row group and triggers the complex fallback. An empty table emits only its caption, if present. If the first row is entirely `th`, use it as the header. Otherwise synthesize an empty header row and retain every original row as data. Emit a caption as a paragraph immediately before the table. Escape cell pipes and other Markdown syntax according to table context.

For a complex table emit a caption, then an ordered list of source rows. Each row contains an ordered list of source cells, identifying `th` cells as headers and stating any non-unit `rowspan`/`colspan` next to the cell, including `rowspan=0`. Preserve the cell's block content and nested tables through the same renderer. Do not duplicate spanning cell text, invent column names, or imply a rectangular alignment the converter has not established. Valid complex tables require no recovery warning.

### 7.6 Character references and encoding

Vendor the complete semicolon-terminated named-reference map from the official [HTML named-character reference data](https://html.spec.whatwg.org/multipage/named-characters.html). Include two-code-point values. Store the runtime form as plain, validated data; never source downloaded/generated data as executable code. Record upstream URL, retrieval date, checksum, generation instructions, and applicable licensing in `data/README.md`.

v1 deliberately requires the semicolon for named references. Preserve unknown or unterminated names literally. Support decimal and hexadecimal numeric references with a semicolon. Document that legacy semicolon omission is outside the v1 contract.

Validate digits and bound numeric accumulation before arithmetic. For zero, surrogates, and values above U+10FFFF, emit U+FFFD. Apply the HTML numeric-reference C1 replacement mapping for U+0080–U+009F. Reject decoded forbidden control bytes consistently with literal input; HT and LF are allowed, and CR is normalized to LF. Do not expand an entity twice: `&amp;lt;` must remain literal `&lt;` text before Markdown escaping.

Accept well-formed UTF-8 and an optional initial UTF-8 BOM. Reject NUL, invalid UTF-8, and C0/DEL controls other than HT/LF/CR with status `3`. Preserve Unicode text without normalization or transliteration. Use byte-oriented ASCII scanning with a locally scoped C locale; validate UTF-8 sequences and generate decoded Unicode as UTF-8 bytes with builtins. Locale-sensitive `%c` behavior is not an acceptable implicit codec.

### 7.7 Recovery contract

Apply only these specified repairs in tolerant mode; warn for each occurrence up to the diagnostic cap:

1. A new `li` closes an open sibling `li` in the same nearest list.
2. A new `p` or recognized paragraph-breaking block closes an open `p`.
3. A new `tr` closes an open row in the same table; a new `td`/`th` closes an open cell in the same row.
4. A matching end tag unwinds intervening frames before closing its frame. Preserve their already-read child content.
5. A non-void end tag without a matching open frame is ignored. End tags for void elements are ignored as defects.
6. An orphan `li` creates a synthetic unordered-list container for consecutive orphan items.
7. EOF closes open semantic frames. Unterminated discarded regions remain discarded through EOF. Each open source frame produces an EOF diagnostic; synthetic list containers produce none. `plaintext`'s intrinsic EOF termination is normal parsing, as specified in 7.1.
8. A dangling tag opener/unfinished ordinary tag at EOF is rendered as escaped literal text. An unterminated quote remains part of that literal candidate. A `<` that never begins plausible markup is ordinary text, not a defect.
9. An unterminated comment/declaration is discarded through EOF.
10. Invalid/out-of-contract numeric list or span attributes are ignored in favor of their defaults: ordinary list start 1, reversed start equal to item count, normal continuation for invalid `li value`, and unit spans. Issue an attribute-value warning; never evaluate the invalid value. Unknown/presentation attributes do not constitute a defect.

All of the above are defects in `--strict`, including omitted end tags that browsers accept in some contexts. State this explicitly: strict mode validates this converter's simpler contract, not HTML-standard conformance. Do not add ad hoc recovery rules without updating this list and fixtures.

New list/row/cell siblings close their previous sibling scope before
paragraph closure is considered. Structural repairs at a new opener
precede defects in that token's numeric attributes; attributes are decoded
and validated in source order. EOF diagnostics use the byte immediately
after the input; lexical unfinished-token diagnostics use the opener.
Each orphan item is a defect. Consecutive orphan items share a synthetic
list, including intervening whitespace/comments/declarations; nonwhite
text or another tag outside the item ends the group. Source end tags do
not match synthetic containers.
These scope searches respect the discard boundary described in 7.1.

Use a diagnostic envelope of `zhtml2md: CATEGORY at byte OFFSET: MESSAGE`. Pin categories in fixtures: `implicit-li-close`, `implicit-p-close`, `implicit-table-close`, `misnested-close`, `unmatched-end-tag`, `orphan-li`, `unclosed-element`, `incomplete-tag`, `unterminated-declaration`, and `invalid-numeric-attribute`. Use `unterminated-comment` and `unterminated-discard` for the corresponding EOF cases. Operational failures use separate categories such as `input-io`, `output-io`, `invalid-utf8`, `forbidden-control`, `resource-limit`, and `initialization`; offsets may be omitted where no input position exists. Sanitize any source-derived diagnostic excerpt and bound it to 80 bytes.

## 8. Internal architecture

### 8.1 Components and data flow

```text
argument validation
  → bounded byte reader + UTF-8 validation
  → tokenizer
  → entity decoding at eligible text/attribute boundaries
  → semantic frame stack + local recovery
  → context-aware Markdown renderer
  → bounded output fragments
  → final stdout emission
```

The input is read fully within a fixed limit before conversion. Rendering is event-driven and iterative, with local buffering for code, links, list items, and tables where lookahead is required. Do not construct a complete generic DOM or recurse once per HTML element.

Tokenizer results are structured local parameters: token kind, source start/end offsets, tag name, self-closing marker, and an associative attribute map. Text runs use offsets where practical. No newline-delimited serialization of arbitrary text, `eval`, or reparsing generated shell code.

Use parallel arrays indexed by frame ID for frame kind, parent, content fragments, and necessary metadata. Never derive variable names or function names from HTML. Namespaced dynamic-scope parameters are an intentional internal protocol; each helper must document the context it reads and writes.

Renderer fragments are literal strings. Keep byte accounting incremental; avoid repeatedly joining an ever-growing output. Track pending spaces and block boundaries separately from text. Join once for final emission, allowing for the temporary memory cost in the benchmark.

### 8.2 Tokenizer

Explicit states include data, tag-open/name, before/after attribute name, before attribute value, single/double/unquoted attribute value, comment, declaration, raw text, text-only content, and discarded region. Use monotonically advancing offsets.

In ordinary data, seek the next ASCII delimiter and emit a text span. Character-by-character handling is appropriate for tag syntax and bounded character references, not every byte of long prose. Raw discarded content should scan toward matching end-tag candidates without allocating its body as a second string.

Avoid applying a pattern to the entire remaining document for every character. Quote or escape any literal fragments used in patterns; source text must not become a pattern program. HTML tokenization must not use Zsh's shell-word lexer as a substitute for the HTML grammar.

### 8.3 Native shell hygiene

- Every callable public/helper function establishes the required native semantics with `emulate -L zsh` and explicit required options.
- The loader must also suppress alias expansion while function definitions are parsed. Body-level emulation alone cannot undo parse-time aliases. Choose and verify a constant-code loading strategy during milestone 0.
- Use only prefixed helpers and state names. Avoid special Zsh parameter names such as `status`, `path`, and `commands` for scratch variables.
- Use builtin-qualified literal output and a constant `printf` format. Never use `print -P`, `${(e)}`, `eval`, or `source` on HTML or entity data.
- Validate numeric attributes and references as bounded text before assignment to integers or arithmetic expressions.
- Keep attributes as literal data and keep list values as arrays; no implicit word splitting.
- Localize locale/options/traps. Use `always` cleanup for owned descriptors. Do not close or reposition caller-owned descriptors beyond consuming the explicitly selected input.
- Verify library loading, repeated calls, failures, and use under adverse options. Loading and execution are separate test cases.

The available builtins and their input/output behavior should be checked against the [Zsh builtin manual](https://zsh.sourceforge.io/Doc/Release/Shell-Builtin-Commands.html) and verified on the minimum supported version.

### 8.4 Resource limits

| Resource | v1 limit | Enforcement |
| --- | --- | --- |
| Input | 4 MiB / 4,194,304 bytes | Bounded reads; detect one extra byte and fail |
| One ordinary tag candidate including attributes | 64 KiB / 65,536 bytes | Tokenizer checks while advancing |
| Simultaneously open semantic/discard frames | 256 | Check before every push, including synthetic frames |
| Final rendered output | 16 MiB / 16,777,216 bytes | Charge appended fragments and separators before accepting them |
| Pending captured payload | 16 MiB / 16,777,216 unique bytes | Account for live captures; transfer fragment ownership rather than duplicating it per ancestor |
| Individual diagnostics | 20 warnings | Aggregate the remainder into one final count |

Plain text, comments, raw text, and code are not subject to the ordinary-tag limit, but remain bounded by input/output limits. Repeated references to an existing fragment must not evade output accounting. Account for pending captures separately from the finalized output, releasing their charge as ownership transfers. Transient joins/escapes can require additional allocations; they must be bounded by the documented input/capture/output sizes. Final-output accounting alone is insufficient when captured content can later be discarded.

These limits prevent unbounded buffers; they are not a promise of a 16 MiB process-memory ceiling. Input, arrays, retained fragments, entity data, and the final join add overhead. Measure and document actual peak memory.

The reader is blocking until EOF. Network timeouts and writers that never finish are the caller's responsibility. Do not add a background reader or shell-wide signal trap to emulate a timeout.

## 9. Repository deliverables

Planned layout:

```text
zhtml2md.zsh                  # sourceable public entry point and safe loader
bin/zhtml2md                 # Zsh CLI wrapper
lib/_zhtml2md_input.zsh      # arguments, bounded reading, encoding
lib/_zhtml2md_tokenizer.zsh  # lexical states and attributes
lib/_zhtml2md_entities.zsh   # data loading and reference decoding
lib/_zhtml2md_frames.zsh     # stack and documented repairs
lib/_zhtml2md_render.zsh     # Markdown contexts and output buffers
data/entities.tsv            # vendored static named-reference data
data/README.md               # provenance, format, regeneration, licensing
tests/run.zsh                # mandatory offline runner
tests/fixtures/              # HTML, expected Markdown, status/stderr expectations
tests/integration/           # shell loading/state and zoup contract cases
bench/run.zsh                # fixture generation and timing driver
bench/corpus/                # attributed or synthetic representative inputs
docs/implementation-plan.md
docs/usage.md
docs/supported-html.md
docs/development.md
docs/benchmarks.md
README.md
LICENSE                      # project license selected before release
```

The split is a responsibility boundary, not a requirement to implement every helper as a separate module. Keep files small enough to review without creating a plugin framework. Data-generation tooling may be added under `tools/`; it must be explicitly development-only and offline during normal runtime.

Use a three-field entity-data format: ASCII name without `&`/`;`, first Unicode scalar in hexadecimal, and optional second scalar in hexadecimal, separated by tabs. Validate every field before building the association. The cache stores decoded UTF-8 values keyed by the literal validated name. Regeneration must verify the expected upstream entry count and each value; malformed local data is an initialization error, not HTML input to repair.

## 10. Implementation sequence

Each milestone produces code, documentation updates, and the named verification before dependent work begins. Estimates are intentionally omitted until the shell mechanics and baseline performance are measured.

### Milestone 0 — Prove the runtime mechanics [COMPLETE]

Tasks:

1. Confirm Zsh 5.9 availability and the stable builtin semantics needed for reading, byte slicing, associations, and output.
2. Prototype fixed-size builtin reads under a local C locale. Verify partial final reads, empty input, NUL detection, CRLF, exact-boundary EOF, and pipes. Do not depend on `/dev/stdin` or `/proc`.
3. Prototype UTF-8 validation and numeric-reference-to-UTF-8 emission using builtins only, including two-code-point values and invalid ranges.
4. Prototype safe source loading under aliases and adverse shell options; locate sibling files when sourced through an absolute or relative path.
5. Compare byte scanning with text-span scanning on small and 1 MiB synthetic inputs. Identify full-tail copies or quadratic work before adopting the tokenizer structure.
6. Add the minimal offline fixture runner, benchmark skeleton, and versioned constants for limits and statuses.

Acceptance: the mechanical probes pass on 5.9 and the local version, including operation without external programs on `PATH`. Record the chosen mechanics in `docs/development.md`. If a proposed mechanism fails, replace it with another builtin design and revise this plan before building the parser; do not introduce an external runtime dependency.

### Milestone 1 — Library and I/O contract [COMPLETE]

Tasks:

1. Implement the sourceable loader, public function, CLI wrapper, option parser, and version/help output.
2. Implement bounded file/stdin reading, UTF-8 validation, initial BOM handling, and owned-descriptor cleanup.
3. Implement result buffering, literal final emission, resource accounting, and bounded diagnostics.
4. Add empty-input and literal-text conversion as the initial vertical slice.
5. Write the first usage guide and tests for status codes, filenames, repeated loading, and caller-state preservation.

Acceptance: documented invocations work; failed reads/encoding checks emit no conversion stdout; the library is silent on load and leaves caller state intact. A filename containing whitespace or beginning with `-` is handled literally.

### Milestone 2 — Tokenizer, entities, and structural recovery [COMPLETE]

Tasks:

1. Implement the lexical state machine, text spans, attributes, comments/declarations, void elements, and raw/text-only regions.
2. Vendor and validate the entity data with recorded provenance; implement one-pass text/attribute decoding and numeric references. All 2,125 named values have independent exact-byte fixtures; decoding is now connected to eligible parser text/attribute boundaries.
3. Implement iterative frames, discard policies, byte offsets, and every listed recovery rule.
4. Add strict-mode behavior and limits for tags/depth.
5. Add tokenizer-level fixtures separate from Markdown output so lexical mistakes can be isolated.

Acceptance: quoted `>`/`<`, mixed case, duplicate attributes, fake tags in scripts/comments, nested templates, entities, malformed EOF, and strict/tolerant pairs produce the specified events or statuses. Every transition either advances input, consumes a token, changes a bounded state, or finishes; no infinite retry loop is possible.

Verified artifacts: `_zhtml2md_tokenizer.zsh`, `_zhtml2md_frames.zsh`,
80 reviewed token/frame fixtures (including strict pairs), and parser
integration checks for Unicode/code whitespace, inert data, every repair
category, exact tag/depth boundaries, warning caps, sink failure, aliases,
caller state, repeated use and empty PATH. The fixed internal event sink
now dispatches to invocation-local rendering during public conversion.
Discard-scope regressions cover inner paragraph/list starts and unmatched ends.

### Milestone 3 — Prose, links, images, and code [COMPLETE]

Tasks:

1. Implement pending spaces/block boundaries, context-specific escaping, headings, paragraphs, hard breaks, thematic breaks, and emphasis.
2. Implement captured link labels and destinations, image fallbacks, metadata discards, and unknown-element unwrapping.
3. Implement inline/fenced code, preserved whitespace, language hints, `textarea`, and `plaintext` behavior.
4. Add form/textual fallbacks, details/summary, and definition lists.
5. Add independently reviewable golden fixtures that cover delimiter collisions and block-start escaping.

Acceptance: supported text and destinations survive; code whitespace survives; source punctuation cannot accidentally become generated Markdown structure. Raw HTML is never used as a renderer fallback.

Verified artifacts: `_zhtml2md_markdown.zsh`, public parser integration,
52 reviewed Markdown fixtures in addition to the 25 I/O/encoding fixtures,
and rendering integration assertions for ownership transfers, exact 16 MiB
fragment/capture caps, final-LF accounting, depth 256, scanning-window seams,
code delimiter collisions, form values, discard isolation, warning summaries,
hostile aliases/options/regex state, repeated use, and empty PATH. Validation
uses Zsh 5.9.2; minimum-version and complete-conversion benchmarking remain
release/hardening work. List/table rendering remains milestone 4.

### Milestone 4 — Nested structures and tables

Tasks:

1. Implement ordered/unordered lists, explicit/reversed numbering fallbacks, marker-width continuation indentation, and nested quotes.
2. Implement buffered table classification, captions, pipe tables, empty synthetic headers, and complex-table row/cell fallbacks.
3. Exercise list/quote/table/code combinations and malformed structural input.
4. Enforce temporary-buffer and output accounting for nested captures.

Acceptance: lists preserve hierarchy and numbering, quotes cover all lines, and every source table cell remains represented in order. Span information survives without fabricated alignment or repeated cell text.

### Milestone 5 — zoup contract, hardening, and performance

Tasks:

1. Add representative cleaned-HTML contract fixtures and standalone ordinary-HTML cases.
2. Exercise shell syntax payloads as inert text, numeric injection attempts, literal pattern characters, and load-time alias collisions.
3. Run with external command lookup unavailable; inspect runtime code for process creation, executable data loading, and hidden optional dependencies.
4. Run deterministic malformed-input mutation cases under a timeout supplied by the development harness; assert bounded termination/statuses rather than inventing expected Markdown for random input.
5. Benchmark cold library load, first conversion/entity initialization, and warm conversions separately; optimize measured hotspots without changing behavior.
6. Record corpus bytes, output bytes, elapsed time, peak memory, and a fact-preservation checklist. Measure tokens only with an optional named external tokenizer.

Acceptance: all semantic, shell-hygiene, resource, and runtime-purity checks pass; the benchmark report exists and identifies any unmet performance target. Optional zoup checks remain clearly marked until an actual zoup API/version is available.

### Milestone 6 — Release readiness

Tasks:

1. Complete README, installation/usage, supported behavior/deviations, contribution/testing instructions, data provenance, and benchmark report.
2. Select and document the project license; verify that vendored data notices are retained.
3. Run mandatory checks on Zsh 5.9 and the current stable development environment. Add CI if the repository's eventual hosting environment supports it.
4. Verify the CLI and sourceable library from outside the checkout directory with the installed layout.
5. Review the completion checklist below against artifacts and actual results.

Acceptance: a v1 candidate satisfies every mandatory completion criterion. Implementing this plan does not by itself authorize publishing a release or choosing a hosting destination.

## 11. Verification strategy

### 11.1 Golden and component fixtures

Store each case with input HTML, exact expected Markdown bytes, expected status, and expected diagnostic categories/offsets when applicable. The Zsh runner compares exact data including trailing newlines; command substitution alone cannot do that. Use builtin reads and comparisons that retain EOF/newline information.

Required fixture groups:

- Empty input, whitespace-only input, missing final LF, fragments, complete documents, and BOM.
- Quoted/unquoted attributes; embedded delimiters; mixed case; duplicate attributes; void and non-void self-closing syntax.
- Comments, declarations, script/style, template nesting, text-only contexts, unknown elements, and retained hidden/navigation text.
- Named references, two-code-point references, numeric references, unknown names, required semicolons, C1 remapping, non-recursive decoding, and invalid code points.
- UTF-8 ASCII/non-ASCII/emoji/combining text; overlong sequences, isolated continuations, surrogate encodings, NUL, and disallowed controls.
- Inline boundaries with and without spaces; adjacent blocks; HTML ASCII versus Unicode whitespace; hard breaks.
- Literal Markdown punctuation and line-start markers; links/images with delimiters and non-clickable fallbacks.
- Empty/space-boundary/nested emphasis; code containing backticks, fence runs, tabs, blank lines, leading LF, and trailing spaces.
- Nested lists/quotes/code, ordered starts/item values/reversed numbering, orphan items, and every recovery rule in tolerant and strict modes.
- Headerless/headered simple tables; pipes; captions; empty cells; uneven widths; row/column spans; nested tables; multiline/block-content fallbacks.
- Form textual values, definition lists, details bodies, and foreign-element fallback text.
- Each resource limit at the boundary and one unit beyond; large comments/raw text; limits inside nested captures.

Golden outputs must be reviewed for meaning. Generating expected Markdown from the implementation under test is not sufficient. Add an optional independent CommonMark/GFM parsing check for tricky Markdown fixtures; it must not become a production dependency.

### 11.2 Shell integration

Run noninteractive checks with `zsh -df`, and parse every shipped script with `zsh -f -n`. Repeat function calls with `SH_WORD_SPLIT`, `KSH_ARRAYS`, `GLOB_SUBST`, and other relevant caller options enabled. Test aliases defined before sourcing, including names used by the loader.

Snapshot and compare options, traps, aliases, locale variables, `IFS`, cwd, `path`, `fpath`, and unrelated parameters around loading, successful calls, and failed calls. Check owned descriptor cleanup, lazy-data initialization failure, repeated sourcing, and no accidental globals. Library-owned functions/metadata are the documented additions.

Test missing/unreadable files, paths containing spaces/newlines/glob characters, leading-dash paths, empty/unterminated input, stdin pipes, and output-write failures. Use isolated shell processes for destructive option/descriptor scenarios. Tests must assert observable behavior, not merely mirror helper implementation details.

### 11.3 Runtime purity

Invoke the already-selected Zsh executable with `PATH` pointing to an empty directory and run library loading plus conversions from files and stdin. Use builtins and absolute trusted paths in this test setup. Review calls that could fork or execute external commands even if `PATH` is empty, including absolute executable paths and process substitution. The production code must not hide external work in aliases, user startup files, or first-run data generation.

### 11.4 Preservation evidence

For the representative corpus, list required facts explicitly: headings, sentences, code bytes, link destinations, list membership/order, and table values. Verify them against reviewed expected Markdown. Whitespace-normalized text comparison can supplement this checklist but cannot replace relationship checks.

Byte-size reduction is a representation metric. Optional token comparisons must record tokenizer name/version and distinguish ordinary HTML, zoup-cleaned HTML, and Markdown. Do not attribute zoup's cleanup savings to the Markdown converter.

## 12. Benchmark protocol and targets

Use committed synthetic or appropriately attributed offline inputs: long prose, many short tags, nested structures, code-heavy documentation, tables, entity-heavy text, and discarded script/style bodies. Generate size variants around 10 KiB, 100 KiB, 1 MiB, and the 4 MiB input limit. Record exact byte counts because generated variants will not always hit the nominal size.

For each case record environment, Zsh version, CPU/OS, input/output size, cold-load time, first-conversion time, warm median and p95 from at least 20 runs, and peak memory from an optional development measurement tool. Avoid network access during measurements. Include both the CLI startup path and repeated function calls in one shell.

Initial engineering targets on a documented developer machine:

- Warm 100 KiB typical prose/markup conversion: median no greater than 1 second.
- Warm 1 MiB typical prose/markup conversion: median no greater than 10 seconds.
- For the same synthetic document family, a 10× input increase should generally stay below 15× warm runtime after accounting for measurement noise. This is a regression signal, not a complexity proof.
- No external processes in library loading or the conversion loop.
- No growing retained state or descriptor count across 100 consecutive conversions, allowing the one-time immutable entity cache.

These are provisional performance targets, not evidence or release claims. Milestone 0 establishes a baseline; milestone 5 measures the complete converter. Missing a target requires profiling and either an implementation improvement or an explicit recorded change to the supported performance envelope before declaring v1 complete. No correctness tradeoff or external runtime dependency may be introduced simply to meet a timing target.

## 13. Main risks and implementation responses

| Risk | Response | Verification |
| --- | --- | --- |
| Shell scanning becomes quadratic | Advance offsets, process text spans, avoid repeated full-tail substitutions and accumulated joins | Size-series benchmarks and profiles |
| Loading is affected by caller aliases/options | Treat parse-time loading separately from function execution; establish safe native parsing | Adverse-option and preexisting-alias tests |
| Malformed HTML loses structure | Small explicit recovery list, strict mode, source offsets | Paired strict/tolerant fixtures |
| Escaping changes meaning or leaks raw HTML | Context-specific emitters and semantic fallbacks | Golden fixtures plus independent Markdown checks |
| Code/list/table captures use excessive memory | Bound temporary buffers and final output; iterative frames | Boundary fixtures and measured peak memory |
| Numeric data is interpreted as shell arithmetic | Validate bounded digit strings before accumulation; use no executable data | Payload and oversized-numeric fixtures |
| zoup removes required information | Explicit upstream contract and cleaned-HTML fixtures | Contract tests; actual versioned integration when available |
| Token reduction is overstated | Separate byte metrics, tokenizer metrics, and zoup cleanup savings | Reproducible report with preservation checklist |

## 14. Definition of complete

### 14.1 Concrete acceptance example

The following cleaned HTML must convert successfully in both ordinary and strict mode:

```html
<article>
  <h1>Shell tools</h1>
  <p>Use <code>zhtml2md</code> with the <a href="./guide">guide</a>.</p>
  <ul><li>Pure Zsh</li><li>Reusable library</li></ul>
  <pre><code class="language-zsh">print -r -- "hello"
</code></pre>
  <table>
    <tr><th>Name</th><th>Value</th></tr>
    <tr><td>Mode</td><td>HTML &amp; Markdown</td></tr>
  </table>
</article>
```

Expected output, with exactly one final LF:

````markdown
# Shell tools

Use `zhtml2md` with the [guide](./guide).

- Pure Zsh
- Reusable library

```zsh
print -r -- "hello"
```

| Name | Value |
| --- | --- |
| Mode | HTML & Markdown |
````

Adopt the example's simple formatting conventions in v1: one blank line between top-level blocks, unpadded pipe-table columns with one space inside each cell boundary, and backtick fences of at least three characters. Additional backticks are required only when content would conflict with the fence. Equivalent Markdown is insufficient for this fixture; output bytes must match. Other fixtures establish nested/fallback formatting before the relevant renderer is implemented.

### 14.2 Completion checklist

The implementation is complete only when all of the following are true:

- [ ] The sourceable library and CLI implement the public interface and return documented statuses.
- [ ] Production loading, reading, parsing, data loading, and rendering use pure Zsh builtins/code with no required native modules or external programs.
- [ ] Supported HTML and all rendering fallbacks are documented and covered by reviewed fixtures.
- [ ] Text order, semantic structure, code whitespace, destinations, numbering, and table cell data are preserved under the v1 contract.
- [ ] All specified strict/tolerant recovery cases are tested; no undocumented repair behavior remains.
- [ ] Input/output/tag/depth limits and encoding/control policies are enforced with no conversion stdout on pre-emission failure.
- [ ] The library preserves caller state across loading, repeated use, and failures, and cleans up owned descriptors.
- [ ] Parse checks and the mandatory offline suite pass on Zsh 5.9 and the development stable version.
- [ ] Runtime-purity checks pass with external commands unavailable.
- [ ] zoup interoperability is documented and contract-tested without requiring zoup to run standalone tests.
- [ ] A reproducible benchmark and preservation report are committed, with performance targets met or explicitly revised with evidence.
- [ ] Installation, usage, deviations, contributor instructions, licensing, and vendored data provenance are complete.
- [ ] Planned usage examples work from an installed copy outside the repository cwd.

The concrete final behavior is: a Zsh script can load `zhtml2md.zsh`, feed UTF-8 HTML from `zoup` or another source into `zhtml2md`, receive useful deterministic Markdown on stdout, distinguish failures by status, and continue with its original shell environment intact. The converter provides documented limits and fidelity instead of relying on an external implementation or claiming browser parity.
