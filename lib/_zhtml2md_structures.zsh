# SPDX-License-Identifier: Apache-2.0
# Structured list/table captures own each retained payload once.
'builtin' 'typeset' _zhtml2md_structures_loadopt="$( 'builtin' 'set' '+o' )"
'builtin' 'setopt' 'noaliases'
if [[ $'\n'$_zhtml2md_structures_loadopt$'\n' == *$'\nset +o noaliases\n'* ||
      $'\n'$_zhtml2md_structures_loadopt$'\n' == *$'\nset -o aliases\n'* ]]; then
  _zhtml2md_structures_loadopt=on
else
  _zhtml2md_structures_loadopt=off
fi

# Record indices are generated counters; source text is never an index.
_zhtml2md_r_record_add() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _bytes=${#2} _slot=$_zhtml2md_r_slot _id
  if (( _zhtml2md_r_pending + _bytes > _ZHTML2MD_LIMIT_CAPTURE )); then
    _zhtml2md_fail resource-limit '' "pending captures exceed $_ZHTML2MD_LIMIT_CAPTURE bytes" 4
    return 4
  fi
  (( _zhtml2md_r_pending += _bytes ))
  (( _id = ++_zhtml2md_r_record_serial ))
  _zhtml2md_r_record_new=$_id
  _zhtml2md_r_record_kind[$_id]=$1
  _zhtml2md_r_record_text[$_id]=$2
  _zhtml2md_r_record_name[$_id]=$3
  _zhtml2md_r_record_value[$_id]=$4
  _zhtml2md_r_record_rs[$_id]=${5:-1}
  _zhtml2md_r_record_cs[$_id]=${6:-1}
  _zhtml2md_r_record_flags[$_id]=${7:-0}
  _zhtml2md_r_record_child[$_id]=${8:-0}
  if (( ${_zhtml2md_r_records_tail[$_slot]:-0} )); then
    _zhtml2md_r_record_next[${_zhtml2md_r_records_tail[$_slot]}]=$_id
  else
    _zhtml2md_r_records_head[$_slot]=$_id
  fi
  _zhtml2md_r_records_tail[$_slot]=$_id
  return 0
}

_zhtml2md_r_record_take() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  _zhtml2md_r_result=${_zhtml2md_r_record_text[$1]}
  (( _zhtml2md_r_pending -= ${#_zhtml2md_r_result} ))
  unset "_zhtml2md_r_record_text[$1]"
  return 0
}

_zhtml2md_r_record_drop() {
  emulate -L zsh
  unset "_zhtml2md_r_record_kind[$1]" "_zhtml2md_r_record_name[$1]" \
    "_zhtml2md_r_record_value[$1]" "_zhtml2md_r_record_rs[$1]" \
    "_zhtml2md_r_record_cs[$1]" "_zhtml2md_r_record_flags[$1]" \
    "_zhtml2md_r_record_child[$1]"
}

# Move preceding/trailing non-member text into the same ordered chain.
_zhtml2md_r_records_flush() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _slot=$_zhtml2md_r_slot
  if (( ${_zhtml2md_r_size[$_slot]:-0} )); then
    _zhtml2md_r_take
    _zhtml2md_r_record_add text "$_zhtml2md_r_result" '' '' || return $?
  fi
  _zhtml2md_r_end[$_slot]=''
  _zhtml2md_r_code_id[$_slot]=0
  _zhtml2md_r_digits[$_slot]=0
  _zhtml2md_r_space[$_slot]=0
  _zhtml2md_r_block[$_slot]=0
  return 0
}

# Prefix windows rather than repeatedly substituting across a whole body.
_zhtml2md_r_indent() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _body=$1 _first=$2 _rest=$3 _chunk
  local -a _parts=( "$_first" )
  local -i _at=1 _bytes=${#_first}
  if [[ -z $_body ]]; then
    _zhtml2md_r_result=${_first% }
    return 0
  fi
  while (( _at <= ${#_body} )); do
    _chunk=${_body[_at,_at+4095]}
    _chunk=${_chunk//$'\n'/$'\n'$_rest}
    (( _bytes += ${#_chunk} ))
    if (( _bytes > _ZHTML2MD_LIMIT_OUTPUT )); then
      _zhtml2md_fail resource-limit '' "output exceeds $_ZHTML2MD_LIMIT_OUTPUT bytes" 4
      return 4
    fi
    _parts+=( "$_chunk" )
    (( _at += 4096 ))
  done
  _zhtml2md_r_result=${(j::)_parts}
  return 0
}

_zhtml2md_r_structure_open() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _name=$1
  case ${_zhtml2md_r_scope[$_zhtml2md_r_slot]}:$_name in
    list:li|table:tr|table:td|table:th|table:caption|row:td|row:th)
      _zhtml2md_r_records_flush || return $? ;;
  esac
  _zhtml2md_r_boundary
  case $_name in
    ul|ol)
      _zhtml2md_r_push list
      _zhtml2md_r_scope[$_zhtml2md_r_slot]=list
      _zhtml2md_r_list_start[$_zhtml2md_r_slot]=${_zhtml2md_event_attrs[start]}
      _zhtml2md_r_list_reversed[$_zhtml2md_r_slot]=${+_zhtml2md_event_attrs[reversed]} ;;
    li)
      _zhtml2md_r_push item
      _zhtml2md_r_scope[$_zhtml2md_r_slot]=''
      _zhtml2md_r_item_value[$_zhtml2md_r_slot]=${_zhtml2md_event_attrs[value]} ;;
    table) _zhtml2md_r_push table; _zhtml2md_r_scope[$_zhtml2md_r_slot]=table ;;
    tr) _zhtml2md_r_push row; _zhtml2md_r_scope[$_zhtml2md_r_slot]=row ;;
    td|th)
      _zhtml2md_r_push cell
      _zhtml2md_r_scope[$_zhtml2md_r_slot]=''
      _zhtml2md_r_cellctx[$_zhtml2md_r_slot]=1
      _zhtml2md_r_cell_rs[$_zhtml2md_r_slot]=${_zhtml2md_event_attrs[rowspan]:-1}
      _zhtml2md_r_cell_cs[$_zhtml2md_r_slot]=${_zhtml2md_event_attrs[colspan]:-1} ;;
    caption) _zhtml2md_r_push caption; _zhtml2md_r_scope[$_zhtml2md_r_slot]='' ;;
  esac
  _zhtml2md_r_single[$_zhtml2md_r_slot]=0
  return 0
}

# A wrapper around structural members preserves the chain in source order.
# Block-bearing links retain their destination as a separate code block.
_zhtml2md_r_inline_records_close() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _slot=$_zhtml2md_r_slot _head _tail
  local _kind=${_zhtml2md_r_kind[$_slot]} _dest=${_zhtml2md_r_dest[$_slot]}
  _zhtml2md_r_records_flush || return $?
  if [[ $_kind == link && -n $_dest ]]; then
    _zhtml2md_r_code "$_dest" inline '' || return $?
    _zhtml2md_r_record_add text "$_zhtml2md_r_result" '' '' || return $?
  fi
  _head=${_zhtml2md_r_records_head[$_slot]:-0}
  _tail=${_zhtml2md_r_records_tail[$_slot]:-0}
  _zhtml2md_r_records_head[$_slot]=0 _zhtml2md_r_records_tail[$_slot]=0
  _zhtml2md_r_nested[$_slot]=0
  (( --_zhtml2md_r_slot ))
  _zhtml2md_r_records_flush || return $?
  if (( ${_zhtml2md_r_records_tail[$_zhtml2md_r_slot]:-0} )); then
    _zhtml2md_r_record_next[${_zhtml2md_r_records_tail[$_zhtml2md_r_slot]}]=$_head
  else
    _zhtml2md_r_records_head[$_zhtml2md_r_slot]=$_head
  fi
  _zhtml2md_r_records_tail[$_zhtml2md_r_slot]=$_tail
  _zhtml2md_r_blocks[$_zhtml2md_r_slot]=1
  _zhtml2md_r_single[$_zhtml2md_r_slot]=0
  return 0
}

_zhtml2md_r_structure_close() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _slot=$_zhtml2md_r_slot _head=0 _flags=${_zhtml2md_r_blocks[$_zhtml2md_r_slot]:-0}
  local _kind=${_zhtml2md_r_kind[$_slot]} _name=${_zhtml2md_r_name[$_slot]}
  local _value=${_zhtml2md_r_item_value[$_slot]} _start=${_zhtml2md_r_list_start[$_slot]}
  local _rev=${_zhtml2md_r_list_reversed[$_slot]:-0}
  local _rs=${_zhtml2md_r_cell_rs[$_slot]:-1} _cs=${_zhtml2md_r_cell_cs[$_slot]:-1} _body
  case $_kind in
    list|table|row)
      _zhtml2md_r_records_flush || return $?
      _head=${_zhtml2md_r_records_head[$_slot]:-0} ;;
    *) _zhtml2md_r_take; _body=$_zhtml2md_r_result ;;
  esac
  _zhtml2md_r_records_head[$_slot]=0 _zhtml2md_r_records_tail[$_slot]=0
  (( --_zhtml2md_r_slot ))
  case $_kind in
    list) _zhtml2md_r_list_emit $_head "$_name" "$_start" "$_rev" || return $? ;;
    table) _zhtml2md_r_table_emit $_head || return $? ;;
    row)
      if [[ ${_zhtml2md_r_scope[$_zhtml2md_r_slot]} == table ]]; then
        _zhtml2md_r_record_add row '' '' '' 1 1 0 $_head || return $?
        return 0
      fi
      _zhtml2md_r_row_build $_head || return $?
      _zhtml2md_r_boundary
      _zhtml2md_r_inline "$_zhtml2md_r_result" || return $?
      _zhtml2md_r_boundary ;;
    item|cell|caption)
      case ${_zhtml2md_r_scope[$_zhtml2md_r_slot]}:$_kind in
        list:item|row:cell|table:cell|table:caption)
          _zhtml2md_r_record_add "$_kind" "$_body" "$_name" "$_value" "$_rs" "$_cs" "$_flags" || return $?
          return 0 ;;
      esac
      if [[ $_kind == item ]]; then
        _zhtml2md_r_indent "$_body" '- ' '  ' || return $?
        _body=$_zhtml2md_r_result
      elif [[ $_kind == cell ]]; then
        _zhtml2md_r_cell_label "$_body" "$_name" "$_rs" "$_cs" "$_flags"
        _body=$_zhtml2md_r_result
      fi
      _zhtml2md_r_boundary
      _zhtml2md_r_inline "$_body" || return $?
      _zhtml2md_r_boundary ;;
  esac
  _zhtml2md_r_blocks[$_zhtml2md_r_slot]=1
  _zhtml2md_r_single[$_zhtml2md_r_slot]=0
  return 0
}

_zhtml2md_r_list_emit() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _head=$1 _id=$1 _next _count=0 _loose=0 _native=1 _number=1 _previous=0 _seen=0 _step=1 _adjacent=0
  local _name=$2 _start=$3 _rev=$4 _body _marker _indent
  local -A _numbers=()
  while (( _id )); do
    if [[ ${_zhtml2md_r_record_kind[$_id]} == item ]]; then
      (( ++_count ))
      [[ ${_zhtml2md_r_record_text[$_id]} == *$'\n\n'* ]] && _loose=1
    fi
    _id=${_zhtml2md_r_record_next[$_id]:-0}
  done
  if [[ $_name == ol ]]; then
    if [[ -n $_start ]]; then _number=$_start
    elif [[ $_rev == 1 ]]; then _number=$_count; fi
    [[ $_rev == 1 ]] && _step=-1
    _id=$_head
    while (( _id )); do
      if [[ ${_zhtml2md_r_record_kind[$_id]} == item ]]; then
        [[ -n ${_zhtml2md_r_record_value[$_id]} ]] && _number=${_zhtml2md_r_record_value[$_id]}
        _numbers[$_id]=$_number
        (( _number < 0 || _number > 999999999 || (_seen && _number != _previous + 1) )) && _native=0
        _previous=$_number _seen=1
        (( _number += _step ))
      fi
      _id=${_zhtml2md_r_record_next[$_id]:-0}
    done
  fi
  _zhtml2md_r_boundary
  _id=$_head
  while (( _id )); do
    _next=${_zhtml2md_r_record_next[$_id]:-0}
    if [[ ${_zhtml2md_r_record_kind[$_id]} == item ]]; then
      _zhtml2md_r_record_take $_id
      _body=$_zhtml2md_r_result
      _marker='- ' _indent='  '
      if [[ $_name == ol ]]; then
        if (( _native )); then
          _marker="${_numbers[$_id]}. "
          builtin printf -v _indent '%*s' ${#_marker} ''
        else
          _marker="- ${_numbers[$_id]}\\. "
        fi
      fi
      _zhtml2md_r_indent "$_body" "$_marker" "$_indent" || return $?
      _body=$_zhtml2md_r_result
      if (( _adjacent )); then
        if (( _loose )); then _zhtml2md_r_append $'\n\n' || return $?
        else _zhtml2md_r_append $'\n' || return $?; fi
      fi
      _zhtml2md_r_inline "$_body" || return $?
      _adjacent=1
    else
      _zhtml2md_r_record_take $_id
      _body=$_zhtml2md_r_result
      _zhtml2md_r_boundary
      _zhtml2md_r_inline "$_body" || return $?
      _zhtml2md_r_boundary
      _adjacent=0
    fi
    _zhtml2md_r_record_drop $_id
    unset "_zhtml2md_r_record_next[$_id]"
    _id=$_next
  done
  _zhtml2md_r_boundary
  return 0
}

# Only generated inline code delimiters are interpreted here. Outside
# code, existing context escapes stay intact; inside code each pipe needs
# its own GFM escape, including a pipe preceded by a literal backslash.
_zhtml2md_r_cell_encode() {
  emulate -L zsh -o no_multibyte -o extended_glob
  local LC_ALL=C
  local _s=$1 _chunk _out _prefix _char _ticks _special='\`|'
  local -a _parts=() match mbegin mend
  local MATCH MBEGIN MEND
  local -i _at=1 _pos _run=0 _delimiter=0 _escaped=0 _bytes=0
  while (( _at <= ${#_s} )); do
    _chunk=${_s[_at,_at+4095]} _out=''
    while [[ -n $_chunk ]]; do
      if [[ $_chunk == (#b)([^$_special]#)[$_special]* ]]; then
        _pos=$(( ${#match[1]} + 1 ))
      else
        _pos=$(( ${#_chunk} + 1 ))
      fi
      if (( _pos > 1 )); then
        if (( _run )); then
          if (( !_delimiter )); then _delimiter=$_run
          elif (( _delimiter == _run )); then _delimiter=0; fi
          _run=0
        fi
        _prefix=${_chunk[1,_pos-1]}
        _out+=$_prefix
        _escaped=0
        _chunk=${_chunk[_pos,-1]}
        [[ -n $_chunk ]] || break
      fi
      _char=${_chunk[1]}
      if [[ $_char == '`' && $_escaped == 0 ]]; then
        [[ $_chunk == (#b)(\`##)* ]]
        _ticks=${match[1]}
        (( _run += ${#_ticks} ))
        _out+=$_ticks
        _chunk=${_chunk[${#_ticks}+1,-1]}
        continue
      fi
      if (( _run )); then
        if (( !_delimiter )); then _delimiter=$_run
        elif (( _delimiter == _run )); then _delimiter=0; fi
        _run=0
      fi
      if [[ $_char == '|' && ( $_delimiter != 0 || $_escaped == 0 ) ]]; then
        _out+='\|'
      else
        _out+=$_char
      fi
      if (( !_delimiter && !_escaped )) && [[ $_char == '\' ]]; then _escaped=1
      else _escaped=0; fi
      _chunk=${_chunk[2,-1]}
    done
    (( _bytes += ${#_out} ))
    if (( _bytes > _ZHTML2MD_LIMIT_OUTPUT )); then
      _zhtml2md_fail resource-limit '' "output exceeds $_ZHTML2MD_LIMIT_OUTPUT bytes" 4
      return 4
    fi
    _parts+=( "$_out" )
    (( _at += 4096 ))
  done
  _zhtml2md_r_result=${(j::)_parts}
  return 0
}

_zhtml2md_r_cell_label() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local _body=$1 _name=$2 _rs=$3 _cs=$4 _flags=$5 _label=Cell _meta=''
  [[ $_name == th ]] && _label=Header
  [[ $_rs != 1 ]] && _meta="rowspan=$_rs"
  if [[ $_cs != 1 ]]; then
    [[ -n $_meta ]] && _meta+=', '
    _meta+="colspan=$_cs"
  fi
  [[ -n $_meta ]] && _label+=" ($_meta)"
  _label+=':'
  if [[ -n $_body ]]; then
    if [[ $_flags == 1 || $_body == *$'\n'* ]]; then _label+=$'\n\n'$_body
    else _label+=" $_body"; fi
  fi
  _zhtml2md_r_result=$_label
  return 0
}

# Consume one source row's cells. Notes among cells remain paragraphs.
_zhtml2md_r_row_build() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _id=$1 _next _number=0 _bytes=0 _adjacent=0 _member
  local _name _rs _cs _flags _body _marker _indent
  local -a _parts=()
  while (( _id )); do
    _next=${_zhtml2md_r_record_next[$_id]:-0}
    _name=${_zhtml2md_r_record_name[$_id]}
    _rs=${_zhtml2md_r_record_rs[$_id]:-1} _cs=${_zhtml2md_r_record_cs[$_id]:-1}
    _flags=${_zhtml2md_r_record_flags[$_id]:-0}
    _zhtml2md_r_record_take $_id
    _body=$_zhtml2md_r_result
    _member=0
    if [[ ${_zhtml2md_r_record_kind[$_id]} == cell ]]; then
      _member=1
      (( ++_number ))
      _zhtml2md_r_cell_label "$_body" "$_name" "$_rs" "$_cs" "$_flags"
      _marker="$_number. "
      builtin printf -v _indent '%*s' ${#_marker} ''
      _zhtml2md_r_indent "$_zhtml2md_r_result" "$_marker" "$_indent" || return $?
      _body=$_zhtml2md_r_result
    fi
    if [[ -n $_body ]]; then
      if (( ${#_parts} )); then
        if (( _adjacent && _member )); then
          _parts+=( $'\n' ); (( ++_bytes ))
        else
          _parts+=( $'\n\n' ); (( _bytes += 2 ))
        fi
      fi
      _parts+=( "$_body" )
      (( _bytes += ${#_body} ))
      _adjacent=$_member
      if (( _bytes > _ZHTML2MD_LIMIT_OUTPUT )); then
        _zhtml2md_fail resource-limit '' "output exceeds $_ZHTML2MD_LIMIT_OUTPUT bytes" 4
        return 4
      fi
    fi
    _zhtml2md_r_record_drop $_id
    unset "_zhtml2md_r_record_next[$_id]"
    _id=$_next
  done
  _zhtml2md_r_result=${(j::)_parts}
  return 0
}

_zhtml2md_r_table_line() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _id=$1 _next _bytes=1
  local _cell
  local -a _parts=( '|' )
  while (( _id )); do
    _next=${_zhtml2md_r_record_next[$_id]:-0}
    _zhtml2md_r_record_take $_id
    _zhtml2md_r_cell_encode "$_zhtml2md_r_result" || return $?
    _cell=$_zhtml2md_r_result
    (( _bytes += ${#_cell} + 3 ))
    if (( _bytes > _ZHTML2MD_LIMIT_OUTPUT )); then
      _zhtml2md_fail resource-limit '' "output exceeds $_ZHTML2MD_LIMIT_OUTPUT bytes" 4
      return 4
    fi
    _parts+=( " $_cell |" )
    _zhtml2md_r_record_drop $_id
    unset "_zhtml2md_r_record_next[$_id]"
    _id=$_next
  done
  _zhtml2md_r_result=${(j::)_parts}
  return 0
}

_zhtml2md_r_table_emit() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _head=$1 _id=$1 _next _child _width=0 _cells _rows=0 _simple=1 _header=1 _number=0 _j _bytes
  local _kind _body _line _marker _indent _divider='|' _empty='|'
  while (( _id )); do
    _kind=${_zhtml2md_r_record_kind[$_id]}
    if [[ $_kind == row ]]; then
      _child=${_zhtml2md_r_record_child[$_id]:-0} _cells=0
      while (( _child )); do
        if [[ ${_zhtml2md_r_record_kind[$_child]} != cell ]]; then _simple=0
        else
          (( ++_cells ))
          if [[ ${_zhtml2md_r_record_rs[$_child]} != 1 || ${_zhtml2md_r_record_cs[$_child]} != 1 ||
                ${_zhtml2md_r_record_flags[$_child]} != 0 || ${_zhtml2md_r_record_text[$_child]} == *$'\n'* ]]; then _simple=0; fi
          if (( !_rows )) && [[ ${_zhtml2md_r_record_name[$_child]} != th ]]; then _header=0; fi
        fi
        _child=${_zhtml2md_r_record_next[$_child]:-0}
      done
      if (( !_rows )); then _width=$_cells
      elif (( _width != _cells )); then _simple=0; fi
      (( ++_rows ))
    elif [[ $_kind != caption ]]; then _simple=0; fi
    _id=${_zhtml2md_r_record_next[$_id]:-0}
  done
  # Captions are emitted first, even when supplied after a row.
  _id=$_head
  while (( _id )); do
    if [[ ${_zhtml2md_r_record_kind[$_id]} == caption ]]; then
      _zhtml2md_r_record_take $_id
      _body=$_zhtml2md_r_result
      _zhtml2md_r_boundary
      _zhtml2md_r_inline "$_body" || return $?
      _zhtml2md_r_boundary
      _zhtml2md_r_record_drop $_id
    fi
    _id=${_zhtml2md_r_record_next[$_id]:-0}
  done
  _zhtml2md_r_boundary
  if (( _simple && _width )); then
    for (( _j=0; _j<_width; ++_j )); do _divider+=' --- |'; _empty+='  |'; done
    if (( !_header )); then
      _zhtml2md_r_inline "$_empty" || return $?
      _zhtml2md_r_append $'\n'"$_divider" || return $?
    fi
  fi
  _id=$_head
  while (( _id )); do
    _next=${_zhtml2md_r_record_next[$_id]:-0}
    _kind=${_zhtml2md_r_record_kind[$_id]}
    if [[ $_kind == row ]]; then
      _child=${_zhtml2md_r_record_child[$_id]:-0}
      (( ++_number ))
      if (( _simple && _width )); then
        _zhtml2md_r_table_line $_child || return $?
        _line=$_zhtml2md_r_result
        if (( _number == 1 && _header )); then
          _zhtml2md_r_inline "$_line" || return $?
          _zhtml2md_r_append $'\n'"$_divider" || return $?
        else
          _zhtml2md_r_append $'\n'"$_line" || return $?
        fi
      elif (( !_simple )); then
        _zhtml2md_r_row_build $_child || return $?
        _body="Row $_number"
        [[ -n $_zhtml2md_r_result ]] && _body+=$'\n\n'$_zhtml2md_r_result
        _marker="$_number. "
        builtin printf -v _indent '%*s' ${#_marker} ''
        _zhtml2md_r_indent "$_body" "$_marker" "$_indent" || return $?
        _line=$_zhtml2md_r_result
        _zhtml2md_r_boundary
        _zhtml2md_r_inline "$_line" || return $?
        _zhtml2md_r_boundary
      fi
      _zhtml2md_r_record_take $_id
    elif [[ $_kind == cell ]]; then
      # A cell outside an explicit tr is retained as its own source row.
      (( ++_number ))
      _body=${_zhtml2md_r_record_text[$_id]}
      _zhtml2md_r_cell_label "$_body" "${_zhtml2md_r_record_name[$_id]}" \
        "${_zhtml2md_r_record_rs[$_id]}" "${_zhtml2md_r_record_cs[$_id]}" "${_zhtml2md_r_record_flags[$_id]}"
      _zhtml2md_r_indent "$_zhtml2md_r_result" '1. ' '   ' || return $?
      _body="Row $_number"$'\n\n'$_zhtml2md_r_result
      _marker="$_number. "
      builtin printf -v _indent '%*s' ${#_marker} ''
      _zhtml2md_r_indent "$_body" "$_marker" "$_indent" || return $?
      _line=$_zhtml2md_r_result
      _zhtml2md_r_record_take $_id
      _zhtml2md_r_boundary
      _zhtml2md_r_inline "$_line" || return $?
      _zhtml2md_r_boundary
    elif [[ $_kind == text ]]; then
      _zhtml2md_r_record_take $_id
      _body=$_zhtml2md_r_result
      _zhtml2md_r_boundary
      _zhtml2md_r_inline "$_body" || return $?
      _zhtml2md_r_boundary
    fi
    _zhtml2md_r_record_drop $_id
    unset "_zhtml2md_r_record_next[$_id]"
    _id=$_next
  done
  _zhtml2md_r_boundary
  return 0
}

if [[ $_zhtml2md_structures_loadopt == on ]]; then 'builtin' 'setopt' 'aliases'; fi
'builtin' 'unset' '_zhtml2md_structures_loadopt'
