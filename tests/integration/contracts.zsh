# Offline converter contract: original HTML and agreed cleaned HTML.
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r root=$ZHTML2MD_ROOT tmp=${TMPDIR:-/tmp}/zhtml2md-contracts.$$
command mkdir -p -- "$tmp" || exit 1
trap "command rm -rf -- ${(q)tmp}" EXIT
source "$root/zhtml2md.zsh" || exit 1
local -i fails=0 checks=0
local actual expected chunk fd
_zc_read() {
  REPLY=''
  builtin exec {fd}< "$1" || return 1
  while { IFS= builtin read -r -u $fd -k 65536 chunk; } 2>/dev/null || [[ -n $chunk ]]; do
    REPLY+=$chunk; chunk=''
  done
  builtin exec {fd}<&-
}
local f name kind
for f in "$root"/tests/contracts/*.source.html(N); do
  name=${${f:t}%.source.html}
  for kind in source clean; do
    zhtml2md --strict -- "$root/tests/contracts/$name.$kind.html" > "$tmp/out" 2> "$tmp/err"
    local -i st=$?
    _zc_read "$tmp/out"; actual=$REPLY
    if [[ $kind == source ]]; then _zc_read "$root/tests/contracts/$name.source.md"
    else _zc_read "$root/tests/contracts/$name.md"; fi
    expected=$REPLY
    (( ++checks ))
    if (( st )) || [[ $actual != "$expected" || -s $tmp/err ]]; then
      (( ++fails )); builtin print -r -u 2 -- "contracts: FAIL $name/$kind status=$st"
    fi
  done
done
(( checks == 10 && fails == 0 ))
