# Development measurements

The complete milestone 5 conversion/preservation report is still pending.
These measurements cover milestone 2's parser only, before milestone 3's
public Markdown integration. No token-reduction or complete
conversion throughput claim is made.

## Parser-only probe, 2026-10-10

Host: AMD Ryzen 9 5950X, Linux
6.18.44-1.mga10custom-spurven-zen3, x86_64. Zsh 5.9.2. All parsing uses
native code/builtins; the development driver alone loads `zsh/datetime`
to read a timer.

The committed synthetic `bench/corpus/prose-*.html` family repeats prose,
headings, links, emphasis and entity references. Sizes are exact; truncation
can leave an open final frame, so the probe uses tolerant mode. Recovery
work is timed, with stderr suppressed. The fixed event sink returns
success without rendering or capturing Markdown.

`bench/parser.zsh` loads once, reads/validates each input outside timing,
warms the parser and entity cache, then times repeated parsing in the same
shell. Median is the lower middle sorted sample; p95 uses the nearest
rank. Runs below 20 are exploratory, and their tail estimate is weak.

| Input | Bytes | Warm runs | Median (ms) | p95 (ms) |
| --- | ---: | ---: | ---: | ---: |
| prose-10240.html | 10,240 | 20 | 98.541 | 102.072 |
| prose-102400.html | 102,400 | 20 | 969.776 | 1,019.566 |
| prose-1048576.html | 1,048,576 | 3, exploratory | 9,975.538 | 9,983.899 |

Reproduce the recorded samples from the checkout:

```zsh
zsh -df bench/parser.zsh 20 bench/corpus/prose-10240.html bench/corpus/prose-102400.html
zsh -df bench/parser.zsh 3 bench/corpus/prose-1048576.html
```

For the full default parser probe, including 20 runs at 1 MiB:

```zsh
zsh -df bench/parser.zsh
```

Early profiling identified two avoidable lexer costs: repeatedly copying
a 64 KiB candidate for short tags, and growing indexed-array lookup costs.
The implementation now grows candidates geometrically from 256 bytes and
stores `<` segments/offsets in associations with generated integer-string
keys. Stack arrays stay bounded to 256 active slots. Reviewed fixtures and
boundary tests passed after these changes.

These results exclude loading, reading, UTF-8 validation, first entity
initialization and all Markdown rendering/capture costs. Peak memory,
broader corpus families, preservation evidence, and complete-conversion
median/p95 measurements remain milestone 5 work. Parser timings alone
cannot establish the plan's conversion performance targets, and the 1 MiB
sample must be expanded before using it for a stable regression threshold.
