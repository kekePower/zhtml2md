#!/usr/bin/env zsh
# tests/run.zsh - mandatory offline fixture and integration runner.
#
# Usage: zsh -df tests/run.zsh
#
# Written in Zsh so the core contract can be verified with Zsh alone.
# Filesystem setup and the mutation timeout use development utilities;
# the library and CLI under test never require external commands.
#
# Fixture layout (tests/fixtures/NAME.*):
#   .html     input bytes (required)
#   .md       exact expected stdout (required; empty file allowed)
#   .status   expected exit status (required, decimal)
#   .opts     optional extra CLI arguments, space-separated, one line
#   .stderr   optional exact expected stderr; absent means "expect empty"
#   .stdin    optional marker file: feed input via stdin, not an operand
#   .noinput  optional marker file: pass no input at all (--help etc.)

'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte
local LC_ALL=C

local -r root=${${${(%):-%N}:A:h}:h}
local -r fixdir=$root/tests/fixtures
local -r intdir=$root/tests/integration
local zsh_exe=${ZHTML2MD_TEST_ZSH:-$(whence -p zsh)}

local -i pass=0 fail=0
local -a failures=()

# Byte-exact file read preserving trailing newlines (command substitution
# alone cannot do that).
_zt_read_file() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  REPLY=''
  local _fd _chunk
  { exec {_fd}< "$1" ; } 2>/dev/null || return 1
  while { IFS= read -r -u $_fd -k 65536 _chunk ; } 2>/dev/null || (( ${#_chunk} > 0 )); do
    (( ${#_chunk} == 0 )) && break
    REPLY+=$_chunk
    _chunk=''
  done
  { exec {_fd}<&- ; } 2>/dev/null
  return 0
}

_zt_report() {  # name ok detail
  if (( $2 )); then
    (( ++pass ))
  else
    (( ++fail ))
    failures+=( "$1: $3" )
    builtin print -r -- "FAIL $1: $3"
  fi
}

# --- 1. parse checks -------------------------------------------------------
local -a sources=( "$root"/zhtml2md.zsh "$root"/lib/*.zsh(N) "$root"/bin/zhtml2md(N)
                   "$root"/tests/*.zsh(N) "$root"/tests/parser/*.zsh(N) "$root"/tests/mutations/*.zsh(N)
                   "$root"/tests/integration/*.zsh(N) "$root"/bench/*.zsh(N) )
local f
for f in "${sources[@]}"; do
  if "$zsh_exe" -f -n -- "$f" 2>/dev/null; then
    _zt_report "parse:${f#$root/}" 1 ''
  else
    _zt_report "parse:${f#$root/}" 0 'zsh -f -n failed'
  fi
done

# --- 2. fixtures -----------------------------------------------------------
local -r tmp=${TMPDIR:-/tmp}/zhtml2md-tests.$$
command mkdir -p -- "$tmp" || { builtin print -r -u 2 -- "cannot create $tmp"; exit 1 }
trap "command rm -rf -- ${(q)tmp}" EXIT

local -a fixtures=( "$fixdir"/*.html(N) )
local name base input exp_md exp_status exp_err act_md act_err
local -a optwords
local -i st ok
for f in "${fixtures[@]}"; do
  name=${${f:t}%.html}
  _zt_read_file "$f"; input=$REPLY
  _zt_read_file "$fixdir/$name.md"; exp_md=$REPLY
  _zt_read_file "$fixdir/$name.status"; exp_status=${REPLY%$'\n'}

  optwords=()
  if [[ -e $fixdir/$name.opts ]]; then
    _zt_read_file "$fixdir/$name.opts"
    optwords=( ${(s: :)${REPLY%$'\n'}} )
  fi

  if [[ -e $fixdir/$name.stdin ]]; then
    "$zsh_exe" -df "$root/bin/zhtml2md" "${optwords[@]}" < "$f" \
      > "$tmp/out" 2> "$tmp/err"
  elif [[ -e $fixdir/$name.noinput ]]; then
    "$zsh_exe" -df "$root/bin/zhtml2md" "${optwords[@]}" \
      < /dev/null > "$tmp/out" 2> "$tmp/err"
  else
    "$zsh_exe" -df "$root/bin/zhtml2md" "${optwords[@]}" "$f" \
      > "$tmp/out" 2> "$tmp/err"
  fi
  st=$?

  _zt_read_file "$tmp/out"; act_md=$REPLY
  _zt_read_file "$tmp/err"; act_err=$REPLY

  ok=1
  local detail=''
  if [[ $st != $exp_status ]]; then
    ok=0; detail="status: got $st want $exp_status"
  elif [[ $act_md != $exp_md ]]; then
    ok=0; detail="stdout: got ${#act_md} bytes want ${#exp_md} bytes"
  elif [[ -e $fixdir/$name.stderr ]]; then
    _zt_read_file "$fixdir/$name.stderr"; exp_err=$REPLY
    if [[ $act_err != $exp_err ]]; then
      ok=0; detail="stderr: got ${(q)act_err} want ${(q)exp_err}"
    fi
  elif [[ -n $act_err ]]; then
    ok=0; detail="stderr: expected empty, got ${(q)act_err}"
  fi
  _zt_report "fixture:$name" $ok "$detail"
done

# --- 3. tokenizer/frame component fixtures ----------------------------------
for f in "$root"/tests/parser/fixtures/*.html(N); do
  name=${${f:t}%.html}
  base=$root/tests/parser/fixtures/$name
  _zt_read_file "$base.mode"; local parser_mode=${REPLY%$'\n'}
  _zt_read_file "$base.strict"; local parser_strict=${REPLY%$'\n'}
  _zt_read_file "$base.status"; exp_status=${REPLY%$'\n'}
  _zt_read_file "$base.events"; exp_md=$REPLY
  _zt_read_file "$base.stderr"; exp_err=$REPLY
  "$zsh_exe" -df "$root/tests/parser/runner.zsh" "$parser_mode" "$f" "$parser_strict" \
    > "$tmp/out" 2> "$tmp/err"
  st=$?
  _zt_read_file "$tmp/out"; act_md=$REPLY
  _zt_read_file "$tmp/err"; act_err=$REPLY
  ok=1; detail=''
  if [[ $st != $exp_status ]]; then
    ok=0; detail="status: got $st want $exp_status"
  elif [[ $act_md != $exp_md ]]; then
    ok=0; detail="events: got ${(q)act_md} want ${(q)exp_md}"
  elif [[ $act_err != $exp_err ]]; then
    ok=0; detail="diagnostics: got ${(q)act_err} want ${(q)exp_err}"
  fi
  _zt_report "parser:$name" $ok "$detail"
done

# --- 4. integration scripts -------------------------------------------------
local -a scripts=( "$intdir"/*.zsh(N) )
for f in "${scripts[@]}"; do
  if ZHTML2MD_ROOT=$root ZHTML2MD_TEST_ZSH=$zsh_exe "$zsh_exe" -df "$f" \
       > "$tmp/itout" 2> "$tmp/iterr"; then
    _zt_report "integration:${${f:t}%.zsh}" 1 ''
  else
    _zt_read_file "$tmp/itout"; local _o=$REPLY
    _zt_read_file "$tmp/iterr"; local _e=$REPLY
    _zt_report "integration:${${f:t}%.zsh}" 0 "exit=$? stdout=${(q)_o} stderr=${(q)_e}"
  fi
done

builtin print -r -- "zhtml2md tests: $pass passed, $fail failed"
(( fail == 0 ))
