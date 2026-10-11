#!/usr/bin/env zsh
# Component-only event recorder. Arbitrary token text is quoted solely
# for fixture comparison, never evaluated or used as the runtime protocol.
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r root=${${${${(%):-%N}:A}:h}:h:h}
source "$root/zhtml2md.zsh" || exit 1
local mode=$1
local _zhtml2md_in_path=$2 _zhtml2md_input='' _zhtml2md_strict=${3:-0}
local -i _zhtml2md_bom=0 _zhtml2md_diag_emitted=0 _zhtml2md_diag_total=0 _zhtml2md_diag_capped=0
local -a _zp_log=()

_zhtml2md_parse_event() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _name=${_zhtml2md_event_name:--} _key
  _zp_log+=( "$_zhtml2md_event_kind $_name $_zhtml2md_event_id/$_zhtml2md_event_parent $_zhtml2md_event_start:$_zhtml2md_event_end d$_zhtml2md_event_discard s$_zhtml2md_event_synthetic l$_zhtml2md_event_literal ${(qqqq)_zhtml2md_event_data}"$'\n' )
  for _key in "${(@ok)_zhtml2md_event_attrs}"; do
    _zp_log+=( "attr ${(qqqq)_key} ${(qqqq)_zhtml2md_event_attrs[$_key]}"$'\n' )
  done
  return 0
}

_zp_lex() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -A _zhtml2md_lex_lt=() _zhtml2md_lex_segments=()
  local -a _zhtml2md_token_attr_names=()
  local -i _zhtml2md_lex_index=1 _zhtml2md_lex_pos=0 _zhtml2md_lex_size=0 _zhtml2md_lex_count=0
  local _zhtml2md_lex_raw='' _zhtml2md_token_kind='' _zhtml2md_token_name='' _zhtml2md_token_data=''
  local -i _zhtml2md_token_start=0 _zhtml2md_token_end=0 _zhtml2md_token_self=0 _zhtml2md_token_literal=0
  local -A _zhtml2md_token_attrs=() _zhtml2md_token_attr_offsets=()
  local _key _name
  _zhtml2md_lex_init || return $?
  while true; do
    _zhtml2md_lex_next || return $?
    [[ $_zhtml2md_token_kind == eof ]] && return 0
    _name=${_zhtml2md_token_name:--}
    _zp_log+=( "$_zhtml2md_token_kind $_name $_zhtml2md_token_start:$_zhtml2md_token_end s$_zhtml2md_token_self l$_zhtml2md_token_literal ${(qqqq)_zhtml2md_token_data}"$'\n' )
    for _key in "${(@ok)_zhtml2md_token_attrs}"; do
      _zp_log+=( "attr ${(qqqq)_key} $_zhtml2md_token_attr_offsets[$_key] ${(qqqq)_zhtml2md_token_attrs[$_key]}"$'\n' )
    done
  done
}

_zhtml2md_read_all && _zhtml2md_validate_encoding || exit $?
case $mode in
  events) _zhtml2md_parse ;;
  tokens) _zp_lex ;;
  *) exit 2 ;;
esac
local -i st=$?
_zhtml2md_diag_finish
(( st == 0 )) || exit $st
builtin printf '%s' "${(j::)_zp_log}"
