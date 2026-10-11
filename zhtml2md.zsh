# SPDX-License-Identifier: Apache-2.0
# zhtml2md.zsh - sourceable entry point for the zhtml2md library.
#
# Loads the implementation modules, defines the public `zhtml2md`
# function, and exports immutable installation metadata. Produces no
# load-time output and preserves the caller's shell state.
#
# Parse-time protection: the command words of the guard lines are quoted
# so preexisting caller aliases cannot rewrite them; NO_ALIASES then
# protects the remainder of this parse. ALIASES is restored manually at
# the end of the file because LOCAL_OPTIONS has no enclosing function
# scope to restore into when this file is sourced at top level.


'builtin' 'typeset' _zhtml2md_loadopt_aliases="$( 'builtin' 'set' '+o' )"
'builtin' 'setopt' 'noaliases'
if [[ $'\n'$_zhtml2md_loadopt_aliases$'\n' == *$'\nset +o noaliases\n'* ||
      $'\n'$_zhtml2md_loadopt_aliases$'\n' == *$'\nset -o aliases\n'* ]]; then
  _zhtml2md_loadopt_aliases=on
else
  _zhtml2md_loadopt_aliases=off
fi

# Absolute directory containing this file, resolved at load time so
# sibling code and data are located relative to the library, never the
# caller's working directory. Safe to recompute on repeated sourcing.
'builtin' 'typeset' -g _ZHTML2MD_DIR=${${${(%):-%N}:A}:h}

# Versioned constants (milestone 0 deliverable). Guarded so repeated
# sourcing does not attempt to reassign read-only parameters.
if (( ! ${+_ZHTML2MD_VERSION} )); then
  'builtin' 'typeset' -gr  _ZHTML2MD_VERSION='1.0.0-rc.1'
  'builtin' 'typeset' -gir _ZHTML2MD_LIMIT_INPUT=4194304    # 4 MiB
  'builtin' 'typeset' -gir _ZHTML2MD_LIMIT_TAG=65536        # 64 KiB
  'builtin' 'typeset' -gir _ZHTML2MD_LIMIT_DEPTH=256
  'builtin' 'typeset' -gir _ZHTML2MD_LIMIT_OUTPUT=16777216  # 16 MiB
  'builtin' 'typeset' -gir _ZHTML2MD_LIMIT_CAPTURE=16777216 # 16 MiB
  'builtin' 'typeset' -gir _ZHTML2MD_WARN_CAP=20
  # Documented status codes.
  'builtin' 'typeset' -gir _ZHTML2MD_ST_OK=0
  'builtin' 'typeset' -gir _ZHTML2MD_ST_INTERNAL=1
  'builtin' 'typeset' -gir _ZHTML2MD_ST_USAGE=2
  'builtin' 'typeset' -gir _ZHTML2MD_ST_INPUT=3
  'builtin' 'typeset' -gir _ZHTML2MD_ST_LIMIT=4
fi

# Load implementation modules. Any load failure is an initialization
# error and must not leave the library marked ready.
{
  'builtin' 'source' -- "$_ZHTML2MD_DIR/lib/_zhtml2md_input.zsh"  &&
  'builtin' 'source' -- "$_ZHTML2MD_DIR/lib/_zhtml2md_render.zsh" &&
  'builtin' 'source' -- "$_ZHTML2MD_DIR/lib/_zhtml2md_markdown.zsh" &&
  'builtin' 'source' -- "$_ZHTML2MD_DIR/lib/_zhtml2md_structures.zsh" &&
  'builtin' 'source' -- "$_ZHTML2MD_DIR/lib/_zhtml2md_entities.zsh" &&
  'builtin' 'source' -- "$_ZHTML2MD_DIR/lib/_zhtml2md_tokenizer.zsh" &&
  'builtin' 'source' -- "$_ZHTML2MD_DIR/lib/_zhtml2md_frames.zsh"
} || {
  'builtin' 'print' -r -u 2 -- \
    "zhtml2md: initialization: cannot load library modules from $_ZHTML2MD_DIR/lib"
  if [[ $_zhtml2md_loadopt_aliases == on ]]; then
    'builtin' 'setopt' 'aliases'
  fi
  'builtin' 'unset' _zhtml2md_loadopt_aliases
  'builtin' 'return' 1 2>/dev/null || 'builtin' 'exit' 1
}

# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

# usage: zhtml2md [--strict] [--] [FILE|-]
#        zhtml2md --help
#        zhtml2md --version
#
# Converts UTF-8 HTML on FILE (or stdin) to Markdown on stdout.
# Status: 0 ok, 1 io/internal, 2 usage, 3 input rejected, 4 limit.
#
# Dynamic-scope context shared with helpers (declared here, documented
# per helper):
#   _zhtml2md_strict        1 when --strict was given
#   _zhtml2md_in_path       selected input path, '' or '-' for stdin
#   _zhtml2md_input         raw input bytes including any initial BOM
#   _zhtml2md_bom           3 when an initial UTF-8 BOM is present, else 0
#   _zhtml2md_output        buffered Markdown awaiting final emission
#   _zhtml2md_diag_emitted  count of printed diagnostics
#   _zhtml2md_diag_total    count of all diagnostics (including suppressed)
#   _zhtml2md_diag_capped   1 once the warning cap suppressed output
zhtml2md() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C

  local _zhtml2md_strict=0
  local _zhtml2md_in_path=''
  local _zhtml2md_input=''
  local -i _zhtml2md_bom=0
  local _zhtml2md_output=''
  local -i _zhtml2md_diag_emitted=0 _zhtml2md_diag_total=0 _zhtml2md_diag_capped=0

  # ---- argument validation -------------------------------------------
  local -a _zhtml2md_operands=()
  local -i _zhtml2md_want_help=0 _zhtml2md_want_version=0
  local -i _zhtml2md_seen_strict=0 _zhtml2md_seen_help=0 _zhtml2md_seen_version=0
  local _zhtml2md_arg
  while (( $# > 0 )); do
    _zhtml2md_arg=$1
    case $_zhtml2md_arg in
      --strict)
        (( _zhtml2md_seen_strict )) && { _zhtml2md_usage 'duplicate option: --strict'; return 2 }
        _zhtml2md_seen_strict=1; _zhtml2md_strict=1 ;;
      --help)
        (( _zhtml2md_seen_help )) && { _zhtml2md_usage 'duplicate option: --help'; return 2 }
        _zhtml2md_seen_help=1; _zhtml2md_want_help=1 ;;
      --version)
        (( _zhtml2md_seen_version )) && { _zhtml2md_usage 'duplicate option: --version'; return 2 }
        _zhtml2md_seen_version=1; _zhtml2md_want_version=1 ;;
      --)
        shift
        _zhtml2md_operands+=( "$@" )
        break ;;
      --*)
        _zhtml2md_usage "unknown option: $_zhtml2md_arg"; return 2 ;;
      -?*)
        _zhtml2md_usage "unknown option: $_zhtml2md_arg"; return 2 ;;
      *)
        _zhtml2md_operands+=( "$_zhtml2md_arg" ) ;;
    esac
    shift
  done

  if (( _zhtml2md_want_help || _zhtml2md_want_version )); then
    if (( _zhtml2md_want_help && _zhtml2md_want_version )); then
      _zhtml2md_usage '--help and --version cannot be combined'
      return 2
    fi
    if (( ${#_zhtml2md_operands} > 0 || _zhtml2md_seen_strict )); then
      _zhtml2md_usage '--help/--version cannot be combined with conversion arguments'
      return 2
    fi
    if (( _zhtml2md_want_help )); then
      _zhtml2md_print_help
    else
      builtin print -r -- "zhtml2md $_ZHTML2MD_VERSION"
    fi
    return 0
  fi

  if (( ${#_zhtml2md_operands} > 1 )); then
    _zhtml2md_usage 'at most one input file may be given'
    return 2
  fi
  (( ${#_zhtml2md_operands} == 1 )) && _zhtml2md_in_path=${_zhtml2md_operands[1]}

  # ---- conversion pipeline ---------------------------------------------
  local -i _zhtml2md_st

  _zhtml2md_read_all
  _zhtml2md_st=$?
  (( _zhtml2md_st == 0 )) || { _zhtml2md_diag_finish; return $_zhtml2md_st }

  _zhtml2md_validate_encoding
  _zhtml2md_st=$?
  (( _zhtml2md_st == 0 )) || return $_zhtml2md_st

  _zhtml2md_render
  _zhtml2md_st=$?
  (( _zhtml2md_st == 0 )) || { _zhtml2md_diag_finish; return $_zhtml2md_st }

  _zhtml2md_diag_finish
  _zhtml2md_emit
}

# Print the short usage error plus the usage synopsis; status 2 is the
# caller-visible result, emitted by the caller of this helper.
_zhtml2md_usage() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  builtin print -r -u 2 -- "zhtml2md: usage: $1"
  builtin print -r -u 2 -- 'usage: zhtml2md [--strict] [--] [FILE|-]'
  builtin print -r -u 2 -- '       zhtml2md --help'
  builtin print -r -u 2 -- '       zhtml2md --version'
}

_zhtml2md_print_help() {
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  builtin print -r -- 'usage: zhtml2md [--strict] [--] [FILE|-]'
  builtin print -r -- '       zhtml2md --help'
  builtin print -r -- '       zhtml2md --version'
  builtin print -r -- ''
  builtin print -r -- 'Convert UTF-8 HTML to compact, deterministic Markdown.'
  builtin print -r -- 'With no operand, or -, read standard input.'
  builtin print -r -- ''
  builtin print -r -- 'Options:'
  builtin print -r -- '  --strict   fail on recoverable syntax defects instead of repairing'
  builtin print -r -- '  --         end option parsing (allow paths beginning with -)'
  builtin print -r -- '  --help     print this text and exit'
  builtin print -r -- '  --version  print the version and exit'
  builtin print -r -- ''
  builtin print -r -- 'Status: 0 ok, 1 io/internal, 2 usage, 3 input rejected, 4 limit exceeded'
}

# Restore the caller's ALIASES setting (see the guard at the top).
if [[ $_zhtml2md_loadopt_aliases == on ]]; then
  'builtin' 'setopt' 'aliases'
fi
'builtin' 'unset' _zhtml2md_loadopt_aliases
