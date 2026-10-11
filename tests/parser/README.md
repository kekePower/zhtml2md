# Tokenizer and frame fixtures

`runner.zsh tokens FILE [STRICT]` records lexical events; `events` records
semantic frame events. Both use the same runtime components and validate
input first. The recorder buffers its log and emits nothing on failure.
No fixture expectations come from the component under test.

`fixtures/NAME` has `.html`, `.mode`, `.strict`, `.events`, `.status`, and
`.stderr`. Regenerate the 80 reviewed fixtures with
`zsh -df tests/gen-parser-fixtures.zsh`. Each valid case also runs in strict
mode; each repair case has a strict first-error counterpart.

Lexical lines contain kind, name (`-` when absent), byte range, lexical
self-closing/literal flags and quoted raw payload. Attribute lines add
the raw value's original offset. Discarded script/style/title bodies have
only a source range, without an allocated payload. Comment/declaration
payloads are also omitted.

Frame lines contain kind, name, ID/parent ID, byte range, discard/synthetic/
literal flags and quoted decoded payload. Attributes are recorded in
sorted name order for comparison, while decoding and numeric validation
use source order. IDs are monotonic and do not imply retained DOM nodes.
Frame closes from repair have a zero-width range at the trigger; EOF
closes use the input end. All ranges include a BOM and have exclusive ends.

Quoting is a test-only comparison format. It is never evaluated, and the
runtime exchanges tokens and events as local structured parameters.
Markdown output belongs to tests/fixtures/m3-* fixtures, not these files.
