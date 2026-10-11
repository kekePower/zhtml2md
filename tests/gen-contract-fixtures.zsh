#!/usr/bin/env zsh
# Synthetic source/clean pairs and expectations authored from the contract.
'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r dir=${${(%):-%N}:A:h}/contracts
command mkdir -p -- "$dir"
_zc_write() {
  builtin printf '%s' "$2" > "$dir/$1.source.html"
  builtin printf '%s' "$3" > "$dir/$1.clean.html"
  builtin printf '%s' "$4" > "$dir/$1.md"
  builtin printf '%s' "$5" > "$dir/$1.source.md"
}
_zc_write article '<article class="story"><h1>Field notes</h1><p>Read the <a href="./guide">guide</a>. <img src="chart.png" alt="Pressure chart"></p><script>discard()</script></article>' \
  '<article><h1>Field notes</h1><p>Read the <a href="./guide">guide</a>. Pressure chart</p></article>' \
  $'# Field notes\n\nRead the [guide](./guide). Pressure chart\n' \
  $'# Field notes\n\nRead the [guide](./guide). ![Pressure chart](chart.png)\n'
_zc_write lists '<section class="x"><h2>Steps</h2><ol start="4" reversed><li>Build<ul><li>Test</li></ul></li><li value="8">Ship</li></ol></section>' \
  '<section><h2>Steps</h2><ol start="4" reversed=""><li>Build<ul><li>Test</li></ul></li><li value="8">Ship</li></ol></section>' \
  $'## Steps\n\n- 4\\. Build\n  \n  - Test\n\n- 8\\. Ship\n' \
  $'## Steps\n\n- 4\\. Build\n  \n  - Test\n\n- 8\\. Ship\n'
_zc_write tables '<table class="grid"><caption>Measurements</caption><tr><th>Name</th><th>Value</th></tr><tr><td rowspan="0">Mode</td><td>HTML &amp; Markdown</td></tr></table>' \
  '<table><caption>Measurements</caption><tr><th>Name</th><th>Value</th></tr><tr><td rowspan="0">Mode</td><td>HTML &amp; Markdown</td></tr></table>' \
  $'Measurements\n\n1. Row 1\n   \n   1. Header: Name\n   2. Header: Value\n\n2. Row 2\n   \n   1. Cell (rowspan=0): Mode\n   2. Cell: HTML & Markdown\n' \
  $'Measurements\n\n1. Row 1\n   \n   1. Header: Name\n   2. Header: Value\n\n2. Row 2\n   \n   1. Cell (rowspan=0): Mode\n   2. Cell: HTML & Markdown\n'
_zc_write code $'<main><pre><code class="language-zsh">print -r -- "x"\n\t# literal &lt;tag&gt;\n</code></pre></main>' \
  $'<main><pre><code>print -r -- "x"\n\t# literal &lt;tag&gt;\n</code></pre></main>' \
  $'```\nprint -r -- "x"\n\t# literal <tag>\n```\n' \
  $'```zsh\nprint -r -- "x"\n\t# literal <tag>\n```\n'
_zc_write boundaries '<nav>Home</nav><p hidden>a<span>b</span> c <span>d</span>&nbsp;é😀</p><details><summary>More</summary><p>Kept</p></details>' \
  '<nav>Home</nav><p hidden="">a<span>b</span> c <span>d</span>&nbsp;é😀</p><details><summary>More</summary><p>Kept</p></details>' \
  $'Home\n\nab c d\xc2\xa0é😀\n\nMore\n\nKept\n' \
  $'Home\n\nab c d\xc2\xa0é😀\n\nMore\n\nKept\n'
builtin print -r -- 'wrote 5 source/clean contract pairs'
