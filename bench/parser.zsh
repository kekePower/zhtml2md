#!/usr/bin/env zsh
# Development-only parser probe. Measures warm parsing/events with a
# no-op sink, not complete Markdown conversion. No runtime dependency.
# Usage: zsh -df bench/parser.zsh [RUNS [FILE...]] (default 20 runs).
emulate -L zsh -o no_multibyte -o extended_glob
local LC_ALL=C
local -r root=${${${(%):-%N}:A:h}:h}
local run_text=${1:-20}
[[ $run_text == [0-9]## && ${#run_text} -le 4 ]] || exit 2
local -i runs=$(( 10#$run_text ))
(( runs >= 1 && runs <= 1000 )) || exit 2
(( $# )) && shift
local -a files=( "$@" )
(( ${#files} )) || files=( "$root/bench/corpus/prose-10240.html" "$root/bench/corpus/prose-102400.html" "$root/bench/corpus/prose-1048576.html" )
zmodload zsh/datetime || exit 1
source "$root/zhtml2md.zsh" || exit 1
_zhtml2md_parse_event() { emulate -L zsh -o no_multibyte; return 0; }
local _zhtml2md_input='' _zhtml2md_in_path='' _zhtml2md_strict=0
local -i _zhtml2md_bom=0 _zhtml2md_diag_emitted=0 _zhtml2md_diag_total=0 _zhtml2md_diag_capped=0
local f
local -F start elapsed
local -i i median_idx=$(( (runs+1)/2 )) p95_idx=$(( (runs*95+99)/100 ))
local -a times=() sorted=()
builtin print -r -- "parser-only warm probe: zsh $ZSH_VERSION / $OSTYPE; n=$runs; no Markdown sink"
for f in "${files[@]}"; do
  _zhtml2md_in_path=$f
  _zhtml2md_read_all && _zhtml2md_validate_encoding || exit $?
  _zhtml2md_parse 2>/dev/null || exit $?
  times=()
  for (( i=0; i < runs; ++i )); do
    _zhtml2md_diag_emitted=0; _zhtml2md_diag_total=0; _zhtml2md_diag_capped=0
    start=$EPOCHREALTIME
    _zhtml2md_parse 2>/dev/null || exit $?
    (( elapsed = (EPOCHREALTIME-start) * 1000 ))
    times+=( $elapsed )
  done
  sorted=( ${(on)times} )
  builtin printf '%s: %d bytes; median %.3f ms; p95 %.3f ms\n' \
    "${f:t}" ${#_zhtml2md_input} ${sorted[$median_idx]} ${sorted[$p95_idx]}
done
