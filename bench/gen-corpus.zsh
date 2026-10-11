#!/usr/bin/env zsh
# Synthetic seeds are authored here with independent Markdown expectations.
# Generated size variants are reproducible artifacts, not runtime inputs.
'builtin' 'setopt' 'noaliases'
emulate -L zsh -o no_multibyte
local LC_ALL=C
local -r root=${${${(%):-%N}:A:h}:h}
local -r dir=$root/bench/generated
command mkdir -p -- "$dir" "$root/bench/seeds" || exit 1
local prose='' code='' tags='' refs='' table_html table_md
local -i i target count need
for (( i=0; i<40; ++i )); do prose+='Native shell tools preserve text and structure for agents. '; done
for (( i=0; i<40; ++i )); do code+=$'print -r -- "hello"\n\t# keep  two spaces  \n'; done
for (( i=0; i<32; ++i )); do tags+='<span>item </span>'; done
for (( i=0; i<8; ++i )); do refs+='&amp; &copy; &NotEqualTilde; '; done
local -A html md
html[prose]="<h2>Section</h2><p>$prose"'<a href="./guide">guide</a>.</p>'
md[prose]=$'## Section\n\n'"$prose"$'[guide](./guide).\n'
html[short-tags]="<p>$tags$prose"'done</p>'
md[short-tags]=''
for (( i=0; i<32; ++i )); do md[short-tags]+='item '; done
md[short-tags]+="$prose"$'done\n'
html[nested]="<blockquote><ul><li>$prose"'<ol start="9"><li>Child</li></ol></li></ul></blockquote>'
md[nested]='> - '${prose% }$'\n>   \n>   9. Child\n'
html[code]='<pre><code class="language-zsh">'"$code"'</code></pre>'
md[code]=$'```zsh\n'"$code"$'```\n'
html[tables]='<table><caption>Measurements</caption><tr><th>Name</th><th>Value</th></tr><tr><td>Mode</td><td>'"${prose% }"'</td></tr></table>'
md[tables]=$'Measurements\n\n| Name | Value |\n| --- | --- |\n| Mode | '"${prose% }"$' |\n'
html[entities]="<p>$prose$refs"'end</p>'
md[entities]="$prose"
for (( i=0; i<8; ++i )); do md[entities]+=$'\\& © ≂̸ '; done
md[entities]+=$'end\n'
html[discard]='<script>'"$prose"' <fake attr=">">ignored</fake></script><style>'"$prose"'</style><p>Kept</p>'
md[discard]=$'Kept\n'
local family seed expected out exp padding
builtin print -r -- 'family nominal_bytes repeats input_bytes output_bytes'
for family in prose short-tags nested code tables entities discard; do
  seed=$html[$family] expected=$md[$family]
  builtin printf '%s' "$seed" > "$root/bench/seeds/$family.html"
  builtin printf '%s' "$expected" > "$root/bench/seeds/$family.md"
  for target in 10240 102400 1048576 4194304; do
    count=$(( target / ${#seed} ))
    out='' exp=''
    for (( i=0; i<count; ++i )); do
      out+=$seed
      (( i )) && exp+=$'\n'
      exp+=$expected
    done
    need=$(( target - ${#out} ))
    builtin printf -v padding '%*s' $need ''
    out+=$padding
    builtin printf '%s' "$out" > "$dir/$family-$target.html"
    builtin printf '%s' "$exp" > "$dir/$family-$target.md"
    builtin print -r -- "$family $target $count ${#out} ${#exp}"
  done
done
