# lib/_zhtml2md_input.zsh - input reading, encoding validation, BOM.
#
# Sourced by zhtml2md.zsh. The guard below protects this file's parse if
# it is ever sourced directly; it is harmless when sourced from the
# loader (NO_ALIASES is already in effect there).


'builtin' 'typeset' _zhtml2md_input_loadopt=${options[aliases]:-off}
'builtin' 'setopt' 'noaliases'

# _zhtml2md_read_all
#
# Reads the complete input into memory with a bounded chunk reader.
#   Reads:  _zhtml2md_in_path   (empty or '-' reads stdin)
#   Writes: _zhtml2md_input
#   Status: 0 ok, 1 input-io, 4 resource-limit
#
# Uses one owned descriptor (a duplicate of stdin when reading stdin) and
# always closes it. The reader is blocking until EOF; writer timeouts are
# the caller's responsibility by contract.
_zhtml2md_read_all() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C

  _zhtml2md_input=''
  local _zhtml2md_fd=-1
  local _zhtml2md_chunk
  local -i _zhtml2md_total=0

  {
    if [[ -n $_zhtml2md_in_path && $_zhtml2md_in_path != '-' ]]; then
      if [[ -d $_zhtml2md_in_path ]]; then
        _zhtml2md_fail input-io '' 'input is a directory' 1
        return 1
      fi
      # Redirections are wrapped in a brace group: a bare `exec ... 2>...'
      # would apply the stderr redirection to the whole shell permanently.
      { exec {_zhtml2md_fd}< "$_zhtml2md_in_path" ; } 2>/dev/null || {
        _zhtml2md_fail input-io '' "cannot open input file" 1
        return 1
      }
    else
      # Duplicate stdin onto an owned descriptor; the caller's fd 0 is
      # consumed but never closed or repositioned by us.
      { exec {_zhtml2md_fd}<&0 ; } 2>/dev/null || {
        _zhtml2md_fail input-io '' 'cannot read standard input' 1
        return 1
      }
    fi

    # Partial final reads return data with a nonzero status on pipes and
    # status 0 on regular files, so the loop continues while data arrived
    # and stops only on a failed empty read.
    while { IFS= read -r -u $_zhtml2md_fd -k 65536 _zhtml2md_chunk ; } 2>/dev/null ||
          (( ${#_zhtml2md_chunk} > 0 ))
    do
      (( ${#_zhtml2md_chunk} == 0 )) && break
      (( _zhtml2md_total += ${#_zhtml2md_chunk} ))
      if (( _zhtml2md_total > _ZHTML2MD_LIMIT_INPUT )); then
        _zhtml2md_fail resource-limit '' \
          "input exceeds $_ZHTML2MD_LIMIT_INPUT bytes" 4
        return 4
      fi
      _zhtml2md_input+=$_zhtml2md_chunk
      _zhtml2md_chunk=''
    done
  } always {
    if (( _zhtml2md_fd >= 0 )); then
      { exec {_zhtml2md_fd}<&- ; } 2>/dev/null
    fi
  }
  return 0
}

# _zhtml2md_validate_encoding
#
# Validates the raw input buffer: NUL and forbidden C0/DEL controls,
# UTF-8 well-formedness, and the optional initial BOM.
#   Reads:  _zhtml2md_input
#   Writes: _zhtml2md_bom (3 when a BOM is present, else 0)
#   Status: 0 ok, 3 forbidden-control / invalid-utf8
#
# Diagnostics report zero-based byte offsets in the original input,
# including the BOM. Validation is byte-oriented under a C locale.
_zhtml2md_validate_encoding() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C

  _zhtml2md_bom=0
  local _s=$_zhtml2md_input
  local -i _n=${#_s}

  # NUL: metafied by the reader, detectable with a literal pattern. The
  # (i) subscript flag cannot match it, so use a prefix strip instead.
  if [[ $_s == *$'\x00'* ]]; then
    local _pre=${_s%%$'\x00'*}
    _zhtml2md_fail forbidden-control ${#_pre} 'NUL byte in input' 3
    return 3
  fi

  # Forbidden C0 controls other than HT/LF/CR, plus DEL.
  local _ctrl=$'[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]'
  if [[ $_s == *${~_ctrl}* ]]; then
    local _pre=${_s%%${~_ctrl}*}
    _zhtml2md_fail forbidden-control ${#_pre} 'forbidden control byte in input' 3
    return 3
  fi

  # Optional initial UTF-8 BOM is accepted and recorded.
  if [[ ${_s[1,3]} == $'\xef\xbb\xbf' ]]; then
    _zhtml2md_bom=3
  fi

  # ASCII fast path: one C-level scan, no copies.
  local _hi=$'[\x80-\xff]'
  [[ $_s != *${~_hi}* ]] && return 0

  # Detailed UTF-8 validation. A bounded window locates non-ASCII bytes
  # without copying the whole tail per hit; each found sequence is then
  # checked arithmetically, and dense non-ASCII runs are walked
  # sequentially so the window is not re-sliced per character.
  local -i _pos=1
  local _c _c1 _c2 _c3 _win _pre2
  while (( _pos <= _n )); do
    _win=${_s[_pos,_pos+4095]}
    _pre2=${_win%%${~_hi}*}
    if (( ${#_pre2} == ${#_win} )); then
      (( _pos += ${#_win} ))
      continue
    fi
    (( _pos += ${#_pre2} ))
    while (( _pos <= _n )); do
      _c=${_s[_pos]}
      local -i _b0=$(( #_c ))
      (( _b0 < 0x80 )) && break
      local -i _len _lo=0x80 _hi2=0xBF
      if   (( _b0 >= 0xC2 && _b0 <= 0xDF )); then
        _len=2
      elif (( _b0 == 0xE0 )); then
        _len=3; _lo=0xA0
      elif (( _b0 == 0xED )); then
        _len=3; _hi2=0x9F
      elif (( _b0 >= 0xE1 && _b0 <= 0xEF )); then
        _len=3
      elif (( _b0 == 0xF0 )); then
        _len=4; _lo=0x90
      elif (( _b0 == 0xF4 )); then
        _len=4; _hi2=0x8F
      elif (( _b0 >= 0xF1 && _b0 <= 0xF3 )); then
        _len=4
      else
        _zhtml2md_fail invalid-utf8 $(( _pos - 1 )) 'invalid UTF-8 leading byte' 3
        return 3
      fi
      if (( _pos + _len - 1 > _n )); then
        _zhtml2md_fail invalid-utf8 $(( _pos - 1 )) 'truncated UTF-8 sequence' 3
        return 3
      fi
      _c1=${_s[_pos+1]}
      local -i _b1=$(( #_c1 ))
      if (( _b1 < _lo || _b1 > _hi2 )); then
        _zhtml2md_fail invalid-utf8 $(( _pos - 1 )) 'invalid UTF-8 continuation byte' 3
        return 3
      fi
      if (( _len >= 3 )); then
        _c2=${_s[_pos+2]}
        local -i _b2=$(( #_c2 ))
        if (( _b2 < 0x80 || _b2 > 0xBF )); then
          _zhtml2md_fail invalid-utf8 $(( _pos - 1 )) 'invalid UTF-8 continuation byte' 3
          return 3
        fi
      fi
      if (( _len == 4 )); then
        _c3=${_s[_pos+3]}
        local -i _b3=$(( #_c3 ))
        if (( _b3 < 0x80 || _b3 > 0xBF )); then
          _zhtml2md_fail invalid-utf8 $(( _pos - 1 )) 'invalid UTF-8 continuation byte' 3
          return 3
        fi
      fi
      (( _pos += _len ))
    done
  done
  return 0
}

# Restore the caller's ALIASES setting (see the guard at the top).
if [[ $_zhtml2md_input_loadopt == on ]]; then
  'builtin' 'setopt' 'aliases'
fi
'builtin' 'unset' _zhtml2md_input_loadopt
