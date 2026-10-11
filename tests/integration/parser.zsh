# Parser boundary, shell-hygiene, and inert-data tests. Core operations
# use Zsh alone; filesystem tools only prepare disposable installations.
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r root=$ZHTML2MD_ROOT
local -r tmp=${TMPDIR:-/tmp}/zhtml2md-parser.$$
command mkdir -p -- "$tmp/empty"
trap "command rm -rf -- ${(q)tmp}" EXIT
source "$root/zhtml2md.zsh" || exit 1
local -i fails=0 checks=0
local _zhtml2md_input='' _zhtml2md_strict=1
local -i _zhtml2md_bom=0 _zhtml2md_diag_emitted=0 _zhtml2md_diag_total=0 _zhtml2md_diag_capped=0
local -a texts=() attr_names=() attr_values=() tags=()
local -i opens=0 closes=0 voids=0
local pad=''
local -i i=0

_zp_check() {
  (( ++checks ))
  if (( $2 != 0 )); then
    (( ++fails ))
    builtin print -r -u 2 -- "parser: FAIL: $1"
  fi
}

_zhtml2md_parse_event() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local key
  case $_zhtml2md_event_kind in
    open) (( ++opens )); tags+=( "$_zhtml2md_event_name" ) ;;
    close) (( ++closes )) ;;
    void) (( ++voids )) ;;
    text) texts+=( "$_zhtml2md_event_data" ) ;;
  esac
  for key in "${(@ok)_zhtml2md_event_attrs}"; do
    attr_names+=( "$key" )
    attr_values+=( "${_zhtml2md_event_attrs[$key]}" )
  done
  return 0
}

_zp_parse() { # input strict
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  _zhtml2md_input=$1
  _zhtml2md_strict=$2
  _zhtml2md_bom=0
  _zhtml2md_diag_emitted=0; _zhtml2md_diag_total=0; _zhtml2md_diag_capped=0
  texts=(); attr_names=(); attr_values=(); tags=()
  opens=0; closes=0; voids=0
  _zhtml2md_parse > "$tmp/out" 2> "$tmp/err"
  local -i st=$?
  _zhtml2md_diag_finish 2>> "$tmp/err"
  return $st
}

# Code text retains initial LF, tabs, CRLF, blank lines, trailing spaces,
# and source order; the future renderer owns newline normalization.
_zp_parse $'<pre><code>\n\t a  \r\n\n</code></pre>' 1
(( $? == 0 )); _zp_check 'code strict success' $?
[[ ${(j::)texts} == $'\n\t a  \r\n\n' ]]; _zp_check 'exact code whitespace' $?
_zp_parse $'<p>caf\xc3\xa9 &nbsp; \xf0\x9f\x98\x80 e\xcc\x81</p>' 1
(( $? == 0 )); _zp_check 'Unicode strict success' $?
[[ ${(j::)texts} == $'caf\xc3\xa9 \xc2\xa0 \xf0\x9f\x98\x80 e\xcc\x81' ]]; _zp_check 'Unicode bytes and NBSP' $?
_zp_parse '<table><tr><td>A<table><tr><td>B</td></tr><tr><td>C</td></tr></table>D</td></tr></table>' 1
(( $? == 0 && opens == closes && ! _zhtml2md_diag_total )); _zp_check 'nested table scopes stay independent' $?
[[ ${(j::)texts} == ABCD ]]; _zp_check 'nested table text order' $?

# Candidate growth can cross every lexical state and '<' segment edge.
for i in {245..260} 505 506 507 508 509 510 511 512; do
  builtin printf -v pad '%0*d' $i 0
  _zp_parse '<div x="'"$pad"'<fake>">ok</div>' 1
  (( $? == 0 )); _zp_check "quoted candidate growth $i" $?
  [[ ${attr_values[1]} == "$pad<fake>" && ${(j::)texts} == ok ]]; _zp_check "quoted candidate bytes $i" $?
done

# Attack strings stay literal even when used as attribute/tag names.
# No shell expansion, arithmetic expression, or pattern is evaluated.
local -i marker=0
local payload='<x[$((marker=99))] a[$(print_BAD)]="$(print BAD)" href="`print BAD`" value="$((marker=77))">${HOME}; $(print BAD)</x[$((marker=99))]>'
_zp_parse "$payload" 1
(( $? == 0 && marker == 0 )); _zp_check 'payloads in literal names and values inert' $?
[[ ${(j::)texts} == '${HOME}; $(print BAD)' ]]; _zp_check 'text payload retained' $?
[[ ${tags[1]} == 'x[$((marker=99))]' ]]; _zp_check 'tag name literal' $?
[[ ${attr_names[1]} == 'a[$(print_bad)]' && ${attr_values[1]} == '$(print BAD)' ]]; _zp_check 'attribute name folds ASCII and value stays literal' $?

# All HTML void elements can appear at the depth boundary; they do not
# consume stack frames. Depth also counts discarded/synthetic frames.
local nested='' ends='' manyvoid='' data
local -i st
for (( i=0; i < 256; ++i )); do
  nested+='<x>'; ends+='</x>'
done
manyvoid='<area><base><br><col><embed><hr><img><input><link><meta><param><source><track><wbr>'
_zp_parse "$nested$manyvoid$ends" 1
(( $? == 0 && opens == 256 && closes == 256 && voids == 14 )); _zp_check 'depth exactly 256 and void set' $?
[[ ! -s $tmp/err && ! -s $tmp/out ]]; _zp_check 'boundary has no diagnostics or stdout' $?
_zp_parse "$nested<x>$ends</x>" 1
(( $? == 4 )); _zp_check 'depth 257 rejected' $?
[[ $( <"$tmp/err" ) == 'zhtml2md: resource-limit at byte 768: open frames exceed 256' ]]; _zp_check 'depth diagnostic offset' $?
_zp_parse "$nested<li>x</li>$ends" 0
(( $? == 4 )); _zp_check 'synthetic frame counts against depth' $?
nested=''; ends=''
for (( i=0; i < 256; ++i )); do
  nested+='<template>'; ends+='</template>'
done
_zp_parse "$nested$ends" 1
(( $? == 0 && opens == 256 && closes == 256 )); _zp_check 'discard depth boundary' $?
_zp_parse "$nested<script>x</script>$ends" 1
(( $? == 4 )); _zp_check 'discard depth overflow' $?

# Ordinary candidate includes both brackets and quoted attribute bytes.
builtin printf -v pad '%065526d' 0
data='<div x="'"$pad"'"></div>'
_zp_parse "$data" 1
(( $? == 0 && opens == 1 && closes == 1 )); _zp_check 'tag exactly 65536' $?
(( ${#attr_values[1]} == 65526 )); _zp_check 'large attribute retained' $?
_zp_parse '<div x="'"${pad}0"'"></div>' 1
(( $? == 4 )); _zp_check 'tag one byte beyond rejected' $?
[[ $( <"$tmp/err" ) == 'zhtml2md: resource-limit at byte 0: ordinary tag exceeds 65536 bytes' ]]; _zp_check 'tag diagnostic' $?
builtin printf -v pad '%065528d' 0
_zp_parse '<div x="'"$pad" 0
(( $? == 0 )); _zp_check 'unfinished tag exactly limit retained' $?
[[ ${(j::)texts} == '<div x="'"$pad" ]]; _zp_check 'unfinished tag literal bytes' $?
_zp_parse '<div x="'"${pad}0" 0
(( $? == 4 )); _zp_check 'unfinished tag over limit rejected' $?

# Large comments, declarations, raw bodies and plain text bypass the tag
# cap, and comment terminators are found across every window boundary.
for i in {4093..4100}; do
  builtin printf -v pad '%0*d' $i 0
  _zp_parse '<!--'"$pad"'-->ok' 1
  (( $? == 0 )); _zp_check "comment window $i status" $?
  [[ ${(j::)texts} == ok ]]; _zp_check "comment window $i text" $?
done
builtin printf -v pad '%01048576d' 0
for data in '<!--'"$pad"'-->ok' '<!DOCTYPE x "'"$pad"'>">ok' '<script>'"$pad"'</script>ok' '<style>'"$pad"'</style>ok'; do
  _zp_parse "$data" 1
  (( $? == 0 )); _zp_check 'large discarded span succeeds' $?
  [[ ${(j::)texts} == ok ]]; _zp_check 'large discarded body absent' $?
done
_zp_parse "$pad" 1
(( $? == 0 )); _zp_check 'large plain text succeeds' $?
[[ ${(j::)texts} == "$pad" ]]; _zp_check 'large plain bytes retained' $?
pad=''; data=''; nested=''; ends=''

# Numeric boundary values and source expression rejection. Unknown attrs
# are literal; invalid recognized numeric attrs lose only their value.
for data in -999999999 999999999 +0009 -0; do
  _zp_parse '<ol start="'"$data"'"><li>x</li></ol>' 1
  (( $? == 0 )); _zp_check "signed number $data accepted" $?
done
for data in -1000000000 1000000000 '1+2' '$((marker=3))' '' ' 1' '--1'; do
  _zp_parse '<ol start="'"$data"'"><li>x</li></ol>' 0
  (( $? == 0 && marker == 0 )); _zp_check "bad signed $data tolerant and inert" $?
  (( ${#attr_values} == 0 )); _zp_check "bad signed $data defaults" $?
  _zp_parse '<ol start="'"$data"'"><li>x</li></ol>' 1
  (( $? == 3 )); _zp_check "bad signed $data strict" $?
done
for data in '<td rowspan=0 colspan=1>x</td>' '<th rowspan=65534 colspan=1000>x</th>'; do
  _zp_parse "$data" 1
  (( $? == 0 )); _zp_check 'span boundaries accepted' $?
done
for data in '<td rowspan=-1>x</td>' '<td rowspan=65535>x</td>' '<td colspan=0>x</td>' '<td colspan=1001>x</td>' '<td colspan="1+1">x</td>'; do
  _zp_parse "$data" 0
  (( $? == 0 && ${#attr_values} == 0 )); _zp_check 'invalid span defaults' $?
  _zp_parse "$data" 1
  (( $? == 3 )); _zp_check 'invalid span strict' $?
done

# Warning cap, EOF repairs and strict early failure have stable counts.
data=''
for (( i=0; i < 25; ++i )); do data+='</br>'; done
_zp_parse "$data" 0
(( $? == 0 && _zhtml2md_diag_total == 25 && _zhtml2md_diag_emitted == 20 )); _zp_check 'warning cap counts' $?
[[ $( <"$tmp/err" ) == *'zhtml2md: warning-summary: 5 further warnings suppressed' ]]; _zp_check 'warning cap summary' $?
_zp_parse "$data" 1
(( $? == 3 && _zhtml2md_diag_total == 1 )); _zp_check 'strict stops at first repair' $?

# Options, regex scratch, locale, paths, aliases, traps, descriptors and
# unrelated parameters survive success, failure and repeated invocations.
() {
  emulate -L zsh
  setopt ksh_arrays sh_word_split glob_subst extended_glob
  local LC_ALL=C.UTF-8 IFS=': '
  local MATCH=caller MBEGIN=11 MEND=22
  local -a match=( prior ) mbegin=( 3 ) mend=( 4 )
  local before_options=${(j: :)${(@kv)options}} before_locale=$LC_ALL before_ifs=$IFS
  local before_pwd=$PWD before_path=${(j: :)path} before_fpath=${(j: :)fpath}
  local before_aliases=$(builtin alias) before_traps=$(builtin trap)
  local -a fds_before=( /proc/self/fd/*(N) ) fds_after
  for (( i=0; i < 100; ++i )); do
    _zp_parse '<ol start="&#45;009"><li>a&amp;b</li></ol>' 1
    (( $? == 0 )); _zp_check 'repeated parse under hostile options' $?
  done
  _zp_parse '<p>x<p>y' 1
  (( $? == 3 )); _zp_check 'hostile parse failure status' $?
  [[ ${(j: :)${(@kv)options}} == "$before_options" && $LC_ALL == "$before_locale" && $IFS == "$before_ifs" ]]; _zp_check 'option locale IFS preservation' $?
  [[ $PWD == "$before_pwd" && ${(j: :)path} == "$before_path" && ${(j: :)fpath} == "$before_fpath" ]]; _zp_check 'cwd path fpath preservation' $?
  [[ $(builtin alias) == "$before_aliases" && $(builtin trap) == "$before_traps" ]]; _zp_check 'alias trap preservation' $?
  [[ $MATCH == caller && $MBEGIN == 11 && $MEND == 22 && ${match[0]} == prior ]]; _zp_check 'regex caller state' $?
  fds_after=( /proc/self/fd/*(N) )
  [[ ${(j: :)fds_before} == ${(j: :)fds_after} ]]; _zp_check 'descriptor preservation' $?
}

# Fresh loading and parsing with no external lookup and a foreign cwd.
PATH=$tmp/empty "$ZHTML2MD_TEST_ZSH" -df -c '
  builtin cd / || exit 1
  source "$1" || exit 1
  local _zhtml2md_input="<p>&amp;<script>fake<p>&#1;</script>x</p>" _zhtml2md_strict=1
  local _zhtml2md_bom=0 _zhtml2md_diag_emitted=0 _zhtml2md_diag_total=0 _zhtml2md_diag_capped=0
  _zhtml2md_parse
' zsh "$root/zhtml2md.zsh" > "$tmp/out" 2> "$tmp/err"
(( $? == 0 )); _zp_check 'empty PATH parser succeeds' $?
[[ ! -s $tmp/out && ! -s $tmp/err ]]; _zp_check 'empty PATH parser quiet' $?

# Fixed sink failures propagate; no output is published by the parser.
_zhtml2md_parse_event() { emulate -L zsh; return 1; }
_zp_parse '<p>x</p>' 1
(( $? == 1 )); _zp_check 'sink failure propagated' $?
[[ ! -s $tmp/out ]]; _zp_check 'sink failure stdout empty' $?

builtin print -r -- "parser integration: $checks checks, $fails failed"
(( fails == 0 ))
