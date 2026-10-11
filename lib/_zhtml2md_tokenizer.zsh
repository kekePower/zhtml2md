# Stateful byte tokenizer. The parser declares the namespaced context;
# tokens are parameters, never serialized shell code. Source offsets are
# zero-based, with exclusive ends, in the original input including BOM.
'builtin' 'typeset' _zhtml2md_tokenizer_loadopt=${options[aliases]:-off}
'builtin' 'setopt' 'noaliases'

# Initialize the '<' index once using C-level splitting. Subsequent
# seeks advance a cursor through these offsets; no repeated whole-tail
# search or copy is needed for ordinary text or raw closing candidates.
# Writes: _zhtml2md_lex_segments/lt, _zhtml2md_lex_index/pos/raw/size/count.
# Associations have generated integer-string keys. Selecting repeatedly
# from large indexed arrays measured poorly; active stack arrays stay
# bounded and do not have this issue.
_zhtml2md_lex_init() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -a _segments=( "${(@s:<:)${_zhtml2md_input[_zhtml2md_bom+1,-1]}}" )
  local _segment
  local -i _i=1 _offset=$_zhtml2md_bom
  _zhtml2md_lex_count=$(( ${#_segments} - 1 ))
  _zhtml2md_lex_segments=()
  _zhtml2md_lex_lt=()
  for _segment in "${_segments[@]}"; do
    _zhtml2md_lex_segments[$_i]=$_segment
    (( _offset += ${#_segment} ))
    if (( _i <= _zhtml2md_lex_count )); then
      _zhtml2md_lex_lt[$_i]=$_offset
      (( ++_offset ))
    fi
    (( ++_i ))
  done
  _zhtml2md_lex_index=1
  _zhtml2md_lex_pos=$_zhtml2md_bom
  _zhtml2md_lex_size=${#_zhtml2md_input}
  _zhtml2md_lex_raw=''
  return 0
}

# Tag-local context: grow the candidate geometrically from '<' segments,
# up to the tag cap plus one byte. Normal short tags never copy a 64 KiB
# candidate or repeatedly slice the full input. Called only when a lexer
# state exhausts its current window (initial call builds 256 bytes).
_zhtml2md_lex_tag_grow() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  (( _window < _ZHTML2MD_LIMIT_TAG + 1 && _start + _n < _zhtml2md_lex_size )) || return 1
  (( _window = _window ? _window * 2 : 256 ))
  (( _window > _ZHTML2MD_LIMIT_TAG + 1 )) && _window=$(( _ZHTML2MD_LIMIT_TAG + 1 ))
  _candidate='<'
  local -i _j _need
  for (( _j=_ordinal+1; _j <= _zhtml2md_lex_count+1; ++_j )); do
    (( _need = _window - ${#_candidate} ))
    if (( ${#_zhtml2md_lex_segments[$_j]} >= _need )); then
      _candidate+=${_zhtml2md_lex_segments[$_j][1,_need]}
      break
    fi
    _candidate+=${_zhtml2md_lex_segments[$_j]}
    (( _j <= _zhtml2md_lex_count )) && _candidate+='<'
    (( ${#_candidate} >= _window )) && break
  done
  _n=${#_candidate}
  return 0
}

# Parse one bounded tag candidate at offset $1 / '<' ordinal $2.
# Does not advance the lexer cursor. Writes token name, kind, end,
# self-closing flag, attrs and their value offsets. Status 5 means
# unfinished at EOF (caller chooses literal versus raw-text handling).
# Attribute states deliberately accept nonconforming but complete
# syntax without inventing repairs absent from the v1 recovery list.
_zhtml2md_lex_tag() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _start=$1 _ordinal=$2 _window=0 _p=2 _q _begin _vbegin _n=0 _closing=0
  local _candidate=''
  local _c _name _value _quote
  _zhtml2md_lex_tag_grow || return 5
  _zhtml2md_token_attrs=()
  _zhtml2md_token_attr_names=()
  _zhtml2md_token_attr_offsets=()
  _zhtml2md_token_self=0
  [[ $_candidate[_p] == / ]] && { _closing=1; (( ++_p )); }
  _begin=$_p
  while (( _p <= _n )) || _zhtml2md_lex_tag_grow; do
    _c=${_candidate[_p]}
    [[ $_c == [\ $'\t\r\n'/\>] ]] && break
    (( ++_p ))
  done
  _zhtml2md_token_name=${(L)_candidate[_begin,_p-1]}
  _zhtml2md_token_kind=start
  (( _closing )) && _zhtml2md_token_kind=end
  while (( _p <= _n )) || _zhtml2md_lex_tag_grow; do
    _c=${_candidate[_p]}
    case $_c in
      [\ $'\t\r\n']) (( ++_p )); continue ;;
      '>')
        if (( _p > _ZHTML2MD_LIMIT_TAG )); then
          _zhtml2md_fail resource-limit $_start 'ordinary tag exceeds 65536 bytes' 4
          return 4
        fi
        (( _zhtml2md_token_end = _start + _p ))
        return 0 ;;
      '/')
        (( _q = _p + 1 ))
        while { (( _q <= _n )) || _zhtml2md_lex_tag_grow; } && [[ ${_candidate[_q]} == [\ $'\t\r\n'] ]]; do
          (( ++_q ))
        done
        [[ ${_candidate[_q]} == '>' ]] && _zhtml2md_token_self=1
        (( ++_p )); continue ;;
    esac
    # Before/name/after attribute name, then before/quoted/unquoted value.
    _begin=$_p
    while (( _p <= _n )) || _zhtml2md_lex_tag_grow; do
      _c=${_candidate[_p]}
      [[ $_c == [\ $'\t\r\n'/=\>] ]] && break
      (( ++_p ))
    done
    # A stray '=' is a literal attribute name, rather than a retry loop.
    if (( _p == _begin )); then
      (( ++_p ))
    fi
    _name=${(L)_candidate[_begin,_p-1]}
    while { (( _p <= _n )) || _zhtml2md_lex_tag_grow; } && [[ ${_candidate[_p]} == [\ $'\t\r\n'] ]]; do
      (( ++_p ))
    done
    _value=''
    _vbegin=$_p
    if [[ ${_candidate[_p]} == '=' ]]; then
      (( ++_p ))
      while { (( _p <= _n )) || _zhtml2md_lex_tag_grow; } && [[ ${_candidate[_p]} == [\ $'\t\r\n'] ]]; do
        (( ++_p ))
      done
      _quote=${_candidate[_p]}
      if [[ $_quote == '"' || $_quote == "'" ]]; then
        (( ++_p ))
        _vbegin=$_p
        while { (( _p <= _n )) || _zhtml2md_lex_tag_grow; } && [[ ${_candidate[_p]} != "$_quote" ]]; do
          (( ++_p ))
        done
        _value=${_candidate[_vbegin,_p-1]}
        (( ++_p ))
      else
        _vbegin=$_p
        while { (( _p <= _n )) || _zhtml2md_lex_tag_grow; } && [[ ${_candidate[_p]} != [\ $'\t\r\n'\>] ]]; do
          (( ++_p ))
        done
        _value=${_candidate[_vbegin,_p-1]}
      fi
    fi
    if (( ! ${+_zhtml2md_token_attrs[$_name]} )); then
      _zhtml2md_token_attrs[$_name]=$_value
      _zhtml2md_token_attr_names+=( "$_name" )
      _zhtml2md_token_attr_offsets[$_name]=$(( _start + _vbegin - 1 ))
    fi
  done
  if (( _n > _ZHTML2MD_LIMIT_TAG )); then
    _zhtml2md_fail resource-limit $_start 'ordinary tag exceeds 65536 bytes' 4
    return 4
  fi
  return 5
}

# Scan comments/declarations with bounded windows; comments use literal
# '-->', declarations the first unquoted '>'. Body size is input-bound,
# not tag-bound. Writes token kind/end and advances the cursor.
_zhtml2md_lex_skip() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _scan=$_zhtml2md_token_start _i _found=0
  local _win _prefix _c _quote=''
  if [[ $1 == comment ]]; then
    (( _scan += 4 ))
    while (( _scan < _zhtml2md_lex_size )); do
      _win=${_zhtml2md_input[_scan+1,_scan+4096]}
      _prefix=${_win%%'-->'*}
      if (( ${#_prefix} < ${#_win} )); then
        (( _scan += ${#_prefix} + 3, _found=1 ))
        break
      fi
      (( ${#_win} <= 2 )) && break
      (( _scan += ${#_win} - 2 ))
    done
  else
    (( _scan += 2 ))
    while (( _scan < _zhtml2md_lex_size )); do
      _win=${_zhtml2md_input[_scan+1,_scan+4096]}
      # Seek delimiter spans within the bounded window. Each strip is
      # bounded; long declaration bodies are never visited per byte.
      while [[ -n $_win ]]; do
        if [[ -n $_quote ]]; then
          _prefix=${_win%%"$_quote"*}
        else
          _prefix=${_win%%[\'\">]*}
        fi
        (( _scan += ${#_prefix} ))
        if (( ${#_prefix} == ${#_win} )); then
          break
        fi
        (( _i = ${#_prefix} + 1 ))
        _c=${_win[_i]}
        (( ++_scan ))
        _win=${_win[_i+1,-1]}
        if [[ -n $_quote ]]; then
          _quote=''
        elif [[ $_c == '>' ]]; then
          _found=1
          break
        else
          _quote=$_c
        fi
      done
      (( _found )) && break
    done
  fi
  if (( ! _found )); then
    _scan=$_zhtml2md_lex_size
    _zhtml2md_repair "unterminated-$1" $_zhtml2md_token_start 'discarded through EOF' || return $?
  fi
  _zhtml2md_token_kind=$1
  _zhtml2md_token_end=$_scan
  _zhtml2md_lex_pos=$_scan
  return 0
}

# _zhtml2md_lex_next
# Monotonic pull tokenizer; $token_end is exclusive. Retained text is raw
# source bytes in $token_data; discarded script/style/title bodies carry
# offsets only. Decoding happens after discard classification.
# token_literal is set for plaintext and unfinished-tag literal fallback.
# Raw script/style/title/textarea text ends only at its appropriate end
# tag; no shell-word lexer, recursive descent, or dynamic pattern code.
_zhtml2md_lex_next() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  local -i _next _at _st _j _end _base
  local _probe _boundary
  _zhtml2md_token_start=$_zhtml2md_lex_pos
  _zhtml2md_token_end=$_zhtml2md_lex_pos
  _zhtml2md_token_name=''
  _zhtml2md_token_data=''
  _zhtml2md_token_attrs=()
  _zhtml2md_token_attr_names=()
  _zhtml2md_token_attr_offsets=()
  _zhtml2md_token_self=0
  _zhtml2md_token_literal=0
  if (( _zhtml2md_lex_pos >= _zhtml2md_lex_size )); then
    _zhtml2md_token_kind=eof
    return 0
  fi
  while (( _zhtml2md_lex_index <= _zhtml2md_lex_count )); do
    _at=${_zhtml2md_lex_lt[$_zhtml2md_lex_index]}
    (( _at >= _zhtml2md_lex_pos )) && break
    (( ++_zhtml2md_lex_index ))
  done
  _next=$_zhtml2md_lex_size
  if [[ $_zhtml2md_lex_raw == plaintext ]]; then
    _zhtml2md_token_literal=1
  elif [[ -n $_zhtml2md_lex_raw ]]; then
    # Find appropriate raw/text-only end tags. A closing name must be
    # followed by ASCII whitespace, '/', or '>'; names are compared as
    # literal strings, so source punctuation cannot become a pattern.
    for (( _j=_zhtml2md_lex_index; _j <= _zhtml2md_lex_count; ++_j )); do
      _at=${_zhtml2md_lex_lt[$_j]}
      _probe=${(L)_zhtml2md_lex_segments[$((_j+1))][1,1+${#_zhtml2md_lex_raw}]}
      _boundary=${_zhtml2md_lex_segments[$((_j+1))][2+${#_zhtml2md_lex_raw}]}
      if [[ $_probe == "/$_zhtml2md_lex_raw" && $_boundary == [\ $'\t\r\n'/\>] ]]; then
        _zhtml2md_lex_tag $_at $_j
        _st=$?
        (( _st == 4 )) && return 4
        if (( _st == 0 )); then
          _next=$_at
          _zhtml2md_lex_index=$_j
          break
        fi
      fi
    done
    if (( _next == _zhtml2md_lex_pos )); then
      _zhtml2md_lex_pos=$_zhtml2md_token_end
      _zhtml2md_lex_raw=''
      return 0
    fi
    # Failed closing candidates are literal raw body, not incomplete
    # ordinary tags. Clear the candidate's attribute/name fields.
    _zhtml2md_token_name=''
    _zhtml2md_token_attrs=()
    _zhtml2md_token_attr_names=()
    _zhtml2md_token_attr_offsets=()
    _zhtml2md_token_self=0
  elif (( _zhtml2md_lex_index <= _zhtml2md_lex_count )); then
    _next=${_zhtml2md_lex_lt[$_zhtml2md_lex_index]}
  fi
  if (( _next > _zhtml2md_lex_pos )); then
    _zhtml2md_token_kind=text
    _zhtml2md_token_end=$_next
    if [[ -z $_zhtml2md_lex_raw ]]; then
      _base=$_zhtml2md_bom
      (( _zhtml2md_lex_index > 1 )) && (( _base = ${_zhtml2md_lex_lt[$((_zhtml2md_lex_index-1))]} + 1 ))
      _zhtml2md_token_data=${_zhtml2md_lex_segments[$_zhtml2md_lex_index][_zhtml2md_lex_pos-_base+1,_next-_base]}
    elif [[ $_zhtml2md_lex_raw == textarea || $_zhtml2md_lex_raw == plaintext ]]; then
      _zhtml2md_token_data=${_zhtml2md_input[_zhtml2md_lex_pos+1,_next]}
    fi
    _zhtml2md_lex_pos=$_next
    return 0
  fi
  _probe="<${_zhtml2md_lex_segments[$((_zhtml2md_lex_index+1))][1,3]}"
  if [[ $_probe == '<!--' ]]; then
    _zhtml2md_lex_skip comment
    return $?
  elif [[ $_probe == '<!'* || $_probe == '<?'* ]]; then
    _zhtml2md_lex_skip declaration
    return $?
  elif [[ $_probe == '<'[A-Za-z]* || $_probe == '</'[A-Za-z]* ]]; then
    _zhtml2md_lex_tag $_next $_zhtml2md_lex_index
    _st=$?
    (( _st == 4 )) && return 4
    if (( _st == 0 )); then
      _zhtml2md_lex_pos=$_zhtml2md_token_end
      if [[ $_zhtml2md_token_kind == start ]]; then
        case $_zhtml2md_token_name in
          script|style|title|textarea|plaintext) _zhtml2md_lex_raw=$_zhtml2md_token_name ;;
        esac
      fi
      return 0
    fi
    _zhtml2md_repair incomplete-tag $_next 'unfinished tag retained as literal text' || return $?
    _end=$_zhtml2md_lex_size
    _zhtml2md_token_literal=1
  elif [[ $_probe == '<' || $_probe == '</' ]]; then
    _zhtml2md_repair incomplete-tag $_next 'unfinished tag retained as literal text' || return $?
    _end=$_zhtml2md_lex_size
    _zhtml2md_token_literal=1
  else
    # A '<' that does not start plausible markup is ordinary text.
    (( _end = _next + 1 ))
  fi
  _zhtml2md_token_kind=text
  _zhtml2md_token_name=''
  _zhtml2md_token_attrs=()
  _zhtml2md_token_attr_names=()
  _zhtml2md_token_attr_offsets=()
  _zhtml2md_token_self=0
  _zhtml2md_token_end=$_end
  if (( _zhtml2md_token_literal )); then
    _zhtml2md_token_data=${_zhtml2md_input[_next+1,_end]}
  else
    _zhtml2md_token_data='<'
  fi
  _zhtml2md_lex_pos=$_end
  return 0
}

if [[ $_zhtml2md_tokenizer_loadopt == on ]]; then
  'builtin' 'setopt' 'aliases'
fi
'builtin' 'unset' _zhtml2md_tokenizer_loadopt
