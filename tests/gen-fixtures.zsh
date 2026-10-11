#!/usr/bin/env zsh
# tests/gen-fixtures.zsh - regenerate the golden fixtures.
#
# Development tool, pure Zsh. Fixtures are committed; regenerate after a
# deliberate behavior change and review the resulting bytes. Expected
# Markdown is authored here by hand from the contract, never copied from
# implementation output.

'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte
local LC_ALL=C

local -r dir=${${(%):-%N}:A:h}/fixtures
command mkdir -p -- "$dir"

local -a written=()

# name | input bytes | expected stdout | status | opts | stderr | via-stdin | no-input
_zf_write() {
  # NB: `status' is a special zsh parameter; the status argument is _st.
  local name=$1 input=$2 md=$3 _st=$4 opts=$5 err=$6 stdin=$7 noinput=$8
  builtin printf '%s' "$input" > "$dir/$name.html"
  builtin printf '%s' "$md"    > "$dir/$name.md"
  builtin printf '%s' "$_st" > "$dir/$name.status"
  if [[ -n $opts ]]; then
    builtin printf '%s\n' "$opts" > "$dir/$name.opts"
  else
    [[ -e $dir/$name.opts ]] && command rm -f -- "$dir/$name.opts"
  fi
  if [[ -n $err ]]; then
    builtin printf '%s' "$err" > "$dir/$name.stderr"
  else
    [[ -e $dir/$name.stderr ]] && command rm -f -- "$dir/$name.stderr"
  fi
  if [[ $stdin == stdin ]]; then
    : > "$dir/$name.stdin"
  else
    [[ -e $dir/$name.stdin ]] && command rm -f -- "$dir/$name.stdin"
  fi
  if [[ $noinput == noinput ]]; then
    : > "$dir/$name.noinput"
  else
    [[ -e $dir/$name.noinput ]] && command rm -f -- "$dir/$name.noinput"
  fi
  written+=( $name )
}

local help_text='usage: zhtml2md [--strict] [--] [FILE|-]
       zhtml2md --help
       zhtml2md --version

Convert UTF-8 HTML to compact, deterministic Markdown.
With no operand, or -, read standard input.

Options:
  --strict   fail on recoverable syntax defects instead of repairing
  --         end option parsing (allow paths beginning with -)
  --help     print this text and exit
  --version  print the version and exit

Status: 0 ok, 1 io/internal, 2 usage, 3 input rejected, 4 limit exceeded
'

# --- text slice (milestone 1) ------------------------------------------
_zf_write m1-empty            ''                        ''                0 '' '' ''
_zf_write m1-whitespace-only  $'  \t\n\n \n'            ''                0 '' '' ''
_zf_write m1-plain-text       $'Hello, world!\n'        $'Hello, world\\!\n' 0 '' '' ''
_zf_write m1-no-final-lf      'no trailing newline'     $'no trailing newline\n' 0 '' '' ''
_zf_write m1-crlf             $'a\r\nb\r\nc\r'          $'a b c\n'      0 '' '' ''
_zf_write m1-leading-blanks   $'\n\n\nstart\n'          $'start\n'        0 '' '' ''
_zf_write m1-trailing-blanks  $'end\n\n\n'              $'end\n'          0 '' '' ''
_zf_write m1-tab-preserved    $'a\tb\n'                 $'a b\n'         0 '' '' ''
_zf_write m1-unicode          $'caf\xc3\xa9 \xe2\x82\xac \xf0\x9f\x98\x80 \xe6\xbc\xa2\xe5\xad\x97\n' \
                              $'caf\xc3\xa9 \xe2\x82\xac \xf0\x9f\x98\x80 \xe6\xbc\xa2\xe5\xad\x97\n' 0 '' '' ''
_zf_write m1-bom              $'\xef\xbb\xbfbom text\n' $'bom text\n'     0 '' '' ''
_zf_write m1-stdin            $'from stdin\n'           $'from stdin\n'   0 '' '' stdin

# --- rejected input ------------------------------------------------------
_zf_write m1-reject-nul       $'ab\x00cd'  '' 3 '' \
  $'zhtml2md: forbidden-control at byte 2: NUL byte in input\n' ''
_zf_write m1-reject-bel       $'a\x07b'    '' 3 '' \
  $'zhtml2md: forbidden-control at byte 1: forbidden control byte in input\n' ''
_zf_write m1-reject-del       $'a\x7fb'    '' 3 '' \
  $'zhtml2md: forbidden-control at byte 1: forbidden control byte in input\n' ''
_zf_write m1-invalid-utf8-ff  $'ab\xffcd'  '' 3 '' \
  $'zhtml2md: invalid-utf8 at byte 2: invalid UTF-8 leading byte\n' ''
_zf_write m1-invalid-utf8-overlong $'ab\xc0\x80cd' '' 3 '' \
  $'zhtml2md: invalid-utf8 at byte 2: invalid UTF-8 leading byte\n' ''
_zf_write m1-invalid-utf8-surrogate $'x\xed\xa0\x80' '' 3 '' \
  $'zhtml2md: invalid-utf8 at byte 1: invalid UTF-8 continuation byte\n' ''
_zf_write m1-invalid-utf8-truncated $'x\xe2\x82' '' 3 '' \
  $'zhtml2md: invalid-utf8 at byte 1: truncated UTF-8 sequence\n' ''
_zf_write m1-invalid-utf8-lone-cont $'\x80' '' 3 '' \
  $'zhtml2md: invalid-utf8 at byte 0: invalid UTF-8 leading byte\n' ''

# --- usage ---------------------------------------------------------------
_zf_write m1-usage-unknown-option '' '' 2 '--bogus' '' '' noinput
builtin printf '%s' \
"zhtml2md: usage: unknown option: --bogus
usage: zhtml2md [--strict] [--] [FILE|-]
       zhtml2md --help
       zhtml2md --version
" > "$dir/m1-usage-unknown-option.stderr"

_zf_write m1-usage-two-files '' '' 2 'second-input.html' \
  '' ''
builtin printf '%s' \
"zhtml2md: usage: at most one input file may be given
usage: zhtml2md [--strict] [--] [FILE|-]
       zhtml2md --help
       zhtml2md --version
" > "$dir/m1-usage-two-files.stderr"

_zf_write m1-usage-help-strict '' '' 2 '--help --strict' '' '' noinput
builtin printf '%s' \
"zhtml2md: usage: --help/--version cannot be combined with conversion arguments
usage: zhtml2md [--strict] [--] [FILE|-]
       zhtml2md --help
       zhtml2md --version
" > "$dir/m1-usage-help-strict.stderr"

_zf_write m1-help '' "$help_text" 0 '--help' '' '' noinput
_zf_write m1-version '' $'zhtml2md 0.1.0-dev\n' 0 '--version' '' '' noinput
_zf_write m1-dashdash $'dash text\n' $'dash text\n' 0 '--' '' ''

# --- Markdown prose/inline/code (milestone 3), hand-authored bytes -------
_zf_write m3-adjacency '<p>a<span>b</span> a <span>b</span>c</p>' $'ab a bc\n' 0
_zf_write m3-ascii-whitespace $'<p>  a\t b\r\nc\n </p><p> d </p>' $'a b c\n\nd\n' 0
_zf_write m3-unicode '<p>café&nbsp;漢字&#x1F600;e&#x301;</p>' $'café\xc2\xa0漢字\xf0\x9f\x98\x80e\xcc\x81\n' 0
_zf_write m3-empty-blocks '<div><p> </p><p>A</p><section></section><p>B</p></div>' $'A\n\nB\n' 0
_zf_write m3-unknown '<custom><span>a</span><foreign>b</foreign></custom>' $'ab\n' 0
_zf_write m3-headings '<h1>One</h1><h2>Two</h2><h3>Three</h3><h4>Four</h4><h5>Five</h5><h6>Six</h6>' $'# One\n\n## Two\n\n### Three\n\n#### Four\n\n##### Five\n\n###### Six\n' 0
_zf_write m3-heading-lines $'<h2> a\nb<br>c <p>d</p>e </h2>' $'## a b c d e\n' 0
_zf_write m3-breaks '<p>a<br>b</p><hr><p>c</p>' $'a  \nb\n\n---\n\nc\n' 0
_zf_write m3-source-punctuation '<p># title *em* **b** _u_ [x](y) ![i](z) &lt;b&gt; | + - {x} `c` \</p>' $'\\# title \\*em\\* \\*\\*b\\*\\* \\_u\\_ \\[x\\]\\(y\\) \\!\\[i\\]\\(z\\) \\<b\\> \\| \\+ \\- \\{x\\} \\`c\\` \\\\\n' 0
_zf_write m3-source-blocks '<p>1. list</p><p><span>2</span>. item</p><p>3) item</p><p>---</p><p>&gt; quote</p>' $'1\\. list\n\n2\\. item\n\n3\\) item\n\n\\-\\-\\-\n\n\\> quote\n' 0
_zf_write m3-entities '<p>&amp;copy; &bogus; &lt;x&gt; &#128;</p>' $'\\&copy; \\&bogus; \\<x\\> €\n' 0
_zf_write m3-emphasis '<p><strong>Bold</strong> <b>B</b> <em>Em</em> <i>I</i></p>' $'**Bold** **B** *Em* *I*\n' 0
_zf_write m3-emphasis-space '<p>a<em> b </em>c<em> </em>d<strong></strong>e</p>' $'a *b* c de\n' 0
_zf_write m3-emphasis-nested '<p><em>a<strong>b</strong>c</em> <strong>a<em>b</em>c</strong></p>' $'*abc* **abc**\n' 0
_zf_write m3-emphasis-collision '<p><strong>a</strong><strong>b</strong><strong>c</strong> <em>a</em><em>b</em></p>' $'**a**b**c** *a*b\n' 0
_zf_write m3-emphasis-fallback '<p>x<em>.</em>y <strong>漢字</strong> <em>*a*</em></p>' $'x.y 漢字 \\*a\\*\n' 0
_zf_write m3-emphasis-block '<em><p>A</p><p>B</p></em>' $'A\n\nB\n' 0
_zf_write m3-link '<p>Read <a href="./guide?q=1&amp;x=2">the <strong>guide</strong></a>.</p>' $'Read [the **guide**](./guide?q=1\\&x=2).\n' 0
_zf_write m3-link-empty '<p><a href="./a"></a> <a>No href</a> <a href="">empty</a></p>' $'[./a](./a) No href empty\n' 0
_zf_write m3-link-space '<a href="a b(c)&lt;d&gt;\e"> label </a>' $'[label](<a b\\(c\\)\\<d\\>\\\\e>)\n' 0
_zf_write m3-link-label '<a href="q&amp;amp;">[x] &amp;copy;</a>' $'[\\[x\\] \\&copy;](q\\&amp;)\n' 0
_zf_write m3-link-code '<a href="u"><code>x[y]</code></a>' $'[`x[y]`](u)\n' 0
_zf_write m3-link-block '<a href="u"><p>A</p><p>B</p></a>' $'A\n\nB\n\n`u`\n' 0
_zf_write m3-link-hardbreak '<a href="u">A<br>B</a>' $'A  \nB\n\n`u`\n' 0
_zf_write m3-link-newline '<a href="x&#10;y">Label</a>' $'Label\n\n```\nx\ny\n```\n' 0
_zf_write m3-link-tab '<a href="x&#9;y">Label</a>' $'Label (`x\ty`)\n' 0
_zf_write m3-link-nested '<a href="outer">A<a href="inner">B</a>C</a>' $'AB (`inner`)C (`outer`)\n' 0
_zf_write m3-images '<p><img alt="A [cat]" src="./cat.png"> <img alt="description"> <img src="./bare"> <img alt="" src="./empty"></p>' $'![A \\[cat\\]](./cat.png) description ./bare ./empty\n' 0
_zf_write m3-image-newline '<img alt="A" src="x&#10;y">' $'A\n\n```\nx\ny\n```\n' 0
_zf_write m3-image-bare-newline '<img src="x&#10;y">' $'```\nx\ny\n```\n' 0
_zf_write m3-code-inline '<p>a<code>x[y]&amp;z</code>b <code>`x`</code> <code>``x`</code></p>' $'a`x[y]&z`b `` `x` `` ``` ``x` ```\n' 0
_zf_write m3-code-space '<p><code> a </code> <code>  </code> <code> a</code> <code>a </code><code></code></p>' $'`  a  ` `  ` ` a` `a `\n' 0
_zf_write m3-code-adjacent '<p><code> a </code><code> `b` </code><code>c</code></p>' $'`` a  `b` c``\n' 0
_zf_write m3-code-through-fallback '<p><code>a</code><em><code>b</code></em><a><code>c</code></a></p><p><img src="x&#9;y"><code>z</code></p>' $'`abc`\n\n`x\tyz`\n' 0
_zf_write m3-code-multiline $'<p>A<code>x\ny</code>B</p>' $'A\n\n```\nx\ny\n```\n\nB\n' 0
_zf_write m3-heading-code-fallback $'<h1><a href="u"><code>a\nb</code></a></h1>' $'```\na\nb\n```\n\n`u`\n' 0
_zf_write m3-empty-code $'<pre></pre><pre>\n</pre><textarea></textarea>' $'```\n```\n\n```\n```\n\n```\n```\n' 0
_zf_write m3-pre-whitespace $'<pre>\n\n\t a  \r\nb\r\n\n</pre>' $'```\n\n\t a  \nb\n\n```\n' 0
_zf_write m3-pre-code-lf $'<pre><code class="ignored language-zsh">\nprint x  \n</code></pre>' $'```zsh\n\nprint x  \n```\n' 0
_zf_write m3-pre-fence $'<pre>```\nx\n````\n</pre>' $'`````\n```\nx\n````\n`````\n' 0
_zf_write m3-pre-language-invalid '<pre><code class="language-bad! language-python">x</code></pre>' $'```python\nx\n```\n' 0
_zf_write m3-textarea '<textarea>&lt;b&gt;&amp;copy;</textarea>' $'```\n<b>&copy;\n```\n' 0
_zf_write m3-plaintext '<plaintext><b>&amp;\x' $'```\n<b>&amp;\\x\n```\n' 0 '--strict'
_zf_write m3-discard '<head><title>Title</title></head><p>A<script>&#1;<b>X</script><style>X</style><template><p>Hidden</p></template>B<!--x--><?x?></p>' $'AB\n' 0
_zf_write m3-discard-only '<script>&#1;</script><template>Hidden</template>' '' 0
_zf_write m3-unsupported '<p><del>A</del><s>B</s><sup>C</sup><sub>D</sub></p>' $'ABCD\n' 0
_zf_write m3-inputs '<p><input value="A"> <input type="text" value="B"> <input type="unknown" value="C"> <input type="submit" value="Go"> <input type="reset"> <input type="hidden" value="NO"><input type="PASSWORD" value="NO"><input type="checkbox" value="NO"></p>' $'A B C Go\n' 0
_zf_write m3-options '<select><option>One</option><option>Two</option></select>' $'- One\n\n- Two\n' 0
_zf_write m3-details '<details><summary>Summary</summary><p>Body</p></details>' $'Summary\n\nBody\n' 0
_zf_write m3-definitions '<dl><dt>Term</dt><dd><p>One</p><p>Two</p></dd><dt>T2</dt><dd>End</dd></dl>' $'Term\n\n> One\n> \n> Two\n\nT2\n\n> End\n' 0
_zf_write m3-repair '<p>A' $'A\n' 0 '' $'zhtml2md: unclosed-element at byte 4: element remains open at EOF\n'
_zf_write m3-repair-strict '<p>A' '' 3 '--strict' $'zhtml2md: unclosed-element at byte 4: element remains open at EOF\n'

print -r -- "wrote ${#written} fixtures to $dir"
