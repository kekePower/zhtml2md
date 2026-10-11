#!/usr/bin/env zsh
# Component fixtures, authored from the character-reference contract.
# These test decoded bytes before Markdown escaping/whitespace handling.
'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r dir=${${${(%):-%N}:A:h}:h}/tests/entities
command mkdir -p -- "$dir" || exit 1
local -i written=0

_ze_write() { # name input expected status offset stderr
  emulate -L zsh -o no_multibyte
  local LC_ALL=C
  builtin printf '%s' "$2" > "$dir/$1.input"
  builtin printf '%s' "$3" > "$dir/$1.decoded"
  builtin printf '%s\n' "${4:-0}" > "$dir/$1.status"
  builtin printf '%s\n' "${5:-0}" > "$dir/$1.offset"
  builtin printf '%s' "$6" > "$dir/$1.stderr"
  (( ++written ))
}

_ze_write empty '' ''
_ze_write literal $'a\t caf\xc3\xa9 \xf0\x9f\x98\x80\n' $'a\t caf\xc3\xa9 \xf0\x9f\x98\x80\n'
_ze_write punctuation '&amp;&lt;&gt;&quot;&apos;&bsol;' '&<>"'"'"'\'
_ze_write unicode '&nbsp;&copy;&eacute;&Afr;&NotEqualTilde;&fjlig;' \
  $'\xc2\xa0\xc2\xa9\xc3\xa9\xf0\x9d\x94\x84\xe2\x89\x82\xcc\xb8fj'
_ze_write case-sensitive '&AMP;&amp;&Amp;&aMp;&LT;&lt;' '&&&Amp;&aMp;<<'
_ze_write semicolons '&amp &lt &#65 &#x41 &amp=1' '&amp &lt &#65 &#x41 &amp=1'
_ze_write unknown '&unknown;&AMP0;&;&&amp;&&&' '&unknown;&AMP0;&;&&&&&'
_ze_write one-pass '&amp;lt; &amp;#65; &amp;amp; &#38;lt;' '&lt; &#65; &amp; &lt;'
_ze_write numeric '&#65;&#x41;&#X41;&#00065;&#x000041;' 'AAAAA'
_ze_write utf8-boundaries '&#x7E;&#x80;&#x7FF;&#x800;&#xD7FF;&#xE000;&#xFFFF;&#x10000;&#x10FFFF;' \
  $'~\xe2\x82\xac\xdf\xbf\xe0\xa0\x80\xed\x9f\xbf\xee\x80\x80\xef\xbf\xbf\xf0\x90\x80\x80\xf4\x8f\xbf\xbf'
_ze_write replacements '&#0;&#x0;&#55296;&#xDFFF;&#1114112;&#x110000;&#99999999999999999999999;' \
  $'\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd'
_ze_write allowed-whitespace 'a&Tab;b&NewLine;c&#9;d&#10;e&#13;f' $'a\tb\nc\td\ne\rf'
_ze_write c1 '&#128;&#129;&#130;&#131;&#132;&#133;&#134;&#135;&#136;&#137;&#138;&#139;&#140;&#141;&#142;&#143;&#144;&#145;&#146;&#147;&#148;&#149;&#150;&#151;&#152;&#153;&#154;&#155;&#156;&#157;&#158;&#159;' \
  $'\xe2\x82\xac\xc2\x81\xe2\x80\x9a\xc6\x92\xe2\x80\x9e\xe2\x80\xa6\xe2\x80\xa0\xe2\x80\xa1\xcb\x86\xe2\x80\xb0\xc5\xa0\xe2\x80\xb9\xc5\x92\xc2\x8d\xc5\xbd\xc2\x8f\xc2\x90\xe2\x80\x98\xe2\x80\x99\xe2\x80\x9c\xe2\x80\x9d\xe2\x80\xa2\xe2\x80\x93\xe2\x80\x94\xcb\x9c\xe2\x84\xa2\xc5\xa1\xe2\x80\xba\xc5\x93\xc2\x9d\xc5\xbe\xc5\xb8'
_ze_write inert '&#1+2; &#x$(touch marker); &#-1; &#x0x41; &#x41G; &#; &#x; &#65 ; &a[1]; `print bad` ${x} $(print bad)' \
  '&#1+2; &#x$(touch marker); &#-1; &#x0x41; &#x41G; &#; &#x; &#65 ; &a[1]; `print bad` ${x} $(print bad)'
_ze_write control 'a&#1;z' '' 3 0 \
  $'zhtml2md: forbidden-control at byte 1: forbidden control from character reference\n'
_ze_write control-after-reference 'a&amp;b&#x7F;z' '' 3 3 \
  $'zhtml2md: forbidden-control at byte 10: forbidden control from character reference\n'
_ze_write control-unicode-offset $'\xc3\xa9&unknown;\r\n&#12;' '' 3 3 \
  $'zhtml2md: forbidden-control at byte 16: forbidden control from character reference\n'
_ze_write trailing-lf '&NewLine;&NewLine;' $'\n\n'
_ze_write numeric-noncharacters '&#xFFFE;&#xFDD0;' $'\xef\xbf\xbe\xef\xb7\x90'
_ze_write long-name '&CounterClockwiseContourIntegral;&CounterClockwiseContourIntegralX;' \
  $'\xe2\x88\xb3&CounterClockwiseContourIntegralX;'
builtin print -r -- "wrote $written entity component fixtures"
