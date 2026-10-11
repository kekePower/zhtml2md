# SPDX-License-Identifier: Apache-2.0
# lib/_zhtml2md_render.zsh - diagnostics, bounded output, rendering.
#
# Sourced by zhtml2md.zsh. See that file for the load-time guard
# rationale.


'builtin' 'typeset' _zhtml2md_render_loadopt="$( 'builtin' 'set' '+o' )"
'builtin' 'setopt' 'noaliases'
if [[ $'\n'$_zhtml2md_render_loadopt$'\n' == *$'\nset +o noaliases\n'* ||
      $'\n'$_zhtml2md_render_loadopt$'\n' == *$'\nset -o aliases\n'* ]]; then
  _zhtml2md_render_loadopt=on
else
  _zhtml2md_render_loadopt=off
fi

# ---------------------------------------------------------------------------
# Diagnostics
#
# Envelope: zhtml2md: CATEGORY at byte OFFSET: MESSAGE
# Offsets are zero-based byte positions in the original input including
# any BOM; operational failures omit the offset field. At most
# _ZHTML2MD_WARN_CAP individual diagnostics are printed; the remainder is
# aggregated into one summary by _zhtml2md_diag_finish.

# _zhtml2md_diag CATEGORY OFFSET MESSAGE
#   Bounded warning diagnostic. OFFSET may be empty.
#   Reads/writes: _zhtml2md_diag_emitted, _zhtml2md_diag_total,
#                 _zhtml2md_diag_capped
_zhtml2md_diag() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _category=$1 _offset=$2 _message=$3
  (( ++_zhtml2md_diag_total ))
  if (( _zhtml2md_diag_emitted >= _ZHTML2MD_WARN_CAP )); then
    _zhtml2md_diag_capped=1
    return 0
  fi
  (( ++_zhtml2md_diag_emitted ))
  # Sanitize source-derived text: make controls visible, bound to 80 bytes.
  _message=${(V)_message}
  (( ${#_message} > 80 )) && _message=${_message[1,80]}
  if [[ -n $_offset ]]; then
    builtin print -r -u 2 -- "zhtml2md: $_category at byte $_offset: $_message"
  else
    builtin print -r -u 2 -- "zhtml2md: $_category: $_message"
  fi
}

# _zhtml2md_fail CATEGORY OFFSET MESSAGE STATUS
#   Unconditional fatal diagnostic (never suppressed by the warning cap).
#   Reads/writes: _zhtml2md_diag_emitted, _zhtml2md_diag_total
_zhtml2md_fail() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _category=$1 _offset=$2 _message=$3
  (( ++_zhtml2md_diag_total, ++_zhtml2md_diag_emitted ))
  _message=${(V)_message}
  (( ${#_message} > 80 )) && _message=${_message[1,80]}
  if [[ -n $_offset ]]; then
    builtin print -r -u 2 -- "zhtml2md: $_category at byte $_offset: $_message"
  else
    builtin print -r -u 2 -- "zhtml2md: $_category: $_message"
  fi
}

# _zhtml2md_diag_finish
#   Emits the aggregate summary once the warning cap suppressed output.
_zhtml2md_diag_finish() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  if (( _zhtml2md_diag_capped )); then
    builtin print -r -u 2 -- \
      "zhtml2md: warning-summary: $(( _zhtml2md_diag_total - _zhtml2md_diag_emitted )) further warnings suppressed"
  fi
}

# ---------------------------------------------------------------------------
# Output

# _zhtml2md_emit
#   Writes the buffered Markdown to stdout with a literal constant
#   format. Empty output emits zero bytes.
#   Reads: _zhtml2md_output
#   Status: 0 ok, 1 output-io
_zhtml2md_emit() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  [[ -z $_zhtml2md_output ]] && return 0
  builtin printf '%s' "$_zhtml2md_output" 2>/dev/null || {
    _zhtml2md_fail output-io '' 'write to stdout failed' 1
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# Rendering

# _zhtml2md_render
#   Converts the validated input into buffered Markdown.
#   Reads:  _zhtml2md_input, _zhtml2md_bom, _zhtml2md_strict
#   Writes: _zhtml2md_output
#   Status: 0 ok, 3 strict rejection, 4 resource-limit
#
# The Markdown module owns invocation-local captures and consumes parser
# events. Nothing reaches stdout until the complete conversion succeeds.
_zhtml2md_render() {
  emulate -L zsh -o no_multibyte -o extended_glob
  local LC_ALL=C
  _zhtml2md_markdown
}

# Restore the caller's ALIASES setting (see the guard at the top).
if [[ $_zhtml2md_render_loadopt == on ]]; then
  'builtin' 'setopt' 'aliases'
fi
'builtin' 'unset' _zhtml2md_render_loadopt
