# tests/integration/io-errors.zsh - input/output failure behavior:
# missing files, directories, hostile filenames, and write failures.

emulate -L zsh -o no_multibyte
local LC_ALL=C

local -i fails=0
_zi_check() {
  if (( $2 != 0 )); then
    (( ++fails ))
    builtin print -r -u 2 -- "io-errors: FAIL: $1"
  fi
}

local -r tmp=${TMPDIR:-/tmp}/zhtml2md-io.$$
command mkdir -p -- "$tmp"
trap "command rm -rf -- ${(q)tmp}" EXIT

local -r zsh_exe=${ZHTML2MD_TEST_ZSH:-zsh}
local -r cli=$ZHTML2MD_ROOT/bin/zhtml2md

local out err
local -i st

# Missing file.
out=$( "$zsh_exe" -df "$cli" -- "$tmp/does-not-exist.html" 2>"$tmp/err" )
st=$?
err=$( <"$tmp/err" )
(( st == 1 )); _zi_check 'missing file status 1' $?
[[ -z $out ]]; _zi_check 'missing file stdout empty' $?
[[ $err == "zhtml2md: input-io: cannot open input file" ]]
_zi_check 'missing file diagnostic' $?

# Directory operand.
out=$( "$zsh_exe" -df "$cli" -- "$tmp" 2>"$tmp/err" )
st=$?
err=$( <"$tmp/err" )
(( st == 1 )); _zi_check 'directory status 1' $?
[[ -z $out ]]; _zi_check 'directory stdout empty' $?
[[ $err == "zhtml2md: input-io: input is a directory" ]]
_zi_check 'directory diagnostic' $?

# Filenames with whitespace, glob characters, and newlines are literal.
builtin printf 'space name\n' > "$tmp/weird name.html"
builtin printf 'glob name\n' > "$tmp/star*name.html"
builtin printf 'newline name\n' > "$tmp/new"$'\n'"line.html"
out=$( "$zsh_exe" -df "$cli" -- "$tmp/weird name.html" 2>/dev/null )
[[ $out == "space name" ]]; _zi_check 'space filename' $?
out=$( "$zsh_exe" -df "$cli" -- "$tmp/star*name.html" 2>/dev/null )
[[ $out == "glob name" ]]; _zi_check 'glob filename' $?
out=$( "$zsh_exe" -df "$cli" -- "$tmp/new"$'\n'"line.html" 2>/dev/null )
[[ $out == "newline name" ]]; _zi_check 'newline filename' $?

# Leading-dash filename requires --; without it, it is a usage error.
builtin printf 'dash file\n' > "$tmp/-dash.html"
(
  cd -- "$tmp"
  out=$( "$zsh_exe" -df "$cli" -- ./-dash.html 2>/dev/null )
  [[ $out == "dash file" ]]; _zi_check 'dash filename after --' $?
  out=$( "$zsh_exe" -df "$cli" -- -dash.html 2>/dev/null )
  [[ $out == "dash file" ]]; _zi_check 'bare dash filename after --' $?
  "$zsh_exe" -df "$cli" -dash.html >/dev/null 2>/dev/null
  (( $? == 2 )); _zi_check 'bare dash filename without -- is usage error' $?
)

# Explicit - operand reads stdin.
out=$( builtin printf 'dash stdin\n' | "$zsh_exe" -df "$cli" - 2>/dev/null )
[[ $out == "dash stdin" ]]; _zi_check 'dash operand reads stdin' $?

# Output write failure (/dev/full): status 1, bounded diagnostic.
if [[ -w /dev/full ]]; then
  "$zsh_exe" -df "$cli" -- \
    "$ZHTML2MD_ROOT/tests/fixtures/m1-plain-text.html" > /dev/full 2>"$tmp/err"
  st=$?
  err=$( <"$tmp/err" )
  (( st == 1 )); _zi_check 'write failure status 1' $?
  [[ $err == "zhtml2md: output-io: write to stdout failed" ]]
  _zi_check 'write failure diagnostic' $?
fi

(( fails == 0 ))
