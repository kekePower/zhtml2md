# zoup integration

zhtml2md runs independently. zoup is an optional upstream cleaner, responsible
for selection and cleanup rather than Markdown conversion. Neither converter
fetches the input for this pipeline.

```zsh
fpath=( /path/to/zoup/functions "${fpath[@]}" )
autoload -Uz zoup
source /path/to/zhtml2md/zhtml2md.zsh

local REPLY cleaned_html
if zoup clean -- "$html"; then
  cleaned_html=$REPLY
  builtin printf '%s' "$cleaned_html" | zhtml2md --strict
fi
```

Use `local` inside a function; use `typeset` for those variables at top level.
The scalar cleaner API avoids its optional stdin module. The pipeline producer
uses a Zsh builtin; its pipe is caller orchestration outside the converter.
For ordinary HTML, call zhtml2md directly with a file or stdin.

The API above and five synthetic original/cleaned/Markdown pairs are verified
against zoup **0.1.0**, commit
`b9dd8c07570347fa0cfa73b3bd9219eb1fd12e6d`, on Zsh 5.8 and 5.9.2. Run
`zsh -df tests/optional-zoup.zsh /path/to/zoup` for the optional real check.
The mandatory offline suite checks the agreed cleaned HTML without zoup.

The contract corpus and fact checklist are in tests/contracts/README.md.
zoup 0.1.0 turns images into alt text and removes classes, including code
language hints. Its boolean attributes canonicalize to empty quoted values.
zhtml2md retains destinations/hints when supplied directly, but cannot recover
anything removed upstream. Navigation and hidden text remain if retained;
this converter does no CSS analysis or article extraction.

Compare original HTML, actual cleaned HTML and Markdown separately. Report
cleanup token changes as zoup's stage and conversion token changes as
zhtml2md's stage. The benchmark report includes those separate counts.
