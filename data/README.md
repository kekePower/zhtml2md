# data/entities.tsv - vendored named character reference data

## Provenance

- Upstream: WHATWG HTML Standard, "Named character references"
  - Human page: https://html.spec.whatwg.org/multipage/named-characters.html
  - Machine data: https://html.spec.whatwg.org/entities.json
- Retrieved: 2026-10-10
- Retrieved file: 145,897 bytes, sha256
  `d741d877ac77c4194c4ad526b5b4a19aef8dfe411ab840a466891cdbb9f362e6`
- Upstream license: the WHATWG HTML Standard is licensed under CC BY 4.0
  (https://html.spec.whatwg.org/#ipr and the LICENSE header of the
  standard). The full upstream notice is retained in
  `data/LICENSE.WHATWG` (CC BY 4.0 for the data; BSD 3-Clause for portions
  incorporated into source code). See also the project NOTICE. Attribution: "HTML Standard, Web Hypertext Application
  Technology Working Group (WHATWG), https://html.spec.whatwg.org/".

## Contents

The upstream JSON contains 2,231 entries, of which 106 are legacy names
without a terminating semicolon. zhtml2md v1 requires the semicolon
(docs/implementation-plan.md 7.6), so this file holds exactly the 2,125
semicolon-terminated names, sorted by name.

Format, one entry per line, tab-separated, ASCII, LF endings:

```text
name<TAB>hex1[<TAB>hex2]
```

- `name`: the reference name without `&` and `;` (ASCII alphanumeric)
- `hex1`: first Unicode scalar value, uppercase hexadecimal
- `hex2`: optional second scalar value, uppercase hexadecimal

The runtime parses this file as plain data (tab splitting plus field
validation); it is never sourced or evaluated as shell code. A malformed
file is an initialization error, not something to repair.

The loader and decoder are now implemented in `lib/_zhtml2md_entities.zsh`.
They initialize the cache lazily, validate all rows before publishing it,
and close the owned descriptor on success and failure. Component fixtures
cover every named value independently. The component parser now chooses
eligible text/attribute contexts. The public renderer consumes decoded
parser events; references are expanded once before context-specific escaping.

## Regeneration

```sh
tools/gen-entities                  # download from the upstream URL
tools/gen-entities entities.json    # or use a saved local copy
```

Development-only tooling (python3); never used at runtime. The tool
verifies the expected entry count (2,125) and checks every entry's
`characters` field against its `codepoints` before writing. If the
upstream count changes deliberately, update EXPECTED_SEMICOLON_ENTRIES
in the tool and this README in the same commit, and re-record the
retrieval date and checksum above.
