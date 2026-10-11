# SPDX-License-Identifier: Apache-2.0
# Named-reference data and one-pass character-reference decoding.
# Sourced by the library; the tokenizer will call the decoder only in
# eligible text/attribute contexts. No data is read merely by sourcing
# this module.
'builtin' 'typeset' _zhtml2md_entities_loadopt="$( 'builtin' 'set' '+o' )"
'builtin' 'setopt' 'noaliases'
if [[ $'\n'$_zhtml2md_entities_loadopt$'\n' == *$'\nset +o noaliases\n'* ||
      $'\n'$_zhtml2md_entities_loadopt$'\n' == *$'\nset -o aliases\n'* ]]; then
  _zhtml2md_entities_loadopt=on
else
  _zhtml2md_entities_loadopt=off
fi

# _zhtml2md_entity_number DIGITS BASE
# Writes the caller-local integer _zhtml2md_number. All digits are checked
# as text before arithmetic; long values saturate at U+110000, after a
# C-level scan removes leading zeros. Only <= 7 significant digits are
# accumulated. BASE is a trusted internal constant (10 or 16).
_zhtml2md_entity_number() {
  emulate -L zsh -o no_multibyte -o extended_glob
  local LC_ALL=C
  local _digits=$1 _char
  local MATCH
  local -i MBEGIN MEND
  local -a match mbegin mend
  local -i _base=$2 _value=0 _digit _i
  _zhtml2md_number=0
  case $_base in
    10) [[ $_digits == [0-9]## ]] || return 1 ;;
    16) [[ $_digits == [0-9A-Fa-f]## ]] || return 1 ;;
    *) return 1 ;;
  esac
  [[ $_digits == (#b)(0#)(*) ]]
  _digits=${match[2]}
  if (( ${#_digits} > 7 || (_base == 16 && ${#_digits} > 6) )); then
    _zhtml2md_number=1114112
    return 0
  fi
  for (( _i=1; _i <= ${#_digits}; ++_i )); do
    _char=${_digits[_i]}
    case $_char in
      [0-9]) (( _digit = #_char - 48 )) ;;
      [A-F]) (( _digit = #_char - 55 )) ;;
      [a-f]) (( _digit = #_char - 87 )) ;;
    esac
    (( _value = _value * _base + _digit ))
    if (( _value >= 1114112 )); then
      _zhtml2md_number=1114112
      return 0
    fi
  done
  _zhtml2md_number=$_value
  return 0
}

# _zhtml2md_scalar_utf8 INTEGER
# Encodes a trusted, validated scalar, writing caller-local
# _zhtml2md_scalar. The byte arithmetic and generated octal escapes do
# not depend on locale-sensitive %c or native modules. No stdout.
_zhtml2md_scalar_utf8() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _cp=$1
  local _esc=''
  _zhtml2md_scalar=''
  (( _cp > 0 && _cp <= 0x10ffff && ! (_cp >= 0xd800 && _cp <= 0xdfff) )) || return 1
  if (( _cp < 0x80 )); then
    builtin printf -v _esc '\\0%03o' $_cp
  elif (( _cp < 0x800 )); then
    builtin printf -v _esc '\\0%03o\\0%03o' \
      $(( 0xc0 | (_cp >> 6) )) $(( 0x80 | (_cp & 63) ))
  elif (( _cp < 0x10000 )); then
    builtin printf -v _esc '\\0%03o\\0%03o\\0%03o' \
      $(( 0xe0 | (_cp >> 12) )) $(( 0x80 | ((_cp >> 6) & 63) )) $(( 0x80 | (_cp & 63) ))
  else
    builtin printf -v _esc '\\0%03o\\0%03o\\0%03o\\0%03o' \
      $(( 0xf0 | (_cp >> 18) )) $(( 0x80 | ((_cp >> 12) & 63) )) \
      $(( 0x80 | ((_cp >> 6) & 63) )) $(( 0x80 | (_cp & 63) ))
  fi
  builtin printf -v _zhtml2md_scalar '%b' "$_esc"
}

# _zhtml2md_entities_init
# Lazily reads the installed TSV as literal data. Publishes only a fully
# validated cache (_ZHTML2MD_ENTITIES, _ZHTML2MD_ENTITIES_READY). On error
# no partial cache is retained; a repaired installation can be retried.
# Uses the caller's diagnostic context, like the other pipeline helpers.
# Owns one descriptor and closes it with always on every exit path.
_zhtml2md_entities_init() {
  emulate -L zsh -o no_multibyte -o extended_glob
  local LC_ALL=C
  (( ${+_ZHTML2MD_ENTITIES_READY} )) && return 0
  local _file=$_ZHTML2MD_DIR/data/entities.tsv
  local _fd=-1 _data='' _line _name _hex _value _zhtml2md_scalar=''
  local -i _zhtml2md_number=0 _count=0 _i
  local -a _lines=() _fields=()
  local -A _cache=()
  {
    if [[ ! -f $_file || ! -r $_file ]] || ! { exec {_fd}< "$_file"; } 2>/dev/null; then
      _zhtml2md_fail initialization '' 'cannot read named-reference data' 1
      return 1
    fi
    # 128 KiB comfortably bounds 2,125 rows of <= 31-byte names plus
    # two <= 6-digit scalars. Read one extra byte to detect overflow.
    { IFS= builtin read -r -u $_fd -k 131073 _data; } 2>/dev/null
    # A short read can return nonzero with the complete bytes retained.
    # Framing, field validation, and count checks decide validity.
    if [[ -z $_data ]] ||
       (( ${#_data} > 131072 )) || [[ $_data != *$'\n' ]]; then
      _zhtml2md_fail initialization '' 'invalid named-reference data size or framing' 1
      return 1
    fi
    _lines=( "${(@f)${_data%$'\n'}}" )
    for _line in "${_lines[@]}"; do
      _fields=( "${(@ps:\t:)_line}" )
      if (( ${#_fields} < 2 || ${#_fields} > 3 || ++_count > 2125 )); then
        _zhtml2md_fail initialization '' 'invalid named-reference data row' 1
        return 1
      fi
      _name=${_fields[1]}
      if [[ $_name != [A-Za-z][A-Za-z0-9]# ]] || (( ${#_name} > 31 || ${+_cache[$_name]} )); then
        _zhtml2md_fail initialization '' 'invalid or duplicate named-reference name' 1
        return 1
      fi
      _value=''
      for (( _i=2; _i <= ${#_fields}; ++_i )); do
        _hex=${_fields[_i]}
        if [[ $_hex != [0-9A-F]## ]] || (( ${#_hex} > 6 )); then
          _zhtml2md_fail initialization '' 'invalid named-reference scalar field' 1
          return 1
        fi
        _zhtml2md_entity_number "$_hex" 16 || return 1
        if (( _zhtml2md_number == 0 || _zhtml2md_number > 0x10ffff ||
              (_zhtml2md_number >= 0xd800 && _zhtml2md_number <= 0xdfff) ||
              (_zhtml2md_number < 32 && _zhtml2md_number != 9 && _zhtml2md_number != 10 && _zhtml2md_number != 13) ||
              _zhtml2md_number == 127 )); then
          _zhtml2md_fail initialization '' 'invalid named-reference Unicode scalar' 1
          return 1
        fi
        _zhtml2md_scalar_utf8 $_zhtml2md_number || return 1
        _value+=$_zhtml2md_scalar
      done
      _cache[$_name]=$_value
    done
    if (( _count != 2125 )); then
      _zhtml2md_fail initialization '' 'named-reference data must contain 2125 entries' 1
      return 1
    fi
    builtin typeset -gA _ZHTML2MD_ENTITIES
    _ZHTML2MD_ENTITIES=( "${(@kv)_cache}" )
    builtin typeset -gi _ZHTML2MD_ENTITIES_READY=1
  } always {
    if (( _fd >= 0 )); then
      { exec {_fd}<&-; } 2>/dev/null
    fi
  }
  return 0
}

# _zhtml2md_decode_entities TEXT ORIGINAL_BYTE_OFFSET
# Writes caller-local _zhtml2md_decoded, empty on failure. Reads the
# immutable entity cache and the usual diagnostic context. The offset
# locates TEXT in the unnormalized original input (including any BOM).
# Decodes once, requiring semicolons; unknown/malformed forms stay
# literal. Whitespace normalization belongs to the later renderer.
# Fragments join once, with the capture limit charged before append.
# Status: 0 success, 1 initialization, 3 decoded control, 4 capture limit.
_zhtml2md_decode_entities() {
  emulate -L zsh -o no_multibyte -o extended_glob
  local LC_ALL=C
  local _text=$1 _part _ref _digits _value _zhtml2md_scalar=''
  local MATCH
  local -i MBEGIN MEND
  local -a match mbegin mend
  local -i _offset=$2 _pos _i _used _total=0 _zhtml2md_number=0
  local -a _parts=() _fragments=()
  local -a _c1=( 8364 129 8218 402 8222 8230 8224 8225
                710 8240 352 8249 338 141 381 143
                144 8216 8217 8220 8221 8226 8211 8212
                732 8482 353 8250 339 157 382 376 )
  _zhtml2md_decoded=''
  if (( ${#_text} > _ZHTML2MD_LIMIT_CAPTURE )); then
    _zhtml2md_fail resource-limit $_offset 'decoded text exceeds capture limit' 4
    return 4
  fi
  # Do not load data for text without a possible character reference.
  if [[ $_text != *'&'* ]]; then
    _zhtml2md_decoded=$_text
    return 0
  fi
  _zhtml2md_entities_init || return 1
  _parts=( "${(@s:&:)_text}" )
  _fragments=( "${_parts[1]}" )
  (( _total = ${#_parts[1]}, _pos = _offset + _total ))
  for (( _i=2; _i <= ${#_parts}; ++_i )); do
    _part=${_parts[_i]}
    _used=0
    _value='&'
    # Constant native pattern; input is never executable pattern text.
    if [[ $_part == (#b)(([A-Za-z][A-Za-z0-9](#c0,30)|\#[0-9]##|\#[xX][0-9A-Fa-f]##)\;)* ]]; then
      _ref=${match[1]}
      if [[ $_ref == '#'* ]]; then
        if [[ $_ref == '#x'* || $_ref == '#X'* ]]; then
          _digits=${_ref[3,-2]}
          _zhtml2md_entity_number "$_digits" 16 || return 1
        else
          _digits=${_ref[2,-2]}
          _zhtml2md_entity_number "$_digits" 10 || return 1
        fi
        if (( _zhtml2md_number == 0 || _zhtml2md_number > 0x10ffff ||
              (_zhtml2md_number >= 0xd800 && _zhtml2md_number <= 0xdfff) )); then
          _zhtml2md_number=65533
        elif (( _zhtml2md_number >= 128 && _zhtml2md_number <= 159 )); then
          _zhtml2md_number=${_c1[_zhtml2md_number-127]}
        fi
        if (( (_zhtml2md_number < 32 && _zhtml2md_number != 9 && _zhtml2md_number != 10 && _zhtml2md_number != 13) ||
              _zhtml2md_number == 127 )); then
          _zhtml2md_fail forbidden-control $_pos 'forbidden control from character reference' 3
          return 3
        fi
        _zhtml2md_scalar_utf8 $_zhtml2md_number || return 1
        _value=$_zhtml2md_scalar
        _used=${#_ref}
      else
        _ref=${_ref[1,-2]}
        if (( ${+_ZHTML2MD_ENTITIES[$_ref]} )); then
          _value=${_ZHTML2MD_ENTITIES[$_ref]}
          (( _used = ${#_ref} + 1 ))
        fi
      fi
    fi
    (( _total += ${#_value} + ${#_part} - _used ))
    if (( _total > _ZHTML2MD_LIMIT_CAPTURE )); then
      _zhtml2md_fail resource-limit $_pos 'decoded text exceeds capture limit' 4
      return 4
    fi
    _fragments+=( "$_value" "${_part[_used+1,-1]}" )
    (( _pos += 1 + ${#_part} ))
  done
  _zhtml2md_decoded=${(j::)_fragments}
  return 0
}

if [[ $_zhtml2md_entities_loadopt == on ]]; then
  'builtin' 'setopt' 'aliases'
fi
'builtin' 'unset' _zhtml2md_entities_loadopt
