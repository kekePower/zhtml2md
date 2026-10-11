# Literal shell data, 100-call retained-state stability and installed layout.
'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r root=$ZHTML2MD_ROOT tmp=${TMPDIR:-/tmp}/zhtml2md-hardening.$$
command mkdir -p -- "$tmp/installed/lib" "$tmp/installed/bin" "$tmp/installed/data" "$tmp/empty" || exit 1
trap "command rm -rf -- ${(q)tmp}" EXIT
source "$root/zhtml2md.zsh" || exit 1
local -i failures=0 checks=0 i st
_zh_check() {
  (( ++checks ))
  if (( $2 )); then (( ++failures )); builtin print -r -u 2 -- "hardening: FAIL $1"; fi
}
local payload='$(print EXECUTED > '"${(q)tmp}/marker"') `print EXECUTED` ${HOME} $((1+2)) * ? [a] (#b) %n'
builtin printf '%s' "<pre>$payload</pre><a href='$payload'>X</a><img src='$payload' alt='Y'>" > "$tmp/in"
zhtml2md --strict -- "$tmp/in" > "$tmp/out" 2> "$tmp/err"
_zh_check 'shell syntax remains data' $?
[[ ! -e $tmp/marker && ! -s $tmp/err ]]; _zh_check 'payload executes no side effect' $?
local bad='<ol start="'"$payload"'"><li value="1+1">A</li></ol><table><tr><td rowspan="x[1]" colspan="$((2))">B</td></tr></table>'
builtin printf '%s' "$bad" > "$tmp/in"
zhtml2md -- "$tmp/in" > "$tmp/out" 2> "$tmp/err"
_zh_check 'invalid numeric attributes use defaults' $?
[[ $(<"$tmp/out") == $'1. A\n\n|  |\n| --- |\n| B |' ]]; _zh_check 'numeric fallback bytes' $?
[[ ! -e $tmp/marker ]]; _zh_check 'numeric data executes no side effect' $?
zhtml2md --strict -- "$tmp/in" > "$tmp/out" 2> "$tmp/err"
st=$?
(( st == 3 )) && [[ ! -s $tmp/out ]]; _zh_check 'strict numeric rejection buffers stdout' $?
# Initialize once, then compare every persistent library parameter's value.
zhtml2md --strict -- "$root/tests/fixtures/m4-acceptance-strict.html" > /dev/null || exit 1
local -a names=( ${(ok)parameters} ) owned=() before_fds after_fds
local name before after
for name in "${names[@]}"; do [[ $name == _ZHTML2MD* || $name == _zhtml2md* ]] && owned+=( "$name" ); done
before=$(builtin typeset -p -- "${owned[@]}")
before_fds=( /proc/self/fd/*(N) )
for (( i=0; i<100; ++i )); do
  zhtml2md --strict -- "$root/tests/fixtures/m4-acceptance-strict.html" > /dev/null 2> "$tmp/err" || exit 1
done
after=$(builtin typeset -p -- "${owned[@]}")
local -a after_names=( ${(ok)parameters} ) after_owned=()
for name in "${after_names[@]}"; do [[ $name == _ZHTML2MD* || $name == _zhtml2md* ]] && after_owned+=( "$name" ); done
[[ "${(j: :)owned}" == "${(j: :)after_owned}" ]]; _zh_check 'no growth of persistent library parameter names' $?
[[ $before == "$after" ]]; _zh_check 'immutable state stays fixed across 100 complete calls' $?
after_fds=( /proc/self/fd/*(N) )
[[ "${(j: :)before_fds}" == "${(j: :)after_fds}" ]]; _zh_check 'no descriptor growth across complete calls' $?
# Copy the runtime layout using development-only tools.
command cp -- "$root/zhtml2md.zsh" "$tmp/installed/" || exit 1
command cp -- "$root"/lib/*.zsh "$tmp/installed/lib/" || exit 1
command cp -- "$root/bin/zhtml2md" "$tmp/installed/bin/" || exit 1
command cp -- "$root/data/entities.tsv" "$tmp/installed/data/" || exit 1
local -r shell=$ZHTML2MD_TEST_ZSH
PATH=$tmp/empty "$shell" -df -c '
  builtin cd / || exit 1
  module_path=( /nonexistent-zhtml2md-modules )
  source "$1/zhtml2md.zsh" || exit 1
  source "$1/zhtml2md.zsh" || exit 1
  zhtml2md --strict -- "$2"
' zsh "$tmp/installed" "$root/tests/fixtures/m4-acceptance-strict.html" > "$tmp/library" 2> "$tmp/err"
_zh_check 'installed library outside checkout with no lookup' $?
( builtin cd / || exit 1; PATH=$tmp/empty "$shell" -df "$tmp/installed/bin/zhtml2md" --strict -- "$root/tests/fixtures/m4-acceptance-strict.html" ) > "$tmp/cli" 2> "$tmp/err"
_zh_check 'installed CLI succeeds' $?
[[ $(<"$tmp/cli") == "$(<"$tmp/library")" && ! -s $tmp/err ]]; _zh_check 'installed CLI and library agree' $?
# Restoring ALIASES must not expose the wrapper's final function call.
PATH=$tmp/empty "$shell" -df -c '
  module_path=( /nonexistent-zhtml2md-modules )
  alias zhtml2md="builtin print -r -- HIJACKED"
  builtin source "$1/bin/zhtml2md" --strict -- "$2"
' zsh "$tmp/installed" "$root/tests/fixtures/m4-acceptance-strict.html" > "$tmp/alias-cli" 2> "$tmp/err"
local -i alias_status=$?
(( alias_status == 0 )) && [[ $(<"$tmp/alias-cli") == "$(<"$tmp/library")" && ! -s $tmp/err ]]
_zh_check 'CLI dispatch survives a preexisting public alias' $?
# Preserve ALIASES=off too; loader snapshots must not assume defaults.
() {
  unsetopt aliases
  source "$root/zhtml2md.zsh" || exit 1
  [[ ! -o aliases ]]; _zh_check 'disabled aliases remain disabled' $?
}
builtin print -r -- "hardening: $checks checks, $failures failures"
(( failures == 0 ))
