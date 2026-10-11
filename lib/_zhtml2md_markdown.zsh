# SPDX-License-Identifier: Apache-2.0
# Event-driven Markdown rendering. Captures own fragments only once;
# joining a child releases its charge before transferring to its parent.
# All state below is local to _zhtml2md_markdown's dynamic scope. Numeric
# association keys and arithmetic operands are generated internally.
'builtin' 'typeset' _zhtml2md_markdown_loadopt="$( 'builtin' 'set' '+o' )"
'builtin' 'setopt' 'noaliases'
if [[ $'\n'$_zhtml2md_markdown_loadopt$'\n' == *$'\nset +o noaliases\n'* ||
      $'\n'$_zhtml2md_markdown_loadopt$'\n' == *$'\nset -o aliases\n'* ]]; then
  _zhtml2md_markdown_loadopt=on
else
  _zhtml2md_markdown_loadopt=off
fi

# Literal append, without whitespace policy. Linked fragments avoid
# repeatedly copying a growing document for every short text/tag event.
_zhtml2md_r_append() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _s=$1
  local -i _n=${#_s} _slot=$_zhtml2md_r_slot _cap
  (( _n )) || return 0
  if (( _slot == 1 )); then
    _cap=_ZHTML2MD_LIMIT_OUTPUT
    if (( _zhtml2md_r_size[1] + _n > _cap )); then
      _zhtml2md_fail resource-limit '' "output exceeds $_cap bytes" 4
      return 4
    fi
  else
    _cap=_ZHTML2MD_LIMIT_CAPTURE
    if (( _zhtml2md_r_pending + _n > _cap )); then
      _zhtml2md_fail resource-limit '' "pending captures exceed $_cap bytes" 4
      return 4
    fi
    (( _zhtml2md_r_pending += _n ))
  fi
  (( ++_zhtml2md_r_serial ))
  _zhtml2md_r_piece[$_zhtml2md_r_serial]=$_s
  if (( ${_zhtml2md_r_tail[$_slot]:-0} )); then
    _zhtml2md_r_next[${_zhtml2md_r_tail[$_slot]}]=$_zhtml2md_r_serial
  else
    _zhtml2md_r_head[$_slot]=$_zhtml2md_r_serial
  fi
  _zhtml2md_r_tail[$_slot]=$_zhtml2md_r_serial
  (( _zhtml2md_r_size[$_slot] += _n ))
  _zhtml2md_r_end[$_slot]=${_s[-1]}
  return 0
}

# Read and release the current capture's linked fragments. The result
# variable belongs to the caller; no executable text serialization.
_zhtml2md_r_take() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -a _parts=()
  local -i _id=${_zhtml2md_r_head[$_zhtml2md_r_slot]:-0} _next
  while (( _id )); do
    _parts+=( "${_zhtml2md_r_piece[$_id]}" )
    _next=${_zhtml2md_r_next[$_id]:-0}
    unset "_zhtml2md_r_piece[$_id]" "_zhtml2md_r_next[$_id]"
    _id=$_next
  done
  _zhtml2md_r_result=${(j::)_parts}
  if (( _zhtml2md_r_slot > 1 )); then
    (( _zhtml2md_r_pending -= _zhtml2md_r_size[$_zhtml2md_r_slot] ))
  fi
  _zhtml2md_r_head[$_zhtml2md_r_slot]=0
  _zhtml2md_r_tail[$_zhtml2md_r_slot]=0
  _zhtml2md_r_size[$_zhtml2md_r_slot]=0
  return 0
}

_zhtml2md_r_boundary() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  if (( ${_zhtml2md_r_single[$_zhtml2md_r_slot]:-0} )); then
    _zhtml2md_r_space[$_zhtml2md_r_slot]=1
  else
    _zhtml2md_r_block[$_zhtml2md_r_slot]=1
    _zhtml2md_r_blocks[$_zhtml2md_r_slot]=1
    _zhtml2md_r_space[$_zhtml2md_r_slot]=0
  fi
  return 0
}

# A nonempty inline fragment pays any delayed separator first. Empty
# blocks and source whitespace at block edges never emit separators.
_zhtml2md_r_inline() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  [[ -n $1 ]] || return 0
  local -i _slot=$_zhtml2md_r_slot
  if (( _zhtml2md_r_size[$_slot] )); then
    if (( ${_zhtml2md_r_block[$_slot]:-0} )); then
      if [[ ${_zhtml2md_r_end[$_slot]} == $'\n' ]]; then
        _zhtml2md_r_append $'\n' || return $?
      else
        _zhtml2md_r_append $'\n\n' || return $?
      fi
    elif (( ${_zhtml2md_r_space[$_slot]:-0} )) &&
         [[ ${_zhtml2md_r_end[$_slot]} != $'\n' ]]; then
      _zhtml2md_r_append ' ' || return $?
    fi
  fi
  _zhtml2md_r_space[$_slot]=0
  _zhtml2md_r_block[$_slot]=0
  _zhtml2md_r_append "$1"
}

# Text/heading/label contexts share a conservative literal punctuation
# policy. Generated markers, destinations, and code bypass this helper.
# Escaping & also prevents a second Markdown entity expansion.
_zhtml2md_r_escape() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _s=$1 _c _chunk
  local -a _parts=() _marks=( '\' '`' '*' '_' '[' ']' '<' '>' '&' '#' '+' '-' '!' '(' ')' '|' '{' '}' )
  [[ $2 == destination ]] && _marks=( '\' '&' '<' '>' '(' ')' )
  if [[ $2 == destination ]] && (( ${_zhtml2md_r_cellctx[$_zhtml2md_r_slot]:-0} )); then
    _marks+=( '|' '`' )
  fi
  local -i _pos=1 _size=0
  while (( _pos <= ${#_s} )); do
    _chunk=${_s[_pos,_pos+4095]}
    for _c in "${_marks[@]}"; do
      _chunk=${_chunk//"$_c"/"\\$_c"}
    done
    if [[ $2 != destination ]] && (( ${_zhtml2md_r_cellctx[$_zhtml2md_r_slot]:-0} )); then
      _chunk=${_chunk//'\& '/'& '}
    fi
    (( _size += ${#_chunk} ))
    if (( _size > _ZHTML2MD_LIMIT_OUTPUT )); then
      _zhtml2md_fail resource-limit '' "escaped text exceeds $_ZHTML2MD_LIMIT_OUTPUT bytes" 4
      return 4
    fi
    _parts+=( "$_chunk" )
    (( _pos += 4096 ))
  done
  _zhtml2md_r_result=${(j::)_parts}
  return 0
}

# Normalize raw code in bounded windows, carrying a final CR so a CRLF
# pair crossing a window is still one LF. Prose collapses both directly.
_zhtml2md_r_normalize() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _s=$1 _chunk _carry=''
  local -a _parts=()
  local -i _pos=1
  while (( _pos <= ${#_s} )); do
    _chunk=$_carry${_s[_pos,_pos+4095]}
    _carry=''
    if [[ $2 == spaces ]]; then
      _chunk=${_chunk//$'\r'/ } _chunk=${_chunk//$'\n'/ } _chunk=${_chunk//$'\t'/ }
      _parts+=( "$_chunk" )
      (( _pos += 4096 ))
      continue
    fi
    if [[ $_chunk == *$'\r' ]]; then
      _chunk=${_chunk[1,-2]} _carry=$'\r'
    fi
    _chunk=${_chunk//$'\r\n'/$'\n'} _chunk=${_chunk//$'\r'/$'\n'}
    _parts+=( "$_chunk" )
    (( _pos += 4096 ))
  done
  [[ -n $_carry ]] && _parts+=( $'\n' )
  _zhtml2md_r_result=${(j::)_parts}
  return 0
}

# Collapse ASCII HTML whitespace in bounded windows. Large all-space
# input takes one pattern scan; bounded substitutions avoid quadratic
# behavior of Zsh global substitution on multi-megabyte whitespace.
_zhtml2md_r_prose() {
  emulate -L zsh -o no_multibyte -o extended_glob
  local LC_ALL=C
  local _s=$1 _chunk _text _first _last _number
  local -a _words
  local -i _pos=1 _slot=$_zhtml2md_r_slot
  local MATCH MBEGIN MEND
  local -a match mbegin mend
  if [[ $_s != *[!$' \t\r\n']* ]]; then
    [[ -n $_s ]] && _zhtml2md_r_space[$_slot]=1
    if (( ! _zhtml2md_r_size[$_slot] )); then
      [[ -n $_s ]] && _zhtml2md_r_leading[$_slot]=1
    fi
    return 0
  fi
  while (( _pos <= ${#_s} )); do
    _chunk=${_s[_pos,_pos+4095]}
    _first=${_chunk[1]} _last=${_chunk[-1]}
    if [[ $_first == [$' \t\r\n'] ]]; then
      _zhtml2md_r_space[$_slot]=1
      (( _zhtml2md_r_size[$_slot] )) || _zhtml2md_r_leading[$_slot]=1
    fi
    _chunk=${_chunk//$'\t'/ }
    _chunk=${_chunk//$'\r'/ }
    _chunk=${_chunk//$'\n'/ }
    _words=( ${(s: :)_chunk} )
    _text=${(j: :)_words}
    _zhtml2md_r_escape "$_text" || return $?
    _text=$_zhtml2md_r_result
    # Protect ordered-list punctuation, including a number split over
    # inline boundaries. No general escape of ordinary sentence dots.
    if [[ $_text == (#b)([0-9](#c1,9))\.* ]]; then
      _number=${match[1]}
      _text=$_number'\.'${_text[${#_number}+2,-1]}
    elif [[ $_text == .* ]] && [[ ${_zhtml2md_r_digits[$_slot]:-0} == 1 ]]; then
      _text='\'$_text
    fi
    if (( ! _zhtml2md_r_size[$_slot] || ${_zhtml2md_r_block[$_slot]:-0} )); then
      _zhtml2md_r_digits[$_slot]=0
      [[ $_text == [0-9](#c1,9) ]] && _zhtml2md_r_digits[$_slot]=1
    elif [[ $_text != [0-9]## ]]; then
      _zhtml2md_r_digits[$_slot]=0
    fi
    _zhtml2md_r_inline "$_text" || return $?
    [[ $_last == [$' \t\r\n'] ]] && _zhtml2md_r_space[$_slot]=1
    (( _pos += 4096 ))
  done
  return 0
}

# Longest backtick run, with carry across bounded scanning windows.
_zhtml2md_r_ticks() {
  emulate -L zsh -o no_multibyte -o extended_glob
  local LC_ALL=C
  local _s=$1 _t
  local -i _pos=1 _carry=0 _run=0 _max=0 _len
  local MATCH MBEGIN MEND
  local -a match mbegin mend
  while (( _pos <= ${#_s} )); do
    _t=${_s[_pos,_pos+4095]}
    while [[ $_t == (#b)([^\`]#)(\`##)(*) ]]; do
      _run=${#match[2]}
      [[ -z ${match[1]} ]] && (( _run += _carry ))
      (( _run > _max )) && _max=$_run
      _carry=0
      [[ -z ${match[3]} ]] && _carry=$_run
      _t=${match[3]}
    done
    [[ -n $_t ]] && _carry=0
    (( _pos += 4096 ))
  done
  _zhtml2md_r_tick_max=$_max
}

# TYPE=inline or fence. Code contents bypass prose/entity escaping.
_zhtml2md_r_code() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _s=$1 _type=$2 _language=$3 _fence='' _pad='' _unit='`'
  local -i _width _remaining
  _zhtml2md_r_normalize "$_s"
  _s=$_zhtml2md_r_result
  _zhtml2md_r_ticks "$_s"
  _width=$(( _zhtml2md_r_tick_max + 1 ))
  _zhtml2md_r_result_block=0
  if [[ $_type != inline || $_s == *$'\n'* || -z $_s ]]; then
    _type=fence
    (( _width < 3 )) && _width=3
    _zhtml2md_r_result_block=1
  fi
  # Binary doubling builds even multi-megabyte fences with bounded
  # literal concatenation; no global substitution over a huge space run.
  _remaining=$_width
  while (( _remaining )); do
    (( _remaining & 1 )) && _fence+=$_unit
    (( _remaining /= 2 ))
    (( _remaining )) && _unit+=$_unit
  done
  _zhtml2md_r_code_width=$_width
  _zhtml2md_r_code_pad=0
  if [[ $_type == inline ]]; then
    if [[ $_s == \`* || $_s == *\` ]] ||
       [[ $_s == ' '* && $_s == *' ' && $_s == *[!\ ]* ]]; then
      _pad=' '
      _zhtml2md_r_code_pad=1
    fi
    _zhtml2md_r_result=$_fence$_pad$_s$_pad$_fence
  else
    [[ -z $_s || $_s == *$'\n' ]] || _s+=$'\n'
    _zhtml2md_r_result=$_fence$_language$'\n'$_s$_fence
  fi
}

# Adjacent inline code spans have no literal separator: concatenate their
# contents and replace the last code fragment with one correctly delimited
# span. Only delimiter widths are retained, never a duplicate raw payload.
_zhtml2md_r_inline_code() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _s=$1 _previous _md
  local -i _slot=$_zhtml2md_r_slot _id=${_zhtml2md_r_tail[$_zhtml2md_r_slot]:-0}
  local -i _trim _oldlen _newlen _limit
  if (( _id && _id == ${_zhtml2md_r_code_id[$_slot]:-0} &&
        ! ${_zhtml2md_r_space[$_slot]:-0} && ! ${_zhtml2md_r_block[$_slot]:-0} )) &&
     [[ $_s != *[$'\r\n']* ]]; then
    _previous=${_zhtml2md_r_piece[$_id]}
    _oldlen=${#_previous}
    _trim=$(( _zhtml2md_r_code_edge[$_slot] ))
    _s=${_previous[_trim+1,-_trim-1]}$_s
    _zhtml2md_r_code "$_s" inline ''
    _md=$_zhtml2md_r_result _newlen=${#_md}
    if (( _slot == 1 )); then
      _limit=_ZHTML2MD_LIMIT_OUTPUT
      if (( _zhtml2md_r_size[1] - _oldlen + _newlen > _limit )); then
        _zhtml2md_fail resource-limit '' "output exceeds $_limit bytes" 4
        return 4
      fi
    else
      _limit=_ZHTML2MD_LIMIT_CAPTURE
      if (( _zhtml2md_r_pending - _oldlen + _newlen > _limit )); then
        _zhtml2md_fail resource-limit '' "pending captures exceed $_limit bytes" 4
        return 4
      fi
      (( _zhtml2md_r_pending += _newlen - _oldlen ))
    fi
    (( _zhtml2md_r_size[$_slot] += _newlen - _oldlen ))
    _zhtml2md_r_piece[$_id]=$_md
    _zhtml2md_r_code_edge[$_slot]=$(( _zhtml2md_r_code_width + _zhtml2md_r_code_pad ))
    return 0
  fi
  _zhtml2md_r_code "$_s" inline ''
  if (( _zhtml2md_r_result_block )); then
    return 0
  fi
  _zhtml2md_r_inline "$_zhtml2md_r_result" || return $?
  _zhtml2md_r_code_id[$_slot]=${_zhtml2md_r_tail[$_slot]}
  _zhtml2md_r_code_edge[$_slot]=$(( _zhtml2md_r_code_width + _zhtml2md_r_code_pad ))
  return 0
}

# Preserve destination data, including literal entities and backslashes.
# LF/CR/HT use the documented non-clickable code fallback.
_zhtml2md_r_destination() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _s=$1
  _zhtml2md_r_destination_ok=0
  [[ $_s == *[$'\t\r\n']* ]] && return 0
  _zhtml2md_r_escape "$_s" destination || return $?
  _s=$_zhtml2md_r_result
  [[ $_s == *' '* ]] && _s="<$_s>"
  _zhtml2md_r_result=$_s
  _zhtml2md_r_destination_ok=1
}

_zhtml2md_r_language() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  [[ -n ${_zhtml2md_r_language[$_zhtml2md_r_slot]} ]] && return 0
  local _s=$1 _token
  local -a _tokens
  _zhtml2md_r_normalize "$_s" spaces
  _s=$_zhtml2md_r_result
  _tokens=( ${(s: :)_s} )
  for _token in "${_tokens[@]}"; do
    [[ $_token == language-* ]] || continue
    _token=${_token#language-}
    if [[ -n $_token && ${#_token} -le 32 && $_token != *[^A-Za-z0-9_+-]* ]]; then
      _zhtml2md_r_language[$_zhtml2md_r_slot]=$_token
      return 0
    fi
  done
  return 0
}

_zhtml2md_r_push() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _old=$_zhtml2md_r_slot
  (( ++_zhtml2md_r_slot ))
  local -i _slot=$_zhtml2md_r_slot
  _zhtml2md_r_id[$_slot]=$_zhtml2md_event_id
  _zhtml2md_r_kind[$_slot]=$1
  _zhtml2md_r_name[$_slot]=$_zhtml2md_event_name
  _zhtml2md_r_size[$_slot]=0
  _zhtml2md_r_head[$_slot]=0 _zhtml2md_r_tail[$_slot]=0
  _zhtml2md_r_space[$_slot]=0 _zhtml2md_r_block[$_slot]=0
  _zhtml2md_r_leading[$_slot]=0 _zhtml2md_r_blocks[$_slot]=0
  _zhtml2md_r_end[$_slot]='' _zhtml2md_r_dest[$_slot]=''
  _zhtml2md_r_language[$_slot]='' _zhtml2md_r_strip[$_slot]=0
  _zhtml2md_r_single[$_slot]=${_zhtml2md_r_single[$_old]:-0}
  _zhtml2md_r_format[$_slot]=${_zhtml2md_r_format[$_old]:-0}
  _zhtml2md_r_links[$_slot]=${_zhtml2md_r_links[$_old]:-0}
  _zhtml2md_r_digits[$_slot]=0
  _zhtml2md_r_code_id[$_slot]=0 _zhtml2md_r_code_edge[$_slot]=0
  _zhtml2md_r_scope[$_slot]=${_zhtml2md_r_scope[$_old]}
  _zhtml2md_r_cellctx[$_slot]=${_zhtml2md_r_cellctx[$_old]:-0}
  _zhtml2md_r_records_head[$_slot]=0 _zhtml2md_r_records_tail[$_slot]=0
}

_zhtml2md_r_close() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  case ${_zhtml2md_r_kind[$_zhtml2md_r_slot]} in
    list|item|table|row|cell|caption) _zhtml2md_r_structure_close; return $? ;;
  esac
  if (( ${_zhtml2md_r_records_head[$_zhtml2md_r_slot]:-0} )); then
    _zhtml2md_r_inline_records_close
    return $?
  fi
  local -i _slot=$_zhtml2md_r_slot _blocks=${_zhtml2md_r_blocks[$_zhtml2md_r_slot]:-0}
  local -i _leading=${_zhtml2md_r_leading[$_slot]:-0} _trailing=${_zhtml2md_r_space[$_slot]:-0}
  local -i _nested=${_zhtml2md_r_nested[$_slot]:-0}
  local _kind=${_zhtml2md_r_kind[$_slot]} _name=${_zhtml2md_r_name[$_slot]}
  local _dest=${_zhtml2md_r_dest[$_slot]} _language=${_zhtml2md_r_language[$_slot]}
  local -i _strip=${_zhtml2md_r_strip[$_slot]:-0}
  local -i _code_only=0 _code_edge=${_zhtml2md_r_code_edge[$_slot]:-0}
  if (( ${_zhtml2md_r_code_id[$_slot]:-0} &&
        _zhtml2md_r_code_id[$_slot] == ${_zhtml2md_r_head[$_slot]:-0} &&
        _zhtml2md_r_code_id[$_slot] == ${_zhtml2md_r_tail[$_slot]:-0} )); then
    _code_only=1
  fi
  _zhtml2md_r_take
  local _body=$_zhtml2md_r_result _md _marker
  (( --_zhtml2md_r_slot ))
  # Every new capture resets its own fields, including this optional one.
  _zhtml2md_r_nested[$_slot]=0
  case $_kind in
    raw)
      [[ $_name == code && -z $_body ]] && return 0
      _zhtml2md_r_normalize "$_body"
      _body=$_zhtml2md_r_result
      (( _strip )) && [[ $_body == $'\n'* ]] && _body=${_body[2,-1]}
      if [[ $_name == code ]]; then
        _zhtml2md_r_inline_code "$_body" || return $?
        (( _zhtml2md_r_result_block )) || return 0
      else
        _zhtml2md_r_code "$_body" fence "$_language"
      fi
      _md=$_zhtml2md_r_result
      if (( _zhtml2md_r_result_block )); then
        # Fences cannot be heading inlines. Switch the enclosing capture
        # to child-block fallback and retain delayed separators.
        _zhtml2md_r_single[$_zhtml2md_r_slot]=0
        _zhtml2md_r_boundary
        _zhtml2md_r_inline "$_md" || return $?
        _zhtml2md_r_boundary
      else
        _zhtml2md_r_inline "$_md" || return $?
      fi
      return 0 ;;
    heading)
      if [[ -n $_body && $_blocks == 0 ]]; then
        builtin printf -v _marker '%*s' ${_name#h} ''
        _marker=${_marker// /#}
        _body="$_marker $_body"
      fi ;;
    emphasis)
      # ASCII word edges ensure delimiter flanking even when neighboring
      # source text is a word. Punctuation/Unicode edges use plain text.
      if [[ -n $_body && $_blocks == 0 && $_nested == 0 &&
            $_body[1] == [A-Za-z0-9] && $_body[-1] == [A-Za-z0-9] ]] &&
         { [[ ${_zhtml2md_r_end[$_zhtml2md_r_slot]} != '*' ]] ||
           (( ${_zhtml2md_r_space[$_zhtml2md_r_slot]:-0} || ${_zhtml2md_r_block[$_zhtml2md_r_slot]:-0} || _leading )); }; then
        _marker='*'
        [[ $_name == strong || $_name == b ]] && _marker='**'
        _body=$_marker$_body$_marker
      fi ;;
    link)
      if [[ -n $_dest ]]; then
        if [[ -z $_body ]]; then
          _zhtml2md_r_escape "$_dest" || return $?
          _body=$_zhtml2md_r_result
        fi
        _zhtml2md_r_destination "$_dest" || return $?
        if (( _zhtml2md_r_destination_ok && ! _blocks && ! _nested )); then
          _body="[$_body]($_zhtml2md_r_result)"
        else
          _md=$_body
          _zhtml2md_r_code "$_dest" inline ''
          if (( _blocks || _zhtml2md_r_result_block )); then
            _body=$_md$'\n\n'$_zhtml2md_r_result
            _blocks=1
          else
            _body="$_md ($_zhtml2md_r_result)"
          fi
        fi
      fi ;;
    quote)
      if [[ -n $_body ]]; then
        _zhtml2md_r_indent "$_body" '> ' '> ' || return $?
        _body=$_zhtml2md_r_result
      fi ;;
    option)
      if [[ -n $_body ]]; then
        _zhtml2md_r_indent "$_body" '- ' '  ' || return $?
        _body=$_zhtml2md_r_result
      fi ;;
  esac
  if (( _blocks )); then
    _zhtml2md_r_single[$_zhtml2md_r_slot]=0
    _zhtml2md_r_blocks[$_zhtml2md_r_slot]=1
  fi
  # A plain fallback wrapping only one code span must keep its code
  # identity, so adjacent spans still merge across empty inline wrappers.
  if (( _code_only && ! _blocks )) &&
     { [[ $_kind == emphasis ]] || [[ $_kind == link && -z $_dest ]]; }; then
    (( _leading )) && _zhtml2md_r_space[$_zhtml2md_r_slot]=1
    _zhtml2md_r_inline_code "${_body[_code_edge+1,-_code_edge-1]}" || return $?
    (( _trailing )) && _zhtml2md_r_space[$_zhtml2md_r_slot]=1
    return 0
  fi
  if [[ $_kind == heading || $_kind == quote || $_kind == option ]] || (( _blocks )); then
    _zhtml2md_r_boundary
    _zhtml2md_r_inline "$_body" || return $?
    _zhtml2md_r_boundary
  else
    (( _leading )) && _zhtml2md_r_space[$_zhtml2md_r_slot]=1
    _zhtml2md_r_inline "$_body" || return $?
    (( _trailing )) && _zhtml2md_r_space[$_zhtml2md_r_slot]=1
  fi
  return 0
}

_zhtml2md_render_event() {
  emulate -L zsh -o no_multibyte -o extended_glob
  local LC_ALL=C
  (( _zhtml2md_event_discard )) && return 0
  local _kind=$_zhtml2md_event_kind _name=$_zhtml2md_event_name _value _src _alt _md
  local -i _slot=$_zhtml2md_r_slot
  if [[ $_kind == close ]] && (( _slot > 1 )) &&
     [[ ${_zhtml2md_r_id[$_slot]} == $_zhtml2md_event_id ]]; then
    _zhtml2md_r_close
    return $?
  fi
  if [[ ${_zhtml2md_r_kind[$_slot]} == raw ]]; then
    if [[ $_kind == text ]]; then
      _zhtml2md_r_append "$_zhtml2md_event_data"
      return $?
    elif [[ $_kind == open && $_name == code ]]; then
      _zhtml2md_r_language "${_zhtml2md_event_attrs[class]}"
    elif [[ $_kind == void && $_name == br ]]; then
      _zhtml2md_r_append $'\n'
      return $?
    fi
    return 0
  fi
  if [[ $_kind == text ]]; then
    _zhtml2md_r_prose "$_zhtml2md_event_data"
    return $?
  fi
  if [[ $_kind == open ]]; then
    case $_name in
      ul|ol|li|table|tr|td|th|caption)
        _zhtml2md_r_structure_open "$_name" || return $? ;;
      thead|tbody|tfoot)
        [[ ${_zhtml2md_r_scope[$_slot]} == table ]] || _zhtml2md_r_boundary ;;
      h[1-6])
        _zhtml2md_r_boundary; _zhtml2md_r_push heading
        _zhtml2md_r_single[$_zhtml2md_r_slot]=1 ;;
      em|i|strong|b)
        _zhtml2md_r_push emphasis
        _zhtml2md_r_nested[$_zhtml2md_r_slot]=${_zhtml2md_r_format[$_zhtml2md_r_slot]}
        _zhtml2md_r_format[$_zhtml2md_r_slot]=1 ;;
      a)
        _zhtml2md_r_push link
        _zhtml2md_r_dest[$_zhtml2md_r_slot]=${_zhtml2md_event_attrs[href]}
        _zhtml2md_r_nested[$_zhtml2md_r_slot]=${_zhtml2md_r_links[$_zhtml2md_r_slot]}
        _zhtml2md_r_links[$_zhtml2md_r_slot]=1
        # The outer link must also use fallback when a child is a link.
        (( _slot > 1 && ${_zhtml2md_r_links[$_slot]:-0} )) && _zhtml2md_r_nested[$_slot]=1 ;;
      code|pre|textarea|plaintext)
        [[ $_name != code ]] && _zhtml2md_r_boundary
        _zhtml2md_r_push raw
        if [[ $_name == pre ]]; then
          # Select the byte after this tag from the existing '<' index.
          # Repeated subscripting of the whole input rescans its metadata
          # and measured quadratic growth on many fenced code blocks.
          # Quoted '<' bytes can put the tag end in a later segment.
          local -i _j=$(( _zhtml2md_lex_index + 1 )) _base _at
          while (( _j <= _zhtml2md_lex_count &&
                   ${_zhtml2md_lex_lt[$_j]:-0} < _zhtml2md_event_end )); do
            (( ++_j ))
          done
          _base=$(( ${_zhtml2md_lex_lt[$((_j-1))]} + 1 ))
          _at=$(( _zhtml2md_event_end - _base + 1 ))
          if [[ ${_zhtml2md_lex_segments[$_j][_at]} == [$'\r\n'] ]]; then
            _zhtml2md_r_strip[$_zhtml2md_r_slot]=1
          fi
        fi ;;
      dd|blockquote)
        _zhtml2md_r_boundary; _zhtml2md_r_push quote ;;
      option)
        _zhtml2md_r_boundary; _zhtml2md_r_push option ;;
      *) _zhtml2md_breaks_p "$_name" && _zhtml2md_r_boundary ;;
    esac
  elif [[ $_kind == close ]]; then
    if [[ $_name != thead && $_name != tbody && $_name != tfoot ]] ||
       [[ ${_zhtml2md_r_scope[$_slot]} != table ]]; then
      _zhtml2md_breaks_p "$_name" && _zhtml2md_r_boundary
    fi
  elif [[ $_kind == void ]]; then
    case $_name in
      br)
        if (( ${_zhtml2md_r_single[$_slot]:-0} )); then
          _zhtml2md_r_space[$_slot]=1
        elif (( _zhtml2md_r_size[$_slot] && ! ${_zhtml2md_r_block[$_slot]:-0} )); then
          _zhtml2md_r_space[$_slot]=0
          _zhtml2md_r_blocks[$_slot]=1
          _zhtml2md_r_append $'  \n' || return $?
        fi ;;
      hr)
        _zhtml2md_r_boundary; _zhtml2md_r_inline '---' || return $?
        _zhtml2md_r_boundary ;;
      input)
        _value=${(L)_zhtml2md_event_attrs[type]}
        case $_value in
          hidden|password|checkbox|radio|file|range|color|image) return 0 ;;
        esac
        _zhtml2md_r_prose "${_zhtml2md_event_attrs[value]}" || return $? ;;
      img)
        _src=${_zhtml2md_event_attrs[src]} _alt=${_zhtml2md_event_attrs[alt]}
        if [[ -z $_src ]]; then
          _zhtml2md_r_prose "$_alt" || return $?
        elif [[ -z $_alt || $_alt != *[!$' \t\r\n']* ]]; then
          if [[ $_src == *[$'\t\r\n']* ]]; then
            _zhtml2md_r_inline_code "$_src" || return $?
            if (( _zhtml2md_r_result_block )); then
              _zhtml2md_r_boundary
              _zhtml2md_r_inline "$_zhtml2md_r_result" || return $?
              _zhtml2md_r_boundary
            fi
          else
            _zhtml2md_r_prose "$_src" || return $?
          fi
        else
          _zhtml2md_r_normalize "$_alt" spaces
          _alt=$_zhtml2md_r_result
          local -a _words=( ${(s: :)_alt} )
          _alt=${(j: :)_words}
          _zhtml2md_r_escape "$_alt" || return $?
          _alt=$_zhtml2md_r_result
          _zhtml2md_r_destination "$_src" || return $?
          if (( _zhtml2md_r_destination_ok )); then
            _md="![$_alt]($_zhtml2md_r_result)"
            _zhtml2md_r_inline "$_md" || return $?
          else
            _zhtml2md_r_inline "$_alt" || return $?
            _zhtml2md_r_code "$_src" inline ''
            _md=$_zhtml2md_r_result
            if (( _zhtml2md_r_result_block )); then
              _zhtml2md_r_boundary; _zhtml2md_r_inline "$_md" || return $?
              _zhtml2md_r_boundary
            else
              _zhtml2md_r_inline " ($_md)" || return $?
            fi
          fi
        fi ;;
    esac
  fi
  return 0
}

_zhtml2md_markdown() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _zhtml2md_r_active=1 _zhtml2md_r_slot=1 _zhtml2md_r_serial=0 _zhtml2md_r_pending=0
  local -i _zhtml2md_r_tick_max=0 _zhtml2md_r_result_block=0 _zhtml2md_r_destination_ok=0
  local -i _zhtml2md_r_code_width=0 _zhtml2md_r_code_pad=0
  local _zhtml2md_r_result=''
  local -A _zhtml2md_r_piece=() _zhtml2md_r_next=() _zhtml2md_r_head=(1 0) _zhtml2md_r_tail=(1 0)
  local -A _zhtml2md_r_size=(1 0) _zhtml2md_r_kind=(1 root) _zhtml2md_r_id=() _zhtml2md_r_name=()
  local -A _zhtml2md_r_space=() _zhtml2md_r_block=() _zhtml2md_r_blocks=() _zhtml2md_r_leading=()
  local -A _zhtml2md_r_end=() _zhtml2md_r_dest=() _zhtml2md_r_language=() _zhtml2md_r_strip=()
  local -A _zhtml2md_r_single=() _zhtml2md_r_format=() _zhtml2md_r_links=() _zhtml2md_r_nested=()
  local -A _zhtml2md_r_digits=()
  local -A _zhtml2md_r_code_id=() _zhtml2md_r_code_edge=()
  local -i _zhtml2md_r_record_serial=0 _zhtml2md_r_record_new=0
  local -A _zhtml2md_r_scope=() _zhtml2md_r_cellctx=()
  local -A _zhtml2md_r_records_head=() _zhtml2md_r_records_tail=()
  local -A _zhtml2md_r_record_next=() _zhtml2md_r_record_kind=() _zhtml2md_r_record_text=()
  local -A _zhtml2md_r_record_name=() _zhtml2md_r_record_value=() _zhtml2md_r_record_child=()
  local -A _zhtml2md_r_record_rs=() _zhtml2md_r_record_cs=() _zhtml2md_r_record_flags=()
  local -A _zhtml2md_r_list_start=() _zhtml2md_r_list_reversed=() _zhtml2md_r_item_value=()
  local -A _zhtml2md_r_cell_rs=() _zhtml2md_r_cell_cs=()
  _zhtml2md_parse || return $?
  if (( _zhtml2md_r_slot != 1 || _zhtml2md_r_pending != 0 )); then
    _zhtml2md_fail internal '' 'renderer capture imbalance' 1
    return 1
  fi
  if (( _zhtml2md_r_size[1] )); then
    [[ ${_zhtml2md_r_end[1]} == $'\n' ]] || _zhtml2md_r_append $'\n' || return $?
  fi
  _zhtml2md_r_take
  _zhtml2md_output=$_zhtml2md_r_result
  return 0
}

if [[ $_zhtml2md_markdown_loadopt == on ]]; then
  'builtin' 'setopt' 'aliases'
fi
'builtin' 'unset' _zhtml2md_markdown_loadopt
