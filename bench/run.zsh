#!/usr/bin/env zsh
# bench/run.zsh - benchmark driver (milestone 0 skeleton; the full
# protocol of plan section 12 lands with milestone 5).
#
# Development-only tooling: uses zmodload zsh/datetime for timing and
# mkdir/rm for the corpus directory. These are never runtime
# dependencies of the library. No network access is performed.
#
# Usage: zsh -df bench/run.zsh

'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte
local LC_ALL=C

zmodload zsh/datetime || {
  builtin print -r -u 2 -- 'bench: zsh/datetime module unavailable (development-only dependency)'
  exit 1
}

local -r root=${${${(%):-%N}:A:h}:h}
local -r corpus=$root/bench/corpus
local -r zsh_exe=${ZHTML2MD_TEST_ZSH:-$(whence -p zsh)}
command mkdir -p -- "$corpus"

# --- corpus generation (deterministic, exact byte counts recorded) -------
# Representative "typical prose/markup" family; more families (code-heavy,
# tables, entity-heavy, discard-heavy) arrive with milestone 5.
local -r para='<p>Shell tools compose. A paragraph of prose with an
<a href="./guide">inline link</a>, some <strong>emphasis</strong>, and
an entity &amp; reference, repeated to build realistic bulk.</p>
<h2>Section heading</h2>
'

_zb_gen() {  # target-bytes outfile
  local -i target=$1
  local s=$para
  while (( ${#s} < target )); do s+=$s; done
  builtin printf '%s' "${s[1,$target]}" > "$2"
}

local -a sizes=( 10240 102400 1048576 )
local -a files=()
local -i sz
for sz in "${sizes[@]}"; do
  local f=$corpus/prose-$sz.html
  [[ -s $f ]] || _zb_gen $sz "$f"
  files+=( "$f" )
done

builtin print -r -- "# zhtml2md benchmark skeleton"
builtin print -r -- "# zsh $ZSH_VERSION on $OSTYPE"
builtin print -r -- ""

# --- cold library load ----------------------------------------------------
local -a cold=()
local -i i
local t0
for (( i = 0; i < 5; i++ )); do
  t0=$EPOCHREALTIME
  "$zsh_exe" -df -c 'builtin source -- "$1"' zsh "$root/zhtml2md.zsh" || {
    builtin print -r -u 2 -- 'bench: cold load failed'; exit 1 }
  cold+=( $(( (EPOCHREALTIME - t0) * 1000 )) )
done
local -a sorted=( ${(on)cold} )
builtin print -r -- "cold load:    median ${sorted[3]} ms  (5 runs: ${(j:, :)cold})"

# --- warm conversions ------------------------------------------------------
# One child process loads the library once and converts each corpus file
# 20 times, reporting per-iteration milliseconds.
local -r child_out=$("$zsh_exe" -df -c '
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  zmodload zsh/datetime
  builtin source -- "$1" || exit 1
  shift
  local f='' t0=0
  local -a ts=()
  local -i i=0
  for f in "$@"; do
    ts=()
    for (( i = 0; i < 20; i++ )); do
      t0=$EPOCHREALTIME
      zhtml2md -- "$f" > /dev/null || exit 2
      ts+=( $(( (EPOCHREALTIME - t0) * 1000 )) )
    done
    builtin print -r -- "${f:t}|${(j: :)ts}"
  done
' zsh "$root/zhtml2md.zsh" "${files[@]}") || {
  builtin print -r -u 2 -- 'bench: warm run failed'; exit 1 }

local line='' f=''
for line in "${(@f)child_out}"; do
  f=${line%%|*}
  local -a ts=( ${(s: :)${line#*|}} )
  local -a st=( ${(on)ts} )
  builtin print -r -- "warm ${f}: median ${st[10]} ms  p95 ${st[19]} ms  (n=20)"
done
for f in "${files[@]}"; do
  builtin print -r -- "corpus ${f:t}: $(command wc -c < "$f") bytes"
done
