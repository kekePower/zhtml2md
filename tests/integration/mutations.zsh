# The timeout is a development-harness dependency, never a runtime one.
emulate -L zsh -o no_multibyte
local -r tmp=${TMPDIR:-/tmp}/zhtml2md-mutations.$$
command mkdir -p -- "$tmp" || exit 1
trap "command rm -rf -- ${(q)tmp}" EXIT
command timeout --kill-after=2 120 "$ZHTML2MD_TEST_ZSH" -df \
  "$ZHTML2MD_ROOT/tests/mutations/worker.zsh" "$ZHTML2MD_ROOT" "$tmp"
