#!/usr/bin/env zsh
# Hand-authored milestone 4 expectations; never captured converter output.
'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r dir=${${(%):-%N}:A:h}/fixtures
local -i count=0
_zs_case() {
  local _name=m4-$1 _html=$2 _md=$3 _mode
  for _mode in tolerant strict; do
    local _base=$dir/$_name-$_mode
    builtin printf '%s' "$_html" > "$_base.html"
    builtin printf '%s' "$_md" > "$_base.md"
    builtin printf '%s' 0 > "$_base.status"
    [[ $_mode == strict ]] && builtin printf '%s\n' --strict > "$_base.opts"
    (( ++count ))
  done
}
_zs_case ul '<ul><li>A</li><li>B</li></ul>' $'- A\n- B\n'
_zs_case empty-items '<ul><li></li><li> </li><li>C</li></ul>' $'-\n-\n- C\n'
_zs_case ol '<ol><li>A</li><li>B</li></ol>' $'1. A\n2. B\n'
_zs_case zero '<ol start="0"><li>A</li><li>B</li></ol>' $'0. A\n1. B\n'
_zs_case width '<ol start="9"><li>A<p>B</p></li><li>C<p>D</p></li></ol>' $'9. A\n   \n   B\n\n10. C\n    \n    D\n'
_zs_case loose '<ul><li><p>A</p><p>B</p></li><li>C</li></ul>' $'- A\n  \n  B\n\n- C\n'
_zs_case nested '<ul><li>A<ol start="3"><li>B</li><li>C</li></ol>D</li><li>E</li></ul>' $'- A\n  \n  3. B\n  4. C\n  \n  D\n\n- E\n'
_zs_case value-consecutive '<ol start="3"><li>A</li><li value="4">B</li></ol>' $'3. A\n4. B\n'
_zs_case value-gap '<ol><li>A</li><li value="7">B</li><li>C</li></ol>' $'- 1\\. A\n- 7\\. B\n- 8\\. C\n'
_zs_case negative '<ol start="-2"><li>A</li><li>B</li><li>C</li></ol>' $'- -2\\. A\n- -1\\. B\n- 0\\. C\n'
_zs_case reverse '<ol reversed><li>A</li><li>B</li><li>C</li></ol>' $'- 3\\. A\n- 2\\. B\n- 1\\. C\n'
_zs_case reverse-value '<ol reversed="false" start="5"><li>A</li><li value="9">B</li><li>C</li></ol>' $'- 5\\. A\n- 9\\. B\n- 8\\. C\n'
_zs_case wide '<ol start="999999999"><li>A</li><li>B</li></ol>' $'- 999999999\\. A\n- 1000000000\\. B\n'
_zs_case quote '<blockquote><p>A</p><blockquote><p>B</p><p>C</p></blockquote><p>D</p></blockquote>' $'> A\n> \n> > B\n> > \n> > C\n> \n> D\n'
_zs_case quote-list '<blockquote><ul><li>A</li><li><pre>x\ny</pre></li></ul></blockquote>' $'> - A\n> - ```\n>   x\\ny\n>   ```\n'
_zs_case list-code $'<ol start="10"><li>A<pre> x\n\ty\n</pre></li></ol>' $'10. A\n    \n    ```\n     x\n    \ty\n    ```\n'
_zs_case wrapped-items '<ol reversed><em>before<li>A</li>between<li>B</li>after</em></ol>' $'before\n\n- 2\\. A\n\nbetween\n\n- 1\\. B\n\nafter\n'
_zs_case link-list '<a href="x"><ul><li>A</li></ul></a>' $'- A\n\n`x`\n'
_zs_case wrapper-link-items '<ul><a href="x"><li>A</li></a></ul>' $'- A\n\n`x`\n'
_zs_case table '<table><tr><th>A</th><th>B</th></tr><tr><td>C</td><td>D</td></tr></table>' $'| A | B |\n| --- | --- |\n| C | D |\n'
_zs_case no-header '<table><tr><td>A</td><td>B</td></tr></table>' $'|  |  |\n| --- | --- |\n| A | B |\n'
_zs_case mixed-header '<table><tr><th>A</th><td>B</td></tr></table>' $'|  |  |\n| --- | --- |\n| A | B |\n'
_zs_case rowgroups '<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>B</td></tr></tbody><tfoot><tr><td>C</td></tr></tfoot></table>' $'| A |\n| --- |\n| B |\n| C |\n'
_zs_case empty-table '<table></table><table><tr></tr></table>' ''
_zs_case caption '<table><tr><th>A</th></tr><tr><td>B</td></tr><caption>Caption</caption></table>' $'Caption\n\n| A |\n| --- |\n| B |\n'
_zs_case empty-caption '<table><caption>C</caption></table>' $'C\n'
_zs_case empty-cells '<table><tr><th></th><th>B</th></tr><tr><td></td><td></td></tr></table>' $'|  | B |\n| --- | --- |\n|  |  |\n'
_zs_case spans '<table><tr><th rowspan="0" colspan="2">A</th><td>B</td></tr></table>' $'1. Row 1\n   \n   1. Header (rowspan=0, colspan=2): A\n   2. Cell: B\n'
_zs_case maximum-spans '<table><tr><td rowspan="65534" colspan="1000">A</td></tr></table>' $'1. Row 1\n   \n   1. Cell (rowspan=65534, colspan=1000): A\n'
_zs_case ragged '<table><tr><th>A</th><th>B</th></tr><tr><td>C</td></tr></table>' $'1. Row 1\n   \n   1. Header: A\n   2. Header: B\n\n2. Row 2\n   \n   1. Cell: C\n'
_zs_case blocks '<table><tr><td><p>A</p><p>B</p></td></tr></table>' $'1. Row 1\n   \n   1. Cell:\n      \n      A\n      \n      B\n'
_zs_case hardbreak '<table><tr><td>A<br>B</td></tr></table>' $'1. Row 1\n   \n   1. Cell:\n      \n      A  \n      B\n'
_zs_case multiline-code $'<table><tr><td><code>x\ny</code></td></tr></table>' $'1. Row 1\n   \n   1. Cell:\n      \n      ```\n      x\n      y\n      ```\n'
_zs_case nested-table '<table><tr><td><table><tr><th>A</th></tr></table></td></tr></table>' $'1. Row 1\n   \n   1. Cell:\n      \n      | A |\n      | --- |\n'
_zs_case table-list '<ul><li><table><tr><th>A</th></tr></table></li></ul>' $'- | A |\n  | --- |\n'
_zs_case table-quote '<blockquote><table><tr><td>A</td></tr></table></blockquote>' $'> |  |\n> | --- |\n> | A |\n'
_zs_case cell-format '<table><tr><td><em>A</em> <a href="x">B</a> <code>C</code></td></tr></table>' $'|  |\n| --- |\n| *A* [B](x) `C` |\n'
_zs_case pipes '<table><tr><td>A|B <code>C|D</code></td></tr></table>' $'|  |\n| --- |\n| A\\|B `C\\|D` |\n'
_zs_case code-slash-pipe '<table><tr><td><code>a\|b</code></td></tr></table>' $'|  |\n| --- |\n| `a\\\\|b` |\n'
_zs_case escaped-ticks '<table><tr><td>`a|b` <code>`c|d`</code></td></tr></table>' $'|  |\n| --- |\n| \\`a\\|b\\` `` `c\\|d` `` |\n'
_zs_case pipe-url '<table><tr><td><a href="a|b`c">X</a><img alt="Y|Z" src="i|j"></td></tr></table>' $'|  |\n| --- |\n| [X](a\\|b\\`c)![Y\\|Z](i\\|j) |\n'
_zs_case amp '<table><tr><td>&amp;lt; &amp; A &amp; B &notanentity;</td></tr></table>' $'|  |\n| --- |\n| \\&lt; & A & B \\&notanentity; |\n'
_zs_case table-note '<table>before<tr><td>A</td></tr>after</table>' $'before\n\n1. Row 1\n   \n   1. Cell: A\n\nafter\n'
_zs_case row-note '<table><tr>before<td>A</td>after</tr></table>' $'1. Row 1\n   \n   before\n   \n   1. Cell: A\n   \n   after\n'
_zs_case orphan-cell '<table><td>A</td></table>' $'1. Row 1\n   \n   1. Cell: A\n'
_zs_case standalone-cell '<td>A</td><th rowspan="2">B</th>' $'Cell: A\n\nHeader (rowspan=2): B\n'
_zs_case unicode '<ul><li>café&nbsp;漢字</li></ul><table><tr><td>😀</td></tr></table>' $'- café\xc2\xa0漢字\n\n|  |\n| --- |\n| 😀 |\n'
_zs_case acceptance $'<h1>Shell tools</h1>\n<p>Use <code>zhtml2md</code> with the <a href="./guide">guide</a>.</p>\n<ul><li>Pure Zsh</li><li>Reusable library</li></ul>\n<pre><code class="language-zsh">print -r -- "hello"\n</code></pre>\n<table><tr><th>Name</th><th>Value</th></tr><tr><td>Mode</td><td>HTML &amp; Markdown</td></tr></table>' $'# Shell tools\n\nUse `zhtml2md` with the [guide](./guide).\n\n- Pure Zsh\n- Reusable library\n\n```zsh\nprint -r -- "hello"\n```\n\n| Name | Value |\n| --- | --- |\n| Mode | HTML & Markdown |\n'
_zs_case table-interleaved '<table><tr><td>A</td></tr>note<tr><td>B</td></tr></table>' $'1. Row 1\n   \n   1. Cell: A\n\nnote\n\n2. Row 2\n   \n   1. Cell: B\n'
_zs_case list-quotes '<ul><li><blockquote><p>A</p><p>B</p></blockquote></li><li>C</li></ul>' $'- > A\n  > \n  > B\n- C\n'
# Diagnostics are reviewed against the parser contract fixtures.
_zs_repair() {
  local _name=m4-$1 _html=$2 _md=$3 _err=$4 _strict_err=$5
  builtin printf '%s' "$_html" > "$dir/$_name-tolerant.html"
  builtin printf '%s' "$_md" > "$dir/$_name-tolerant.md"
  builtin printf '%s' 0 > "$dir/$_name-tolerant.status"
  builtin printf '%s' "$_err" > "$dir/$_name-tolerant.stderr"
  builtin printf '%s' "$_html" > "$dir/$_name-strict.html"
  builtin printf '%s' '' > "$dir/$_name-strict.md"
  builtin printf '%s' 3 > "$dir/$_name-strict.status"
  builtin printf '%s\n' --strict > "$dir/$_name-strict.opts"
  builtin printf '%s' "$_strict_err" > "$dir/$_name-strict.stderr"
  (( count += 2 ))
}
_zs_repair implicit-li '<ul><li>a<li>b</li></ul>' $'- a\n- b\n' \
  $'zhtml2md: implicit-li-close at byte 9: new item closes previous item\n' \
  $'zhtml2md: implicit-li-close at byte 9: new item closes previous item\n'
_zs_repair orphan '<li>a</li> <li>b</li>x' $'- a\n- b\n\nx\n' \
  $'zhtml2md: orphan-li at byte 0: item uses synthetic unordered list\nzhtml2md: orphan-li at byte 11: item uses synthetic unordered list\n' \
  $'zhtml2md: orphan-li at byte 0: item uses synthetic unordered list\n'
_zs_repair implicit-table '<table><tr><td>a<td>b<tr><th>c</th></tr></table>' \
  $'1. Row 1\n   \n   1. Cell: a\n   2. Cell: b\n\n2. Row 2\n   \n   1. Header: c\n' \
  $'zhtml2md: implicit-table-close at byte 16: new table member closes previous sibling\nzhtml2md: implicit-table-close at byte 21: new table member closes previous sibling\n' \
  $'zhtml2md: implicit-table-close at byte 16: new table member closes previous sibling\n'
_zs_repair invalid-spans '<table><tr><td colspan=0 rowspan=65535>x</td></tr></table>' $'|  |\n| --- |\n| x |\n' \
  $'zhtml2md: invalid-numeric-attribute at byte 23: invalid colspan attribute; using default\nzhtml2md: invalid-numeric-attribute at byte 33: invalid rowspan attribute; using default\n' \
  $'zhtml2md: invalid-numeric-attribute at byte 23: invalid colspan attribute; using default\n'
builtin print -r -- "wrote $count structure fixtures"
