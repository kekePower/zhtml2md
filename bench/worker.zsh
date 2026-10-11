#!/usr/bin/env zsh
# Measurement worker: only the development timer needs zsh/datetime.
'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte
local LC_ALL=C
zmodload zsh/datetime || exit 1
local -r root=${${${(%):-%N}:A:h}:h} file=$1 runs=$2 scratch=$3
local -F start=$EPOCHREALTIME load_ms first_ms median p95
source "$root/zhtml2md.zsh" || exit 1
load_ms=$(( (EPOCHREALTIME-start)*1000 ))
start=$EPOCHREALTIME
zhtml2md --strict -- "$file" > "$scratch/out" 2> "$scratch/err" || exit 1
first_ms=$(( (EPOCHREALTIME-start)*1000 ))
local fd chunk actual='' expected=''
builtin exec {fd}< "$scratch/out" || exit 1
while { IFS= builtin read -r -u $fd -k 65536 chunk; } 2>/dev/null || [[ -n $chunk ]]; do actual+=$chunk; chunk=''; done
builtin exec {fd}<&-
builtin exec {fd}< "${file%.html}.md" || exit 1
while { IFS= builtin read -r -u $fd -k 65536 chunk; } 2>/dev/null || [[ -n $chunk ]]; do expected+=$chunk; chunk=''; done
builtin exec {fd}<&-
[[ $actual == "$expected" && ! -s $scratch/err ]] || { builtin print -r -u 2 -- "bench: preservation mismatch ${file:t}"; exit 1 }
local -i output_bytes=${#actual} input_bytes=0 i
actual='' expected=''
builtin exec {fd}< "$file" || exit 1
while { IFS= builtin read -r -u $fd -k 65536 chunk; } 2>/dev/null || [[ -n $chunk ]]; do (( input_bytes+=${#chunk} )); chunk=''; done
builtin exec {fd}<&-
local -a samples=() ordered
for (( i=0; i<runs; ++i )); do
  start=$EPOCHREALTIME
  zhtml2md --strict -- "$file" > /dev/null 2> "$scratch/err" || exit 1
  samples+=( $(( (EPOCHREALTIME-start)*1000 )) )
done
# Zsh's numeric string sort compares integer prefixes, so fractional ties
# need actual arithmetic comparison. Sorting is outside the timed calls.
ordered=( "${samples[@]}" )
local -i j
local sample
for (( i=2; i<=runs; ++i )); do
  sample=$ordered[$i]
  j=$(( i-1 ))
  while (( j >= 1 && sample < ordered[j] )); do
    ordered[j+1]=$ordered[$j]
    (( --j ))
  done
  ordered[j+1]=$sample
done
median=$ordered[$(( (runs+1)/2 ))]
p95=$ordered[$(( (95*runs+99)/100 ))]
builtin printf '%s\t%s\t%d\t%d\t%d\t%.3f\t%.3f\t%.3f\t%.3f\n' \
  "${file:t}" "$ZSH_VERSION" $input_bytes $output_bytes $runs $load_ms $first_ms $median $p95
builtin print -r -- "${file:t}"$'\t'"${(pj:\t:)samples}" > "$scratch/samples"
