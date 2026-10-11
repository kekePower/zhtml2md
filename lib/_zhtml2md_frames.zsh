# Iterative semantic frames and the v1 recovery contract. No DOM, no
# recursion per element, and no variable/function names derived from HTML.
'builtin' 'typeset' _zhtml2md_frames_loadopt=${options[aliases]:-off}
'builtin' 'setopt' 'noaliases'

# _zhtml2md_repair CATEGORY OFFSET MESSAGE
# Uses the public diagnostic/strict context. Strict mode stops at the
# first repair; tolerant mode accounts one bounded warning per defect.
_zhtml2md_repair() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  if (( _zhtml2md_strict )); then
    _zhtml2md_fail "$1" "$2" "$3" 3
    return 3
  fi
  _zhtml2md_diag "$1" "$2" "$3"
  return 0
}

# This fixed internal sink connects the parser to the renderer.
# It consumes event parameters in _zhtml2md_parse's dynamic context.
# Component tests replace it in their isolated shell to record events.
# It is not a public hook or plugin API, and does not write stdout.
_zhtml2md_parse_event() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  if (( ${_zhtml2md_r_active:-0} )); then
    _zhtml2md_render_event
    return $?
  fi
  return 0
}

# Known void elements do not consume depth or create frames.
_zhtml2md_is_void() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  case $1 in
    area|base|br|col|embed|hr|img|input|link|meta|param|source|track|wbr) return 0 ;;
  esac
  return 1
}

# Explicit paragraph-breaking set for the converter's simpler contract.
_zhtml2md_breaks_p() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  case $1 in
    address|article|aside|div|fieldset|figcaption|figure|footer|form|header|hgroup|main|nav|section|\
    p|h[1-6]|hr|ul|ol|li|blockquote|pre|textarea|plaintext|dl|dt|dd|details|summary|\
    table|caption|thead|tbody|tfoot|tr|td|th) return 0 ;;
  esac
  return 1
}

# Push/pop helpers consume the event protocol and parallel stack arrays.
# IDs are monotonic, but stack storage is indexed by depth and released
# on pop, so sequential elements do not accumulate a generic tree.
_zhtml2md_frame_push() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  if (( _zhtml2md_depth >= _ZHTML2MD_LIMIT_DEPTH )); then
    _zhtml2md_fail resource-limit $_zhtml2md_event_start 'open frames exceed 256' 4
    return 4
  fi
  _zhtml2md_event_parent=0
  _zhtml2md_event_discard=0
  if (( _zhtml2md_depth )); then
    _zhtml2md_event_parent=${_zhtml2md_frame_ids[_zhtml2md_depth]}
    _zhtml2md_event_discard=${_zhtml2md_frame_discard[_zhtml2md_depth]}
  fi
  local -i _own_discard=0
  case $_zhtml2md_event_name in
    head|script|style|template|title) _own_discard=1; _zhtml2md_event_discard=1 ;;
  esac
  (( ++_zhtml2md_depth, ++_zhtml2md_next_id ))
  _zhtml2md_event_id=$_zhtml2md_next_id
  _zhtml2md_frame_ids+=( $_zhtml2md_event_id )
  _zhtml2md_frame_tags+=( "$_zhtml2md_event_name" )
  _zhtml2md_frame_discard+=( $_zhtml2md_event_discard )
  _zhtml2md_frame_own_discard+=( $_own_discard )
  _zhtml2md_frame_synthetic+=( $_zhtml2md_event_synthetic )
  _zhtml2md_event_kind=open
  _zhtml2md_parse_event
}

_zhtml2md_frame_pop() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  _zhtml2md_event_kind=close
  _zhtml2md_event_literal=0
  _zhtml2md_event_name=${_zhtml2md_frame_tags[_zhtml2md_depth]}
  _zhtml2md_event_id=${_zhtml2md_frame_ids[_zhtml2md_depth]}
  _zhtml2md_event_discard=${_zhtml2md_frame_discard[_zhtml2md_depth]}
  _zhtml2md_event_parent=0
  (( _zhtml2md_depth > 1 )) && _zhtml2md_event_parent=${_zhtml2md_frame_ids[_zhtml2md_depth-1]}
  _zhtml2md_event_attrs=()
  _zhtml2md_parse_event || return $?
  _zhtml2md_frame_ids[-1]=()
  _zhtml2md_frame_tags[-1]=()
  _zhtml2md_frame_discard[-1]=()
  _zhtml2md_frame_own_discard[-1]=()
  _zhtml2md_frame_synthetic[-1]=()
  (( --_zhtml2md_depth ))
  return 0
}

# Close a repaired scope from the current top through stack slot $1.
# All generated closes have a zero-width source range at the trigger.
_zhtml2md_frame_unwind() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _target=$1
  _zhtml2md_event_synthetic=1
  _zhtml2md_event_end=$_zhtml2md_event_start
  while (( _zhtml2md_depth >= _target )); do
    _zhtml2md_frame_pop || return $?
  done
  return 0
}

# Validate recognized numeric attributes before any arithmetic. Signed
# list values use <= nine significant digits; spans are unsigned with
# their documented bounds. On invalid values remove the attribute so
# the renderer can apply its default, including reversed item counts.
# Reads/writes lexer attrs/offsets and the strict/diagnostic context.
_zhtml2md_validate_numeric_attrs() {
  emulate -L zsh -o no_multibyte -o extended_glob
  local LC_ALL=C
  local -a _attrs=()
  local _attr _digits _char
  local -i _min _max _signed=0 _sign _value _i _bad
  local MATCH
  local -i MBEGIN MEND
  local -a match mbegin mend
  for _attr in "${_zhtml2md_token_attr_names[@]}"; do
    case $_zhtml2md_token_name:$_attr in
      ol:start|li:value)
        _attrs+=( "$_attr" ); _min=-999999999; _max=999999999; _signed=1 ;;
      td:rowspan|td:colspan|th:rowspan|th:colspan) _attrs+=( "$_attr" ) ;;
    esac
  done
  for _attr in "${_attrs[@]}"; do
    (( ${+_zhtml2md_token_attrs[$_attr]} )) || continue
    case $_attr in
      rowspan) _min=0; _max=65534 ;;
      colspan) _min=1; _max=1000 ;;
    esac
    _digits=${_zhtml2md_token_attrs[$_attr]}
    _sign=1
    if (( _signed )); then
      case $_digits in
        -*) _sign=-1; _digits=${_digits[2,-1]} ;;
        +*) _digits=${_digits[2,-1]} ;;
      esac
    fi
    _bad=0
    _value=0
    if [[ $_digits != [0-9]## ]]; then
      _bad=1
    else
      if [[ $_digits =~ '^0+' ]]; then
        _digits=${_digits[MEND+1,-1]}
      fi
      if (( ${#_digits} > 9 )); then
        _bad=1
      else
        for (( _i=1; _i <= ${#_digits}; ++_i )); do
          _char=${_digits[_i]}
          (( _value = _value * 10 + #_char - 48 ))
        done
        (( _value *= _sign ))
        (( _value < _min || _value > _max )) && _bad=1
      fi
    fi
    if (( _bad )); then
      _zhtml2md_repair invalid-numeric-attribute "${_zhtml2md_token_attr_offsets[$_attr]}" \
        "invalid $_attr attribute; using default" || return $?
      builtin unset "_zhtml2md_token_attrs[$_attr]"
    else
      _zhtml2md_token_attrs[$_attr]=$_value
    fi
  done
  return 0
}

# Process a start token. New list/row/cell scopes close their old sibling
# first, then paragraph-breaking blocks close p, as documented in the
# parser protocol. Nested list/table boundaries stop sibling searches.
_zhtml2md_frame_start() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _i _container=0 _sibling=0
  local _name=$_zhtml2md_token_name _attr
  local _zhtml2md_decoded=''
  if [[ $_name == li ]]; then
    for (( _i=_zhtml2md_depth; _i >= 1; --_i )); do
      (( _zhtml2md_frame_own_discard[_i] )) && break
      case ${_zhtml2md_frame_tags[_i]} in
        ul|ol) _container=$_i; break ;;
        li) _sibling=$_i ;;
      esac
    done
    if (( _container && _sibling > _container )); then
      _zhtml2md_repair implicit-li-close $_zhtml2md_token_start 'new item closes previous item' || return $?
      _zhtml2md_frame_unwind $_sibling || return $?
    fi
  elif [[ $_name == tr || $_name == td || $_name == th ]]; then
    for (( _i=_zhtml2md_depth; _i >= 1; --_i )); do
      (( _zhtml2md_frame_own_discard[_i] )) && break
      if [[ $_name == tr ]]; then
        [[ ${_zhtml2md_frame_tags[_i]} == table ]] && { _container=$_i; break; }
        [[ ${_zhtml2md_frame_tags[_i]} == tr ]] && _sibling=$_i
      else
        [[ ${_zhtml2md_frame_tags[_i]} == table ]] && break
        [[ ${_zhtml2md_frame_tags[_i]} == tr ]] && { _container=$_i; break; }
        case ${_zhtml2md_frame_tags[_i]} in
          td|th) _sibling=$_i ;;
        esac
      fi
    done
    if (( _container && _sibling > _container )); then
      _zhtml2md_repair implicit-table-close $_zhtml2md_token_start 'new table member closes previous sibling' || return $?
      _zhtml2md_frame_unwind $_sibling || return $?
    fi
  fi
  if _zhtml2md_breaks_p "$_name"; then
    for (( _i=_zhtml2md_depth; _i >= 1; --_i )); do
      (( _zhtml2md_frame_own_discard[_i] )) && break
      if [[ ${_zhtml2md_frame_tags[_i]} == p ]]; then
        _zhtml2md_repair implicit-p-close $_zhtml2md_token_start 'new block closes paragraph' || return $?
        _zhtml2md_frame_unwind $_i || return $?
        break
      fi
    done
  fi
  if [[ $_name == li ]] && (( ! _container || _zhtml2md_frame_synthetic[_container] )); then
    _zhtml2md_repair orphan-li $_zhtml2md_token_start 'item uses synthetic unordered list' || return $?
    if (( ! _container )); then
      _zhtml2md_event_name=ul
      _zhtml2md_event_synthetic=1
      _zhtml2md_event_end=$_zhtml2md_event_start
      _zhtml2md_event_attrs=()
      _zhtml2md_frame_push || return $?
    fi
  fi
  # Structural repairs at the opener precede attribute defects. Values
  # decode in source order, and discarded duplicate values stay ignored.
  for _attr in "${_zhtml2md_token_attr_names[@]}"; do
    if [[ ${_zhtml2md_token_attrs[$_attr]} == *'&'* ]]; then
      _zhtml2md_decode_entities "${_zhtml2md_token_attrs[$_attr]}" \
        "${_zhtml2md_token_attr_offsets[$_attr]}" || return $?
      _zhtml2md_token_attrs[$_attr]=$_zhtml2md_decoded
    fi
  done
  case $_name in
    ol|li|td|th) _zhtml2md_validate_numeric_attrs || return $? ;;
  esac
  _zhtml2md_event_synthetic=0
  _zhtml2md_event_name=$_name
  _zhtml2md_event_end=$_zhtml2md_token_end
  _zhtml2md_event_attrs=( "${(@kv)_zhtml2md_token_attrs}" )
  if _zhtml2md_is_void "$_name"; then
    _zhtml2md_event_kind=void
    _zhtml2md_event_id=0
    _zhtml2md_event_parent=0
    _zhtml2md_event_discard=0
    if (( _zhtml2md_depth )); then
      _zhtml2md_event_parent=${_zhtml2md_frame_ids[_zhtml2md_depth]}
      _zhtml2md_event_discard=${_zhtml2md_frame_discard[_zhtml2md_depth]}
    fi
    _zhtml2md_parse_event
  else
    _zhtml2md_frame_push
  fi
}

_zhtml2md_frame_end() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _match=0 _i
  if ! _zhtml2md_is_void "$_zhtml2md_token_name"; then
    for (( _i=_zhtml2md_depth; _i >= 1; --_i )); do
      if [[ ${_zhtml2md_frame_tags[_i]} == "$_zhtml2md_token_name" && ${_zhtml2md_frame_synthetic[_i]} == 0 ]]; then
        _match=$_i
        break
      fi
      (( _zhtml2md_frame_own_discard[_i] )) && break
    done
  fi
  if (( ! _match )); then
    _zhtml2md_repair unmatched-end-tag $_zhtml2md_token_start 'end tag has no matching open element'
    return $?
  fi
  if (( _match < _zhtml2md_depth )); then
    _zhtml2md_repair misnested-close $_zhtml2md_token_start 'end tag unwinds intervening elements' || return $?
    _zhtml2md_frame_unwind $(( _match + 1 )) || return $?
  fi
  _zhtml2md_event_synthetic=0
  _zhtml2md_event_end=$_zhtml2md_token_end
  _zhtml2md_frame_pop
}

# _zhtml2md_parse
# Input was already read/UTF-8-validated. Reads public input/bom/strict
# and diagnostic context; all lexer/frame/event state is invocation-local.
# Internal event sink sees kind/name/data/attrs, start/end byte range,
# id/parent, discard, synthetic and literal flags. A sink may fail; its
# status is propagated, and no conversion stdout is emitted here.
# Public rendering consumes this parser's fixed internal event sink.
# No retained state except the immutable entity cache.
_zhtml2md_parse() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -A _zhtml2md_lex_lt=() _zhtml2md_lex_segments=()
  local -a _zhtml2md_frame_ids=() _zhtml2md_frame_tags=()
  local -a _zhtml2md_frame_discard=() _zhtml2md_frame_own_discard=() _zhtml2md_frame_synthetic=()
  local -i _zhtml2md_lex_index=1 _zhtml2md_lex_pos=0 _zhtml2md_lex_size=0 _zhtml2md_lex_count=0
  local _zhtml2md_lex_raw=''
  local _zhtml2md_token_kind='' _zhtml2md_token_name='' _zhtml2md_token_data=''
  local -i _zhtml2md_token_start=0 _zhtml2md_token_end=0 _zhtml2md_token_self=0 _zhtml2md_token_literal=0
  local -A _zhtml2md_token_attrs=() _zhtml2md_token_attr_offsets=()
  local -a _zhtml2md_token_attr_names=()
  local -i _zhtml2md_depth=0 _zhtml2md_next_id=0
  local _zhtml2md_event_kind='' _zhtml2md_event_name='' _zhtml2md_event_data=''
  local -A _zhtml2md_event_attrs=()
  local -i _zhtml2md_event_start=0 _zhtml2md_event_end=0 _zhtml2md_event_id=0 _zhtml2md_event_parent=0
  local -i _zhtml2md_event_discard=0 _zhtml2md_event_synthetic=0 _zhtml2md_event_literal=0
  local _zhtml2md_decoded=''
  local -i _parent_discard _group_end
  _zhtml2md_lex_init || return $?
  while true; do
    _zhtml2md_lex_next || return $?
    _zhtml2md_event_start=$_zhtml2md_token_start
    _zhtml2md_event_end=$_zhtml2md_token_end
    _zhtml2md_event_kind=$_zhtml2md_token_kind
    _zhtml2md_event_name=$_zhtml2md_token_name
    _zhtml2md_event_data=''
    _zhtml2md_event_attrs=()
    _zhtml2md_event_literal=$_zhtml2md_token_literal
    _zhtml2md_event_synthetic=0
    # Consecutive orphan items share one synthetic list. Whitespace,
    # comments and declarations between closed items do not end a group.
    if (( _zhtml2md_depth && _zhtml2md_frame_synthetic[_zhtml2md_depth] )); then
      _group_end=1
      case $_zhtml2md_token_kind in
        comment|declaration) _group_end=0 ;;
        start) [[ $_zhtml2md_token_name == li ]] && _group_end=0 ;;
        text) [[ $_zhtml2md_token_data != *[!\ $'\t\r\n']* ]] && _group_end=0 ;;
      esac
      if (( _group_end )); then
        _zhtml2md_frame_unwind $_zhtml2md_depth || return $?
        _zhtml2md_event_name=$_zhtml2md_token_name
        _zhtml2md_event_synthetic=0
        _zhtml2md_event_end=$_zhtml2md_token_end
      fi
    fi
    case $_zhtml2md_token_kind in
      comment|declaration) continue ;;
      start) _zhtml2md_frame_start || return $? ;;
      end) _zhtml2md_frame_end || return $? ;;
      text)
        _parent_discard=0
        _zhtml2md_event_parent=0
        _zhtml2md_event_id=0
        if (( _zhtml2md_depth )); then
          _parent_discard=${_zhtml2md_frame_discard[_zhtml2md_depth]}
          _zhtml2md_event_parent=${_zhtml2md_frame_ids[_zhtml2md_depth]}
        fi
        # Entity-like bytes in discarded raw/template/head content must
        # never be decoded or recursively tokenized as generated markup.
        (( _parent_discard )) && continue
        if (( _zhtml2md_token_literal )) || [[ $_zhtml2md_token_data != *'&'* ]]; then
          _zhtml2md_event_data=$_zhtml2md_token_data
        else
          _zhtml2md_decode_entities "$_zhtml2md_token_data" $_zhtml2md_token_start || return $?
          _zhtml2md_event_data=$_zhtml2md_decoded
        fi
        _zhtml2md_event_kind=text
        _zhtml2md_event_discard=0
        _zhtml2md_parse_event || return $? ;;
      eof)
        while (( _zhtml2md_depth )); do
          if (( ! _zhtml2md_frame_synthetic[_zhtml2md_depth] )) &&
             [[ ${_zhtml2md_frame_tags[_zhtml2md_depth]} != plaintext ]]; then
            if (( _zhtml2md_frame_own_discard[_zhtml2md_depth] )); then
              _zhtml2md_repair unterminated-discard $_zhtml2md_token_start 'discarded element remains open at EOF' || return $?
            else
              _zhtml2md_repair unclosed-element $_zhtml2md_token_start 'element remains open at EOF' || return $?
            fi
          fi
          _zhtml2md_event_synthetic=1
          [[ ${_zhtml2md_frame_tags[_zhtml2md_depth]} == plaintext ]] && _zhtml2md_event_synthetic=0
          _zhtml2md_frame_pop || return $?
        done
        return 0 ;;
    esac
  done
}

if [[ $_zhtml2md_frames_loadopt == on ]]; then
  'builtin' 'setopt' 'aliases'
fi
'builtin' 'unset' _zhtml2md_frames_loadopt
