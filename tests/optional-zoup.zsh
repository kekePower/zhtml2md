#!/usr/bin/env zsh
# Optional real zoup integration. Core tests never require its installation.
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r root=${${${(%):-%N}:A:h}:h}
local zoup_root=${1:-${ZHTML2MD_ZOUP_ROOT:-}}
if [[ -z $zoup_root ]]; then
  builtin print -r -- 'SKIP: supply a zoup checkout path (or ZHTML2MD_ZOUP_ROOT)'
  exit 0
fi
[[ -r $zoup_root/functions/zoup ]] || { builtin print -r -u 2 -- 'zoup functions not found'; exit 1 }
fpath=( "$zoup_root/functions" "${fpath[@]}" )
autoload -Uz zoup
source "$root/zhtml2md.zsh" || exit 1
local -r tmp=${TMPDIR:-/tmp}/zhtml2md-zoup.$$
command mkdir -p -- "$tmp" || exit 1
trap "command rm -rf -- ${(q)tmp}" EXIT
local REPLY input agreed actual f name chunk fd
_zzo_read() {
  REPLY=''
  builtin exec {fd}< "$1" || return 1
  while { IFS= builtin read -r -u $fd -k 65536 chunk; } 2>/dev/null || [[ -n $chunk ]]; do
    REPLY+=$chunk; chunk=''
  done
  builtin exec {fd}<&-
}
zoup --version || exit 1
local -i fails=0 cases=0
for f in "$root"/tests/contracts/*.source.html(N); do
  name=${${f:t}%.source.html}
  _zzo_read "$f"; input=$REPLY
  _zzo_read "$root/tests/contracts/$name.clean.html"; agreed=$REPLY
  zoup clean -- "$input" || exit 1
  (( ++cases ))
  if [[ $REPLY != "$agreed" ]]; then
    builtin print -r -u 2 -- "zoup: cleaning differs for $name: ${(q)REPLY}"
    (( ++fails ))
  fi
  builtin printf '%s' "$REPLY" > "$tmp/clean"
  zhtml2md --strict -- "$tmp/clean" > "$tmp/out" 2> "$tmp/err" || exit 1
  _zzo_read "$tmp/out"; actual=$REPLY
  _zzo_read "$root/tests/contracts/$name.md"
  if [[ $actual != "$REPLY" || -s $tmp/err ]]; then
    builtin print -r -u 2 -- "zoup: Markdown differs for $name"; (( ++fails ))
  fi
done
builtin print -r -- "zoup: $cases pairs, $fails failures"
(( cases == 5 && fails == 0 ))
