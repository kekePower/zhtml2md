# tests/integration/limits.zsh - resource-limit boundaries. The input
# limit is exercised at exactly 4 MiB and one byte beyond; payloads are
# generated with builtins so no large fixture files are committed.

emulate -L zsh -o no_multibyte
local LC_ALL=C

local -i fails=0
_zl2_check() {
  if (( $2 != 0 )); then
    (( ++fails ))
    builtin print -r -u 2 -- "limits: FAIL: $1"
  fi
}

local -r zsh_exe=${ZHTML2MD_TEST_ZSH:-zsh}
local -r cli=$ZHTML2MD_ROOT/bin/zhtml2md
local -r tmp=${TMPDIR:-/tmp}/zhtml2md-lim.$$
command mkdir -p -- "$tmp"
trap "command rm -rf -- ${(q)tmp}" EXIT

local -i st
local err

# Exactly at the limit: succeeds. The payload is spaces ending in 'x',
# so prose whitespace collapses and the output is x plus one LF.
builtin printf '%4194304s' x | "$zsh_exe" -df "$cli" > "$tmp/out" 2>/dev/null
st=$?
(( st == 0 )); _zl2_check 'input at 4 MiB limit accepted' $?
local got=$( <"$tmp/out" )
[[ $got == x ]]
_zl2_check 'limit-boundary prose whitespace collapses' $?

# One byte beyond: status 4, empty stdout, resource-limit diagnostic.
builtin printf '%4194305s' x | "$zsh_exe" -df "$cli" > "$tmp/out" 2>"$tmp/err"
st=$?
err=$( <"$tmp/err" )
(( st == 4 )); _zl2_check 'input one byte over limit rejected with 4' $?
[[ ! -s $tmp/out ]]; _zl2_check 'over-limit stdout empty' $?
[[ $err == "zhtml2md: resource-limit: input exceeds 4194304 bytes" ]]
_zl2_check 'over-limit diagnostic' $?

(( fails == 0 ))
