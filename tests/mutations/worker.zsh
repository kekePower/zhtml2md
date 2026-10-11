#!/usr/bin/env zsh
# Deterministic mutation checks: invariant checks, no invented golden text.
'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r root=$1 tmp=$2
source "$root/zhtml2md.zsh" || exit 1
local -a seeds=( '<p>A<a href="x>y">B</a>C</p>' '<ul><li>A</li><li>B</li></ul>' '<table><tr><td>A</td><td>B</td></tr></table>' '<script>"<x>"</script><p>B</p>' '<textarea>&lt;x&gt;</textarea>' '<!-- --><blockquote>A<br>B</blockquote>' '<pre><code>`x`</code></pre>' '<template><ul><li>X</li></ul></template>A' 'é😀&NotEqualTilde;' )
local -a inserts=( '<' '>' '"' "'" '</p>' '&amp;' $'\x00' $'\xff' '$(print BAD)' )
local REPLY chunk fd actual prior diag prior_diag
local -i checks=0 failures=0 st prior_st i step
_zm_read() {
  REPLY=''
  builtin exec {fd}< "$1" || return 1
  while { IFS= builtin read -r -u $fd -k 65536 chunk; } 2>/dev/null || [[ -n $chunk ]]; do REPLY+=$chunk; chunk=''; done
  builtin exec {fd}<&-
}
_zm_case() {
  local data=$1 mode attempt
  builtin printf '%s' "$data" > "$tmp/in"
  for mode in tolerant strict; do
    local -a args=()
    [[ $mode == strict ]] && args=( --strict )
    for attempt in 1 2; do
      zhtml2md "${args[@]}" -- "$tmp/in" > "$tmp/out" 2> "$tmp/err"
      st=$?
      _zm_read "$tmp/out"; actual=$REPLY
      _zm_read "$tmp/err"; diag=$REPLY
      (( ++checks ))
      if (( st != 0 && st != 3 && st != 4 )) ||
         { (( st )) && [[ -n $actual ]]; } ||
         [[ -n $actual && $actual != *$'\n' ]] ||
         [[ $diag == *$'\x1b'* ]] || (( ${#${(f)diag}} > 21 )); then
        (( ++failures )); builtin print -r -u 2 -- "mutations: invalid result case=$checks status=$st"
      fi
      if [[ $attempt == 2 ]] && { (( st != prior_st )) || [[ $actual != "$prior" || $diag != "$prior_diag" ]]; }; then
        (( ++failures )); builtin print -r -u 2 -- "mutations: nondeterministic case=$checks"
      fi
      prior=$actual prior_diag=$diag prior_st=$st
    done
  done
}
local seed insert
for seed in "${seeds[@]}"; do
  # Every byte prefix, including truncations inside UTF-8 and quotes.
  for (( i=0; i<=${#seed}; ++i )); do _zm_case "${seed[1,i]}"; done
  for (( i=1; i<=${#seed}; i+=11 )); do
    _zm_case "${seed[1,i-1]}${seed[i+1,-1]}"
    for insert in "${inserts[@]}"; do _zm_case "${seed[1,i-1]}$insert${seed[i,-1]}"; done
  done
done
builtin print -r -- "mutations: $checks checks, $failures failures"
(( checks > 1000 && failures == 0 ))
