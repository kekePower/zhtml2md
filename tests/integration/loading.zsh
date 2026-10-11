#!/usr/bin/env zsh
# tests/integration/loading.zsh - library loading and caller-state
# preservation under a deliberately hostile caller environment.
#
# Run by tests/run.zsh as a separate `zsh -df` process with
# ZHTML2MD_ROOT set. Exits nonzero on any failed assertion.
#
# Helper functions are defined before the hostile aliases so their bodies
# parse cleanly; alias expansion is a parse-time event, so arming the
# aliases afterwards still exposes the subsequently *parsed* library.
local -i _zl_fails=0

_zl_check() {  # label status (0 = pass)
  if (( $2 != 0 )); then
    (( ++_zl_fails ))
    builtin print -r -u 2 -- "loading: FAIL: $1"
  fi
}

_zl_snap() {
  # Snapshot caller-visible shell state into _zl_state/_zl_params.
  # NB: zsh re-parses $( ) bodies at execution time, so command words
  # inside substitutions are quoted to defeat the armed aliases.
  _zl_state="opts=${(F)${(@kv)options}}
aliases=${(F)${(o)$( 'alias' )}}
traps=$( 'builtin' 'trap' )
ifs=${(q)IFS}
pwd=$PWD
path=${(q)path}
fpath=${(q)fpath}"
  if [[ -d /proc/self/fd ]]; then
    local -a _fds=( /proc/self/fd/*(N) )
    _zl_state+="
fds=${(F)_fds}"
  fi
  _zl_params=( ${(ok)parameters} )
}

_zl_main() {
  emulate -L zsh
  setopt ksh_arrays sh_word_split glob_subst 2>/dev/null

  local _zl_state
  local -a _zl_params

  # --- hostile loading ---
  _zl_snap
  local _before=$_zl_state
  local -a _before_params=( "${_zl_params[@]}" )

  local _load_out _load_err
  _load_out=$( 'builtin' 'source' -- "$ZHTML2MD_ROOT/zhtml2md.zsh" \
                 2>/tmp/zhtml2md-load-err.$$ )
  _load_err=$( 'command' 'cat' /tmp/zhtml2md-load-err.$$ 2>/dev/null )
  command rm -f /tmp/zhtml2md-load-err.$$

  [[ -z $_load_out ]]; _zl_check 'load produces no stdout' $?
  [[ -z $_load_err ]]; _zl_check 'load produces no stderr' $?

  _zl_snap
  [[ $_zl_state == $_before ]]
  _zl_check 'caller state preserved across load' $?

  # New global parameters must be library-owned and namespaced.
  local -a _after_params=( ${(ok)parameters} )
  local -a _new=( ${_after_params:|_before_params} )
  local -a _bad=( ${_new:#_zhtml2md*} )
  _bad=( ${_bad:#_ZHTML2MD*} )
  (( ${#_bad} == 0 )); _zl_check 'no non-namespaced globals leaked' $?

  # The library must not have defined or altered aliases.
  [[ ${(F)${(o)$(alias)}} == *HIJACKED-public* ]]
  _zl_check 'caller aliases preserved' $?

  # --- repeated sourcing ---
  'builtin' 'source' -- "$ZHTML2MD_ROOT/zhtml2md.zsh"
  local -i _st1=$?
  'builtin' 'source' -- "$ZHTML2MD_ROOT/zhtml2md.zsh"
  local -i _st2=$?
  (( _st1 == 0 && _st2 == 0 ))
  _zl_check 'repeated sourcing succeeds' $?

  # Cold entity initialization and decoding must also survive aliases
  # armed before the implementation modules are parsed.
  local _zhtml2md_decoded=''
  local -i _zhtml2md_diag_emitted=0 _zhtml2md_diag_total=0 _zhtml2md_diag_capped=0
  '_zhtml2md_decode_entities' '&NotEqualTilde;&#x1F600;' 0
  (( $? == 0 )); _zl_check 'entity decoding under hostile aliases succeeds' $?
  [[ $_zhtml2md_decoded == $'\xe2\x89\x82\xcc\xb8\xf0\x9f\x98\x80' ]]
  _zl_check 'entity decoding under hostile aliases has exact bytes' $?

  local _zhtml2md_input='<ul><li>a&amp;b</li></ul>' _zhtml2md_strict=1 _zhtml2md_bom=0
  '_zhtml2md_parse'
  (( $? == 0 )); _zl_check 'parser under hostile aliases succeeds' $?

  # --- conversion under hostile options ---
  local _out1 _out2
  _out1=$( 'zhtml2md' -- "$ZHTML2MD_ROOT/tests/fixtures/m1-plain-text.html" 2>/dev/null )
  local -i _cst=$?
  (( _cst == 0 )); _zl_check 'conversion succeeds under hostile options' $?
  [[ $_out1 == 'Hello, world\!' ]]; _zl_check 'conversion output correct' $?
  _out2=$( 'zhtml2md' -- "$ZHTML2MD_ROOT/tests/fixtures/m1-plain-text.html" 2>/dev/null )
  [[ $_out1 == "$_out2" ]]; _zl_check 'repeated conversion deterministic' $?

  # Failing call must also preserve state.
  'zhtml2md' -- "$ZHTML2MD_ROOT/tests/fixtures/m1-reject-nul.html" >/dev/null 2>/dev/null
  (( $? == 3 )); _zl_check 'rejected input returns 3' $?

  _zl_snap
  [[ $_zl_state == $_before ]]
  _zl_check 'caller state preserved across calls' $?

  # --- descriptor stability across repeated conversions ---
  if [[ -d /proc/self/fd ]]; then
    local -a _fds_before=( /proc/self/fd/*(N) )
    local -i i
    for (( i = 0; i < 100; i++ )); do
      'zhtml2md' -- "$ZHTML2MD_ROOT/tests/fixtures/m1-plain-text.html" >/dev/null 2>&1
    done
    local -a _fds_after=( /proc/self/fd/*(N) )
    (( ${#_fds_after} == ${#_fds_before} ))
    _zl_check 'no descriptor leak over 100 conversions' $?
  fi
}

# Arm the hostile environment. Every name the library uses in command
# position gets an alias; the library must parse unaffected.
alias local='echo HIJACKED-local; local'
alias integer='echo HIJACKED-integer; integer'
alias emulate='echo HIJACKED-emulate; emulate'
alias builtin='echo HIJACKED-builtin; builtin'
alias typeset='echo HIJACKED-typeset; typeset'
alias print='echo HIJACKED-print; print'
alias printf='echo HIJACKED-printf; printf'
alias source='echo HIJACKED-source; builtin source'
alias _zhtml2md_read_all='echo HIJACKED-helper; true'
alias _zhtml2md_entities_init='echo HIJACKED-entities; true'
alias _zhtml2md_decode_entities='echo HIJACKED-decoder; true'
alias _zhtml2md_entity_number='echo HIJACKED-number; true'
alias _zhtml2md_scalar_utf8='echo HIJACKED-scalar; true'
alias _zhtml2md_parse='echo HIJACKED-parser; true'
alias _zhtml2md_lex_next='echo HIJACKED-lexer; true'
alias _zhtml2md_lex_tag_grow='echo HIJACKED-grow; true'
alias _zhtml2md_frame_start='echo HIJACKED-start; true'
alias _zhtml2md_parse_event='echo HIJACKED-sink; true'
alias _zhtml2md_markdown='echo HIJACKED-markdown; true'
alias _zhtml2md_render_event='echo HIJACKED-renderer; true'
alias _zhtml2md_r_append='echo HIJACKED-fragment; true'
alias _zhtml2md_r_prose='echo HIJACKED-prose; true'
alias _zhtml2md_r_close='echo HIJACKED-close; true'
alias read='echo HIJACKED-read; read'
alias exec='echo HIJACKED-exec; exec'
alias unset='echo HIJACKED-unset; unset'
alias zhtml2md='echo HIJACKED-public; true'

_zl_main
(( _zl_fails == 0 ))
