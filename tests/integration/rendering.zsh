# Public rendering, dynamic-scope hygiene, fragment ownership and limits.
# Golden fixtures remain hand-authored in gen-fixtures.zsh; this script
# checks generated boundaries and repeated calls without subprocesses.
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r _zr_root=$ZHTML2MD_ROOT _zr_tmp=${TMPDIR:-/tmp}/zhtml2md-render.$$
command mkdir -p -- "$_zr_tmp" || exit 1
trap "command rm -rf -- ${(q)_zr_tmp}" EXIT
source "$_zr_root/zhtml2md.zsh" || exit 1
local -i _zr_fails=0 _zr_checks=0
_zr_check() {
  (( ++_zr_checks ))
  if (( $2 )); then
    (( ++_zr_fails ))
    builtin print -r -u 2 -- "rendering: FAIL: $1"
  fi
}
_zr_read() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C _chunk _fd
  _zr_readback=''
  { builtin exec {_fd}< "$1"; } 2>/dev/null || return 1
  while { IFS= builtin read -r -u $_fd -k 65536 _chunk; } 2>/dev/null || [[ -n $_chunk ]]; do
    [[ -n $_chunk ]] || break
    _zr_readback+=$_chunk
    _chunk=''
  done
  builtin exec {_fd}<&-
}
local _zr_readback _zr_out _zr_err
_zr_convert() { # HTML expected status [strict]
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  builtin printf '%s' "$1" > "$_zr_tmp/in"
  local -a _opts=()
  [[ $4 == strict ]] && _opts=( --strict )
  zhtml2md "${_opts[@]}" -- "$_zr_tmp/in" > "$_zr_tmp/out" 2> "$_zr_tmp/err"
  local -i _st=$?
  (( _st == $3 )); _zr_check "status $3" $?
  _zr_read "$_zr_tmp/out"; _zr_out=$_zr_readback
  _zr_read "$_zr_tmp/err"; _zr_err=$_zr_readback
  [[ $_zr_out == "$2" ]]; _zr_check 'exact public bytes' $?
}

# Every capture transfers its payload instead of charging all ancestors.
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=8
  _zr_convert '<em><strong><a href="x">abc</a></strong></em>' $'[abc](x)\n' 0 strict
  [[ -z $_zr_err ]]; _zr_check 'capture ownership transfer is quiet' $?
}
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=7
  _zr_convert '<em><strong><a href="x">abc</a></strong></em>' '' 4 strict
  [[ $_zr_err == $'zhtml2md: resource-limit: pending captures exceed 7 bytes\n' ]]
  _zr_check 'capture one byte over boundary' $?
}
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=9
  _zr_convert '<em>A<a href="x">BCD</a></em>' $'A[BCD](x)\n' 0 strict
}
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=8
  _zr_convert '<em>A<a href="x">BCD</a></em>' '' 4 strict
}
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=4
  _zr_convert '<em><code>a</code><code>b</code></em>' $'`ab`\n' 0 strict
}
() {
  local -i _ZHTML2MD_LIMIT_OUTPUT=9
  _zr_convert 'abcdefgh' $'abcdefgh\n' 0 strict
}
() {
  local -i _ZHTML2MD_LIMIT_OUTPUT=8
  _zr_convert 'abcdefgh' '' 4 strict
  [[ $_zr_err == $'zhtml2md: resource-limit: output exceeds 8 bytes\n' ]]
  _zr_check 'final LF charged at output limit' $?
}
() {
  local -i _ZHTML2MD_LIMIT_OUTPUT=5
  _zr_convert '<a href="x">abc</a>' '' 4 strict
  _zr_convert '****' '' 4 strict
}

# Deferred list/table records share the capture budget with live text.
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=6
  _zr_convert '<ul><li>abc</li><li>def</li></ul>' $'- abc\n- def\n' 0 strict
  _zr_convert '<table><tr><td>abc</td><td>def</td></tr></table>' $'|  |  |\n| --- | --- |\n| abc | def |\n' 0 strict
}
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=5
  _zr_convert '<ul><li>abc</li><li>def</li></ul>' '' 4 strict
  _zr_convert '<table><tr><td>abc</td><td>def</td></tr></table>' '' 4 strict
  _zr_convert '<ul><li><ul><li>abc</li></ul></li></ul>' $'- - abc\n' 0 strict
}
() {
  local -i _ZHTML2MD_LIMIT_OUTPUT=7
  _zr_convert '<ul><li>abcd</li></ul>' $'- abcd\n' 0 strict
}
() {
  local -i _ZHTML2MD_LIMIT_OUTPUT=6
  _zr_convert '<ul><li>abcd</li></ul>' '' 4 strict
}
# Immediate pre newlines use the tokenizer's source index, including tags
# crossing quoted '<' segments, UTF-8 attributes and growing tag windows.
_zr_convert $'<pre title="<one><two>">\r\nx\n</pre>' $'```\nx\n```\n' 0 strict
_zr_convert $'<pre title="é😀<x>"><code>\nx\n</code></pre>' $'```\n\nx\n```\n' 0 strict
_zr_convert $'<pre title="<x>">\n\nx\n</pre>' $'```\n\nx\n```\n' 0 strict
local _zr_pre_attr
builtin printf -v _zr_pre_attr '%1024s' ''
_zr_convert '<pre title="'"$_zr_pre_attr"$'<x>">\nx\n</pre>' $'```\nx\n```\n' 0 strict
_zr_convert '<pre title="<x>"></pre>' $'```\n```\n' 0 strict
_zr_convert '<pre>' $'```\n```\n' 0
_zr_convert $'<pre title="<x>">\n' $'```\n```\n' 0
_zr_convert '<pre>' '' 3 strict

# 128 nested list/item pairs occupy all 256 semantic frames. Payload
# moves outward once; only the current rendered item is charged.
local _zr_nested='' _zr_markers
for (( _zr_i=0; _zr_i<128; ++_zr_i )); do _zr_nested+='<ul><li>'; done
_zr_nested+=x
for (( _zr_i=0; _zr_i<128; ++_zr_i )); do _zr_nested+='</li></ul>'; done
builtin printf -v _zr_markers '%128s' ''
_zr_markers=${_zr_markers// /'- '}
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=255
  _zr_convert "$_zr_nested" "$_zr_markers"$'x\n' 0 strict
}
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=254
  _zr_convert "$_zr_nested" '' 4 strict
}
_zr_convert "<ul><li>$_zr_nested</li></ul>" '' 4 strict

# Window boundaries must not change inline-code pipe escaping.
local _zr_seam _zr_pipe_expected
for _zr_i in 4094 4095 4096 4097; do
  builtin printf -v _zr_seam '%*s' $_zr_i ''
  _zr_seam=${_zr_seam// /x}
  _zr_pipe_expected=$'|  |\n| --- |\n| `a'$_zr_seam$'\\|b` |\n'
  _zr_convert "<table><tr><td><code>a$_zr_seam|b</code></td></tr></table>" "$_zr_pipe_expected" 0 strict
done

# Exercise the actual 16 MiB counters independently of the 4 MiB input
# cap. A fragment at the limit fits; a further byte fails with no stdout.
() {
  local -i _zhtml2md_r_slot=1 _zhtml2md_r_serial=0 _zhtml2md_r_pending=0
  local -i _zhtml2md_diag_emitted=0 _zhtml2md_diag_total=0 _zhtml2md_diag_capped=0
  local -A _zhtml2md_r_size=(1 0 2 0) _zhtml2md_r_piece=() _zhtml2md_r_next=()
  local -A _zhtml2md_r_head=() _zhtml2md_r_tail=() _zhtml2md_r_end=()
  local _zhtml2md_r_result _big
  builtin printf -v _big '%16777216s' x
  _zhtml2md_r_append "$_big"; _zr_check 'real output cap exact fragment' $?
  _zhtml2md_r_append x > "$_zr_tmp/out" 2> "$_zr_tmp/err"
  (( $? == 4 )); _zr_check 'real output cap plus one' $?
  [[ ! -s $_zr_tmp/out ]]; _zr_check 'overflow helper stdout empty' $?
  _zhtml2md_r_take
  _zhtml2md_r_slot=2
  _zhtml2md_r_append "$_big"; _zr_check 'real capture cap exact fragment' $?
  _zhtml2md_r_append x > "$_zr_tmp/out" 2> "$_zr_tmp/err"
  (( $? == 4 )); _zr_check 'real capture cap plus one' $?
  _zhtml2md_r_take
  (( _zhtml2md_r_pending == 0 )); _zr_check 'capture charge released' $?
}

# All 256 semantic frames may also be captures, without recursion or
# ancestor payload copies. One more is a parser resource failure.
local _zr_html=''
local -i _zr_i
for (( _zr_i=0; _zr_i<256; ++_zr_i )); do _zr_html+='<em>'; done
_zr_html+=x
for (( _zr_i=0; _zr_i<256; ++_zr_i )); do _zr_html+='</em>'; done
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=3
  _zr_convert "$_zr_html" $'*x*\n' 0 strict
}
_zr_convert "<em>$_zr_html</em>" '' 4 strict

# Bounded-window seams: prose, CRLF, and longest backtick runs. Expected
# bytes are constructed from the inputs and reviewed syntax rules.
local _zr_body _zr_expected
for _zr_i in 4094 4095 4096 4097; do
  builtin printf -v _zr_body '%*s' $_zr_i ''
  _zr_body=${_zr_body// /x}
  _zr_convert "$_zr_body a" "$_zr_body a"$'\n' 0 strict
  _zr_convert "<pre>$_zr_body"$'\r\ny</pre>' $'```\n'"$_zr_body"$'\ny\n```\n' 0 strict
done
builtin printf -v _zr_body '%4100s' ''
_zr_body=${_zr_body// /\`}
_zr_expected='`'$_zr_body
_zr_convert "<pre>$_zr_body</pre>" "$_zr_expected"$'\n'"$_zr_body"$'\n'"$_zr_expected"$'\n' 0 strict
_zr_convert '<pre></pre><pre>'$'\n</pre>' $'```\n```\n\n```\n```\n' 0 strict
_zr_convert '<pre><code class="x language-zsh">A</code><code class="language-python">B</code></pre>' $'```zsh\nAB\n```\n' 0 strict

# All form types with supplied text, including absent/unknown types;
# non-text state is omitted, and no default button value is invented.
local _zr_type
for _zr_type in text search email url tel number date datetime datetime-local time month week button submit reset unknown ''; do
  _zr_convert "<input type='$_zr_type' value='A &amp; B'>" $'A \\& B\n' 0 strict
done
for _zr_type in hidden password checkbox radio file range color image; do
  _zr_convert "<input type='$_zr_type' value='secret'>" '' 0 strict
done

# Recovery may not escape a discard boundary and leak hidden content.
_zr_convert '<p>A<template></p>X</template>B</p>' $'AB\n' 0
_zr_convert '<p>A<template></p>X</template>B</p>' '' 3 strict
_zr_convert '<ul><li>A<template><ul><li>X</li></ul></template>B</li></ul>' $'- AB\n' 0 strict
_zr_convert '<ul><li>A<template><li>X</li></template>B</li></ul>' $'- AB\n' 0
_zr_convert '<table><tr><td>A<template><td>X</td></template>B</td></tr></table>' $'|  |\n| --- |\n| AB |\n' 0 strict
_zr_convert '<div>A<template><table><tr><td>X</td></tr></table></template>B</div>' $'AB\n' 0 strict
_zr_convert '<p>A<template>hidden<p>more' $'A\n' 0
_zr_convert '<p>A<template>hidden<p>more' '' 3 strict

# A long conflicting run exercises many scan windows and fence building
# without committing a large fixture or requiring a development parser.
() {
  local _zhtml2md_r_result _ticks='`'
  local -i _zhtml2md_r_tick_max=0 _zhtml2md_r_result_block=0
  local -i _zhtml2md_r_code_width=0 _zhtml2md_r_code_pad=0 _i
  for (( _i=0; _i<16; ++_i )); do _ticks+=$_ticks; done
  _zhtml2md_r_code "$_ticks" fence ''
  (( _zhtml2md_r_tick_max == 65536 && ${#_zhtml2md_r_result} == 196612 ));
  _zr_check 'long code fence length and conflict run' $?
}

# A later failure still prints the warning summary and releases no bytes.
_zr_html=''
for (( _zr_i=0; _zr_i<25; ++_zr_i )); do _zr_html+='</bad>'; done
() {
  local -i _ZHTML2MD_LIMIT_CAPTURE=1
  _zr_convert "$_zr_html<em>AB</em>" '' 4
  [[ $_zr_err == *$'warning-summary: 5 further warnings suppressed\n' ]]
  _zr_check 'warning summary after renderer failure' $?
}

# Adverse caller options, locale/IFS, regex scratch, traps, globals and
# descriptors on success and failure. Calls stay in this shell so state
# leaks cannot be hidden by command substitution.
() {
  emulate -L zsh
  setopt ksh_arrays sh_word_split glob_subst extended_glob
  local LC_ALL=C.UTF-8 IFS=': '
  local MATCH=sentinel MBEGIN=77 MEND=88
  local -a match=(keep) mbegin=(7) mend=(8)
  local marker=0
  local -r _before_options=${(j: :)${(@kv)options}} _before_locale=$LC_ALL _before_ifs=$IFS
  local -r _before_path=${(j: :)path} _before_fpath=${(j: :)fpath} _before_pwd=$PWD
  local -a _before_fds=( /proc/self/fd/*(N) ) _before_params
  local -a _after_fds _after_params _new _bad
  local -i _i
  _before_params=( ${(ok)parameters} )
  for (( _i=0; _i<50; ++_i )); do
    _zr_convert '<h1>Title</h1><p><strong>A</strong><code>`x`</code><a href="$(marker=99)">B</a></p>' $'# Title\n\n**A**`` `x` ``[B]($\\(marker=99\\))\n' 0 strict
    _zr_convert '<p>Read <a href="x">this</a>' '' 3 strict
  done
  [[ ${(j: :)${(@kv)options}} == "$_before_options" && $LC_ALL == "$_before_locale" && $IFS == "$_before_ifs" ]]
  _zr_check 'caller options locale IFS preserved' $?
  [[ ${(j: :)path} == "$_before_path" && ${(j: :)fpath} == "$_before_fpath" && $PWD == "$_before_pwd" ]]
  _zr_check 'caller paths and cwd preserved' $?
  [[ $MATCH == sentinel && $MBEGIN == 77 && $MEND == 88 && ${match[0]} == keep && ${mbegin[0]} == 7 && ${mend[0]} == 8 && $marker == 0 ]]
  _zr_check 'regex scratch and shell payload inert' $?
  _after_fds=( /proc/self/fd/*(N) )
  [[ ${(j: :)_before_fds} == "${(j: :)_after_fds}" ]]; _zr_check 'renderer descriptor cleanup' $?
  _after_params=( ${(ok)parameters} )
  _new=( ${_after_params:|_before_params} )
  _bad=( ${_new:#_zhtml2md*} ); _bad=( ${_bad:#_ZHTML2MD*} )
  (( ${#_bad} == 0 )); _zr_check 'renderer has no unrelated globals' $?
}

# Cold initialization, complete rendering, and strict failure with no
# command lookup and a foreign working directory.
PATH=$_zr_tmp "${ZHTML2MD_TEST_ZSH}" -df -c '
  builtin cd / || exit 1
  source "$1" || exit 1
  builtin printf "%s" "<h1>A</h1><p><a href=\"./x\">&amp;</a></p><pre><code class=\"language-zsh\">print x</code></pre>" | zhtml2md --strict || exit 1
' zsh "$_zr_root/zhtml2md.zsh" > "$_zr_tmp/out" 2> "$_zr_tmp/err"
_zr_check 'full conversion with empty PATH' $?
_zr_read "$_zr_tmp/out"
[[ $_zr_readback == $'# A\n\n[\\&](./x)\n\n```zsh\nprint x\n```\n' && ! -s $_zr_tmp/err ]]
_zr_check 'empty PATH full Markdown bytes' $?

# The M4 acceptance fixture also runs cold with no command lookup.
PATH=$_zr_tmp "${ZHTML2MD_TEST_ZSH}" -df -c '
  builtin cd / || exit 1
  module_path=( /nonexistent-zhtml2md-modules )
  source "$1" || exit 1
  zhtml2md --strict -- "$2" || exit 1
' zsh "$_zr_root/zhtml2md.zsh" "$_zr_root/tests/fixtures/m4-acceptance-strict.html" > "$_zr_tmp/out" 2> "$_zr_tmp/err"
_zr_check 'structures with empty PATH and module path' $?
_zr_read "$_zr_tmp/out"; _zr_out=$_zr_readback
_zr_read "$_zr_root/tests/fixtures/m4-acceptance-strict.md"
[[ $_zr_out == "$_zr_readback" && ! -s $_zr_tmp/err ]]
_zr_check 'empty PATH structural bytes' $?

builtin print -r -- "rendering: $_zr_checks assertions, $_zr_fails failures"
(( _zr_fails == 0 ))
