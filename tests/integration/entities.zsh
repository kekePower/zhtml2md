# Entity component and initialization checks, run by tests/run.zsh.
# Expected bytes are separate from Markdown fixtures: no tokenizer or
# renderer decisions should obscure a decoding regression.
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r root=$ZHTML2MD_ROOT
local -r tmp=${TMPDIR:-/tmp}/zhtml2md-entities.$$
command mkdir -p -- "$tmp/install/data" || exit 1
trap "command rm -rf -- ${(q)tmp}" EXIT
source "$root/zhtml2md.zsh" || exit 1
local -i fails=0
local _zhtml2md_decoded=''
local -i _zhtml2md_diag_emitted=0 _zhtml2md_diag_total=0 _zhtml2md_diag_capped=0

_ze_check() {
  if (( $2 != 0 )); then
    (( ++fails ))
    builtin print -r -u 2 -- "entities: FAIL: $1"
  fi
}

_ze_read() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _fd _chunk=''
  REPLY=''
  { exec {_fd}< "$1"; } 2>/dev/null || return 1
  {
    while { IFS= builtin read -r -u $_fd -k 65536 _chunk; } 2>/dev/null || [[ -n $_chunk ]]; do
      REPLY+=$_chunk
      _chunk=''
    done
  } always {
    { exec {_fd}<&-; } 2>/dev/null
  }
}

# Sourcing and plain text must not initialize the cache.
(( ! ${+_ZHTML2MD_ENTITIES_READY} )); _ze_check 'data is lazy after source' $?
_zhtml2md_decode_entities plain 0
(( ! ${+_ZHTML2MD_ENTITIES_READY} )); _ze_check 'plain text needs no data' $?

# Snapshot the regex-related caller parameters. Helpers must localize
# these as well as options/locale; =~ otherwise writes caller state.
local MATCH=caller MBEGIN=12 MEND=34
local -a match=( old ) mbegin=( 5 ) mend=( 6 )
local f name input expected err wanted_err offset wanted_status
local -i st
for f in "$root"/tests/entities/*.input(N); do
  name=${${f:t}%.input}
  _ze_read "$f"; input=$REPLY
  _ze_read "$root/tests/entities/$name.decoded"; expected=$REPLY
  _ze_read "$root/tests/entities/$name.offset"; offset=${REPLY%$'\n'}
  _ze_read "$root/tests/entities/$name.status"; wanted_status=${REPLY%$'\n'}
  _ze_read "$root/tests/entities/$name.stderr"; wanted_err=$REPLY
  _zhtml2md_decoded=stale
  _zhtml2md_decode_entities "$input" "$offset" > "$tmp/out" 2> "$tmp/err"
  st=$?
  _ze_read "$tmp/err"; err=$REPLY
  [[ $st == $wanted_status ]]; _ze_check "$name status" $?
  [[ $_zhtml2md_decoded == "$expected" ]]; _ze_check "$name decoded bytes" $?
  [[ $err == "$wanted_err" ]]; _ze_check "$name diagnostic" $?
  [[ ! -s $tmp/out ]]; _ze_check "$name no helper stdout" $?
done
[[ $MATCH == caller && $MBEGIN == 12 && $MEND == 34 && $match[1] == old && $mbegin[1] == 5 && $mend[1] == 6 ]]
_ze_check 'regex parameters preserved' $?
(( ${#_ZHTML2MD_ENTITIES} == 2125 )); _ze_check 'complete cache' $?

# Every forbidden C0/DEL scalar fails, except HT/LF/CR; zero is U+FFFD.
local -i cp
for cp in {1..31} 127; do
  (( cp == 9 || cp == 10 || cp == 13 )) && continue
  _zhtml2md_decode_entities "&#$cp;" 7 2> "$tmp/err"
  (( $? == 3 )); _ze_check "forbidden scalar $cp rejected" $?
  [[ -z $_zhtml2md_decoded ]]; _ze_check "forbidden scalar $cp result empty" $?
done

# Long numeric values get a bounded numeric scan, including arbitrarily
# many leading zeros. A very long invalid candidate remains literal.
local zeros huge
builtin printf -v zeros '%01048576d' 0
_zhtml2md_decode_entities "&#${zeros}65;" 0
[[ $_zhtml2md_decoded == A ]]; _ze_check 'long leading zeros' $?
_zhtml2md_decode_entities "&#${zeros}99999999999;" 0
[[ $_zhtml2md_decoded == $'\xef\xbf\xbd' ]]; _ze_check 'long numeric overflow' $?
huge="&#${zeros}x;"
_zhtml2md_decode_entities "$huge" 0
[[ $_zhtml2md_decoded == "$huge" ]]; _ze_check 'long malformed numeric stays literal' $?

# Exact capture boundary and one byte beyond, without allocating a
# multi-million-element reference array for a simple length check.
builtin printf -v huge '%16777216s' x
_zhtml2md_decode_entities "$huge" 0
(( $? == 0 && ${#_zhtml2md_decoded} == 16777216 )); _ze_check 'capture boundary' $?
_zhtml2md_decode_entities "${huge}x" 0 2> "$tmp/err"
(( $? == 4 )); _ze_check 'capture over boundary status' $?
[[ -z $_zhtml2md_decoded ]]; _ze_check 'capture over boundary result empty' $?
huge=''; zeros=''

# Initialization errors never publish partial cache and never leak an
# owned descriptor. Each case runs with local installation metadata.
_ze_bad_data() { # label contents (empty means missing file)
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _ZHTML2MD_DIR=$tmp/install
  builtin unset _ZHTML2MD_ENTITIES_READY _ZHTML2MD_ENTITIES
  command rm -f -- "$tmp/install/data/entities.tsv"
  [[ -n $2 ]] && builtin printf '%s' "$2" > "$tmp/install/data/entities.tsv"
  local -a _before=( /proc/self/fd/*(N) ) _after
  _zhtml2md_decoded=stale
  _zhtml2md_decode_entities '&amp;' 0 > "$tmp/out" 2> "$tmp/err"
  local -i _st=$?
  _after=( /proc/self/fd/*(N) )
  (( _st == 1 )); _ze_check "$1 init status" $?
  (( ! ${+_ZHTML2MD_ENTITIES_READY} && ! ${+_ZHTML2MD_ENTITIES} )); _ze_check "$1 no partial cache" $?
  [[ -z $_zhtml2md_decoded && ! -s $tmp/out ]]; _ze_check "$1 empty output" $?
  _ze_read "$tmp/err"
  [[ $REPLY == 'zhtml2md: initialization:'*$'\n' ]]; _ze_check "$1 diagnostic" $?
  [[ "${(j: :)_before}" == "${(j: :)_after}" ]]; _ze_check "$1 descriptors" $?
}

_ze_bad_data missing ''
_ze_bad_data empty-line $'\n'
_ze_bad_data empty-field $'amp\t\n'
_ze_bad_data trailing-tab $'amp\t26\t\n'
_ze_bad_data extra-field $'amp\t26\t26\t26\n'
_ze_bad_data duplicate $'amp\t26\namp\t26\n'
_ze_bad_data short $'amp\t26\n'
_ze_bad_data missing-lf $'amp\t26'
_ze_bad_data invalid-name $'$(print bad)\t26\n'
_ze_bad_data invalid-number $'amp\t$(print bad)\n'
_ze_bad_data lowercase-hex $'amp\taB\n'
_ze_bad_data nul $'amp\t26\x00\n'
_ze_bad_data crlf $'amp\t26\r\n'
_ze_bad_data surrogate $'amp\tD800\n'
_ze_bad_data zero $'amp\t0\n'
_ze_bad_data control $'amp\t7F\n'
_ze_bad_data overflow $'amp\t110000\n'
_ze_bad_data long-number $'amp\t0000026\n'
builtin printf -v huge '%131073s' x
_ze_bad_data oversized "$huge"
huge=''

# A subsequent correct file initializes successfully, and later sourcing
# and conversions retain the immutable cache.
command cp -- "$root/data/entities.tsv" "$tmp/install/data/entities.tsv"
() {
  local _ZHTML2MD_DIR=$tmp/install
  _zhtml2md_decode_entities '&amp;' 0
  (( $? == 0 )); _ze_check 'retry after initialization failure' $?
}
source "$root/zhtml2md.zsh"
(( ${#_ZHTML2MD_ENTITIES} == 2125 )); _ze_check 'cache survives repeated source' $?

# Native semantics and caller state with the cache warm and cold. The
# initialization attempt under these options must preserve them too.
() {
  emulate -L zsh
  local LC_ALL=C.UTF-8 IFS=': '
  setopt ksh_arrays sh_word_split glob_subst extended_glob
  local _before_options=${(j: :)${(@kv)options}} _before_locale=$LC_ALL _before_ifs=$IFS
  builtin unset _ZHTML2MD_ENTITIES_READY _ZHTML2MD_ENTITIES
  _zhtml2md_decode_entities '&NotEqualTilde;&#x1F600;' 0
  (( $? == 0 )); _ze_check 'cold decode under hostile options' $?
  [[ $_zhtml2md_decoded == $'\xe2\x89\x82\xcc\xb8\xf0\x9f\x98\x80' ]]; _ze_check 'hostile decode bytes' $?
  [[ ${(j: :)${(@kv)options}} == "$_before_options" && $LC_ALL == "$_before_locale" && $IFS == "$_before_ifs" ]]
  _ze_check 'options locale and IFS preserved' $?
  _zhtml2md_decode_entities '&#1;' 0 2> "$tmp/err"
  (( $? == 3 )); _ze_check 'hostile failure status' $?
  [[ ${(j: :)${(@kv)options}} == "$_before_options" && $LC_ALL == "$_before_locale" && $IFS == "$_before_ifs" ]]
  _ze_check 'caller state preserved after failure' $?
}

# Purity covers cold data loading as well as numeric UTF-8 emission.
local out
out=$( PATH=$tmp/install "${ZHTML2MD_TEST_ZSH}" -df -c '
  builtin cd / || exit 1
  source "$1" || exit 1
  local _zhtml2md_decoded _zhtml2md_diag_emitted=0 _zhtml2md_diag_total=0 _zhtml2md_diag_capped=0
  _zhtml2md_decode_entities "&NotEqualTilde;&#x1F600;" 0 || exit $?
  builtin printf "%s" "$_zhtml2md_decoded"
' zsh "$root/zhtml2md.zsh" 2> "$tmp/err" )
(( $? == 0 )); _ze_check 'cold decoding without PATH commands' $?
[[ $out == $'\xe2\x89\x82\xcc\xb8\xf0\x9f\x98\x80' && ! -s $tmp/err ]]; _ze_check 'empty PATH bytes and diagnostics' $?

# A missing new module must not leave the caller's alias option disabled.
command mkdir -p -- "$tmp/broken/lib"
command cp -- "$root/zhtml2md.zsh" "$tmp/broken/zhtml2md.zsh"
command cp -- "$root/lib/_zhtml2md_input.zsh" "$root/lib/_zhtml2md_render.zsh" "$tmp/broken/lib/"
"${ZHTML2MD_TEST_ZSH}" -df -c '
  setopt aliases
  source "$1" 2>/dev/null
  (( $? == 1 )) || exit 1
  [[ $options[aliases] == on ]]
' zsh "$tmp/broken/zhtml2md.zsh"
(( $? == 0 )); _ze_check 'aliases restored after module load failure' $?

(( fails == 0 ))
