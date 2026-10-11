#!/usr/bin/env zsh
# Full offline conversion benchmark. GNU time is optional, development-only.
# Usage: zsh -df bench/run.zsh [RUNS>=20] [FILES...] > results.tsv
'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte -o extended_glob
local LC_ALL=C
local -r root=${${${(%):-%N}:A:h}:h}
local zsh_exe=${ZHTML2MD_TEST_ZSH:-$(whence -p zsh)}
local runs=${1:-20}
[[ $runs == [0-9]## && ${#runs} -le 4 ]] && (( runs >= 20 && runs <= 1000 )) || { builtin print -r -u 2 -- 'bench: runs must be 20..1000'; exit 2 }
(( $# )) && shift
local -a files=( "$@" )
if (( ! ${#files} )); then
  "$zsh_exe" -df "$root/bench/gen-corpus.zsh" > /dev/null || exit 1
  files=( "$root"/bench/generated/*.html(N) )
fi
(( ${#files} )) || exit 2
zmodload zsh/datetime || exit 1
local -r tmp=${TMPDIR:-/tmp}/zhtml2md-bench.$$
command mkdir -p -- "$tmp" || exit 1
trap "command rm -rf -- ${(q)tmp}" EXIT
local -a timer=()
[[ -x /usr/bin/time ]] && timer=( /usr/bin/time -f '%M' )
local file row worker_rss cli_rss start cli_ms
if [[ -n $ZHTML2MD_BENCH_SAMPLES && ! -s $ZHTML2MD_BENCH_SAMPLES ]]; then
  {
    builtin printf 'case'
    local -i sample_index
    for (( sample_index=1; sample_index<=runs; ++sample_index )); do
      builtin printf '\twarm_ms_%d' $sample_index
    done
    builtin printf '\n'
  } > "$ZHTML2MD_BENCH_SAMPLES" || exit 1
fi
builtin print -r -- $'case\tzsh\tinput_bytes\toutput_bytes\truns\tload_ms\tfirst_ms\twarm_median_ms\twarm_p95_ms\tcli_ms\tworker_peak_kib\tcli_peak_kib'
for file in "${files[@]}"; do
  builtin print -r -u 2 -- "bench: ${file:t} ($runs warm runs)"
  local -a measure=( "${timer[@]}" )
  (( ${#measure} )) && measure+=( -o "$tmp/worker.rss" )
  row=$( "${measure[@]}" "$zsh_exe" -df "$root/bench/worker.zsh" "$file" "$runs" "$tmp" ) || exit 1
  worker_rss=unavailable
  [[ -r $tmp/worker.rss ]] && worker_rss=$(<"$tmp/worker.rss")
  measure=( "${timer[@]}" )
  (( ${#measure} )) && measure+=( -o "$tmp/cli.rss" )
  start=$EPOCHREALTIME
  "${measure[@]}" "$zsh_exe" -df "$root/bin/zhtml2md" --strict -- "$file" > /dev/null 2> "$tmp/err" || exit 1
  cli_ms=$(( (EPOCHREALTIME-start)*1000 ))
  cli_rss=unavailable
  [[ -r $tmp/cli.rss ]] && cli_rss=$(<"$tmp/cli.rss")
  builtin printf '%s\t%.3f\t%s\t%s\n' "$row" $cli_ms "$worker_rss" "$cli_rss"
  if [[ -n $ZHTML2MD_BENCH_SAMPLES ]]; then
    builtin print -r -- "$(<"$tmp/samples")" >> "$ZHTML2MD_BENCH_SAMPLES" || exit 1
  fi
done
exit 0
