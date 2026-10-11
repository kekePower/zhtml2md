# zoup / zhtml2md interoperability corpus

These five synthetic cases are authored here; no external article copyrights
or network fetches are involved. Each `.source.html` has independently
reviewed `.source.md`, `.clean.html` and `.md` expectations. The mandatory
suite verifies conversion of source and agreed cleaned HTML separately.

The pairs also pass against **zoup 0.1.0**, checkout commit
`b9dd8c07570347fa0cfa73b3bd9219eb1fd12e6d`, on Zsh 5.8 and 5.9.2, using its scalar API:

```zsh
fpath=( /path/to/zoup/functions "${fpath[@]}" )
autoload -Uz zoup
local REPLY
zoup clean -- "$html"
# REPLY is the cleaned HTML. Feed it to zhtml2md via a file or stdin.
```

Reproduce with `zsh -df tests/optional-zoup.zsh /path/to/zoup`. Without a path
that script explicitly skips. zoup is never required by standalone tests.
The optional check compares actual cleaned bytes to the agreed clean fixture
and then checks Markdown bytes, catching upstream API/policy changes.

| Case | Facts required in cleaned Markdown | Source-only information |
| --- | --- | --- |
| article | Field notes heading; guide text and `./guide`; Pressure chart description; no script text | zoup replaces the image with alt text, removing `chart.png` before conversion |
| lists | Steps heading; literal 4 and 8 labels; Build/Test nesting; Ship follows Build | Presentation class removed |
| tables | Measurements caption; Name/Value headers; Mode/HTML & Markdown cells; rowspan=0 once | Presentation class removed |
| code | Exact `print` line, tab, double spaces, literal `<tag>`, final code LF | zoup removes `language-zsh`; direct source conversion retains the hint |
| boundaries | Home navigation; hidden paragraph retained; `ab` adjacency and `c d` space; NBSP, é and emoji; closed details body retained | Boolean attributes canonicalize to empty quoted values |

No cleanup savings are credited to the Markdown converter. It cannot recover
information removed upstream. This validates this particular API/version;
future zoup versions should run the same optional check.
