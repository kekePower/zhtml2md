# Supported HTML and deviations

The definitive contract is docs/implementation-plan.md, sections 5-7.
This guide will document the accepted HTML subset, the rendering rules,
and every deliberate deviation from browser behavior as each milestone
lands.

## Current implementation status

Milestones 0-3 are complete. Implemented today:

- Input handling: UTF-8 validation with an optional initial BOM;
  rejection of NUL, invalid UTF-8, and C0/DEL control bytes other than
  HT/LF/CR (status 3). CRLF and lone CR normalize to LF.
- Public HTML parsing, reference decoding, structural recovery and Markdown
  rendering. Nonempty output ends in exactly one final LF; all output remains
  buffered until parsing and rendering succeed.
- Paragraphs/block containers, ATX headings, hard breaks and thematic breaks;
  emphasis and link/image syntax with documented plain/code fallbacks.
- Inline/fenced code, language hints, textarea/plaintext, textual input values,
  option child labels as list items, details/summary and definition lists.
- Outside code, ASCII whitespace collapses to pending spaces. Unicode/NBSP
  text remains intact. Unknown inline elements unwrap without invented space.
- Empty or whitespace-only input succeeds with zero output bytes.

Nested list numbering, continuation indentation and hierarchy, plus simple
and complex table representations, remain milestone 4. This development
version retains their text with paragraph boundaries but does not preserve
those relationships or span metadata in Markdown. Blockquote line prefixes
are already used by the definition-list renderer; list/quote/table combinations
still need milestone 4 verification.

The decoder loads all 2,125 semicolon-terminated WHATWG names
as validated literal data, including two-code-point values. Decimal and
hexadecimal numeric references use bounded textual validation, U+FFFD
replacement for zero/surrogates/out-of-range values, and HTML C1 remapping.
Unknown, malformed, and semicolon-less forms stay literal; decoding is
one pass. Decoded forbidden controls return status 3 at the reference's
original byte offset. CR normalization is the renderer's responsibility.
The parser applies these rules only at eligible text/attribute boundaries.
Public conversion uses these rules for eligible text and attributes.

## Current Markdown rules and fallbacks

- Prose, headings and labels escape literal backslashes, backticks,
  `* _ [ ] < > & # + - ! ( ) | { }`. Numeric list punctuation is escaped
  even when split over inline elements. This conservative policy prevents
  source punctuation from becoming Markdown syntax. Generated markers and
  code use their own contexts; there is no final global escape pass.
- Ampersands are escaped after one HTML entity pass, preserving literal
  text such as `&copy;` produced by `&amp;copy;`. Code bypasses Markdown
  entity expansion naturally.
- Emphasis retains all child text. Empty captures emit no markers and move
  boundary spaces outside. ASCII word edges use markers; punctuation/Unicode
  edges, nested emphasis, and adjacent marker collisions use plain text.
- Links preserve decoded relative/query/scheme data without fetching or
  scheme filtering. Backslashes, ampersands, angles and parentheses are
  escaped in destinations; spaces use angle-delimited destinations. Empty
  labels use destination text, and absent/empty href unwraps children.
- LF/CR/HT in a destination uses a non-clickable label plus a code
  representation; a newline needs a fence. Links with child blocks or nested
  links also use the label/code fallback. Image descriptions/destinations
  follow equivalent rules. Missing src keeps description text; missing alt
  keeps the destination, using code for its otherwise lossy whitespace.
- Single-line code uses a backtick run longer than all contained runs, with
  boundary padding when needed. Adjacent spans merge their literal contents
  into one span. Multiline content uses a fence; no tabs, blank lines, trailing
  spaces or existing terminal newlines are stripped. Nonempty fenced content
  without a terminal LF gains the framing LF before its closing fence. Empty
  fenced content does not gain an invented blank content line.
- `pre` removes at most one normalized initial LF immediately after its
  opening tag. A LF after a nested opening `code` is retained. A valid
  `language-*` class token contains 1-32 ASCII letters/digits/`_+-`; the first
  valid hint is used, and invalid tokens are ignored.
- Heading whitespace and br collapse to spaces. A heading containing a
  fenced-code fallback preserves its child blocks without ATX markers.
- Definition terms remain paragraphs; descriptions prefix every rendered
  line with `> `. Details retain summary and body regardless of open state.
  Inputs preserve supplied textual values and explicit button values, omit
  hidden/password/non-text state, and invent no default button label.

## Verified parser component

- Tag/attribute names fold ASCII case; quoted `>`/`<` remain inside
  values. Duplicate attributes retain the first value. Unquoted values
  include `/`: `<img src=x/>` has `src=x/`.
- Void elements create no frames. A lexical self-closing slash on a
  non-void element does not close it, including `<div/>` and `<script/>`.
- Comments end at literal `-->`. Other `<!`/`<?` declarations end at the
  first unquoted `>`. Full browser bogus comments and XML internal
  subsets are outside the contract.
- `script`/`style` use raw closing-tag recognition; script-data escapes
  are not implemented. `title`/`textarea` are text-only. Closing names
  must match and have an ASCII whitespace, slash, or `>` boundary;
  unfinished raw closing candidates remain part of the body.
- `head`, `title`, `script`, `style`, and nested `template` content are
  discarded. Comments and raw/text-only rules remain active inside
  templates. `noscript`, hidden/navigation text, and unknown/foreign
  element children are retained. Raw discarded body payloads need only
  their source offsets, so the lexer does not copy them for the renderer.
- `textarea` references decode; `plaintext` consumes the rest as literal
  text without decoding. EOF normally terminates `plaintext`, even in
  strict mode. Outer open source frames still require EOF recovery.
- Iterative frames apply exactly the documented sibling, paragraph,
  misnesting, unmatched-end, orphan-item, unfinished-token and EOF repairs.
  Strict mode rejects the first repair. It validates this converter's
  simpler contract, including omitted end tags, rather than browser HTML
  conformance. Every orphan item warns; consecutive items share a
  synthetic list, which source end tags cannot match.
- Start/end recovery searches stop at discard owners. Paragraphs and list/
  table members inside a template cannot close retained outer frames or leak
  discarded children. An end tag can match the discard owner itself.
- List numbers and table spans are validated as bounded decimal text.
  Invalid values warn and lose their attribute so the renderer can use
  the documented default. Unknown attributes do not cause a repair.
- Tag candidates are bounded to 65,536 bytes, including unfinished tags;
  open source/discard/synthetic frames are bounded to 256. Large comments,
  raw bodies and text remain governed by the input limit.
- Code whitespace, CRLF and original byte offsets are preserved at the
  parser boundary. The renderer normalizes line endings without changing
  diagnostic offsets. Numbering and table rendering remain milestone 4.

Public rendering retains these verified deviations:

- The script/style raw-text scan ends at a matching closing end tag; the
  full browser script-data escape algorithm is not implemented.
- A self-closing slash on a non-void element (for example `<div/>`) does
  not close the element.
- v1 requires the semicolon on all character references; legacy
  semicolon-less forms are outside the contract.
- Strict mode validates this converter's documented repair list, not
  HTML-standard conformance.
