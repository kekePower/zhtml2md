# tests/integration/empty-path.zsh - runtime purity: loading and
# conversion must work when no external command lookup is possible.
#
# Run by tests/run.zsh as a separate `zsh -df` process. This script sets
# PATH to an empty directory and then invokes the already-selected Zsh
# executable by absolute path, per the verification contract.

emulate -L zsh -o no_multibyte
local LC_ALL=C

local -i fails=0
_zp_check() {
  if (( $2 != 0 )); then
    (( ++fails ))
    builtin print -r -u 2 -- "empty-path: FAIL: $1"
  fi
}

local -r emptydir=${TMPDIR:-/tmp}/zhtml2md-empty-path.$$
command mkdir -p -- "$emptydir"
trap "command rm -rf -- ${(q)emptydir}" EXIT

local -r zsh_exe=${ZHTML2MD_TEST_ZSH:-zsh}
local -r lib=$ZHTML2MD_ROOT/zhtml2md.zsh
local -r fix=$ZHTML2MD_ROOT/tests/fixtures

# Library loading and repeated conversion with an empty PATH, both from a
# file operand and from stdin. Any hidden external execution would fail
# with "command not found" here.
local out
out=$(
  PATH=$emptydir "$zsh_exe" -df -c '
    source "$1"
    zhtml2md -- "$2" || exit 10
    zhtml2md < "$2" || exit 11
    printf "caf\xc3\xa9 \xf0\x9f\x98\x80\n" | zhtml2md || exit 12
  ' zsh "$lib" "$fix/m1-plain-text.html" 2>/tmp/zhtml2md-ep-err.$$
)
local -i st=$?
local err=$( command cat /tmp/zhtml2md-ep-err.$$ 2>/dev/null )
command rm -f /tmp/zhtml2md-ep-err.$$

(( st == 0 )); _zp_check 'empty-PATH conversion succeeds' $?
local want=$'Hello, world\\!\nHello, world\\!\ncaf\xc3\xa9 \xf0\x9f\x98\x80'
[[ $out == $want ]]; _zp_check 'empty-PATH output correct' $?
[[ -z $err ]]; _zp_check 'empty-PATH stderr empty' $?

# Rejection paths must also work without external commands.
PATH=$emptydir "$zsh_exe" -df "$ZHTML2MD_ROOT/bin/zhtml2md" -- \
  "$fix/m1-reject-nul.html" >/dev/null 2>/tmp/zhtml2md-ep-err2.$$
st=$?
err=$( command cat /tmp/zhtml2md-ep-err2.$$ 2>/dev/null )
command rm -f /tmp/zhtml2md-ep-err2.$$
(( st == 3 )); _zp_check 'empty-PATH rejection status 3' $?
[[ -n $err ]]; _zp_check 'empty-PATH rejection diagnostic present' $?

(( fails == 0 ))
