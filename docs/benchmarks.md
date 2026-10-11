# Conversion and preservation measurements

The milestone 5 report measures public strict conversion for candidate
1.0.0-rc.1 on Linux, Zsh 5.9.2, AMD Ryzen 9 5950X, with 20 warm runs for
each of seven families at four sizes. These are synthetic inputs and
workstation measurements; they do not predict arbitrary websites or dense
non-ASCII input. Correctness is separately verified on Zsh 5.8 and 5.9.2.

## Corpus and preserved facts

All seeds are authored here, with independently reviewed expected Markdown.
The generator repeats complete units and pads with ASCII spaces to exactly
10,240, 102,400, 1,048,576 and 4,194,304 input bytes. No truncation repair is
timed. Generated variants are reproducible and ignored; seeds, hashes, raw
samples and results are committed. Each worker verifies the first complete
conversion byte-for-byte against the expected output, including final LF,
and requires empty stderr before timing warm calls.

| Family | Required facts in every repeated unit |
| --- | --- |
| prose | Section heading, all 40 sentences, guide label and `./guide` destination, original order |
| short-tags | All 32 item labels and 40 sentences in order; correct spaces at inline boundaries |
| nested | Quote coverage, outer bullet membership, exact prose, child ordered start 9 and Child label |
| code | zsh language hint, all 40 print/comment pairs, tabs, double and trailing spaces, exact line endings |
| tables | Measurements caption, Name/Value headers, Mode cell and all sentences in the Value cell |
| entities | All prose, eight copies of literal ampersand, © and the two-code-point ≂̸ value, final end label |
| discard | Kept paragraph for every unit; script/style fake tags and body remain discarded |

The five [upstream contract pairs](../tests/contracts/README.md) separately
verify ordinary HTML and actual zoup-cleaned HTML, including images,
numbering gaps, spans, Unicode and code whitespace. The full golden suite
also checks complex table fallbacks, destinations and nested relationships;
22 optional independent CommonMark/GFM assertions verify their interpretation.

## Measurement protocol

`bench/worker.zsh` starts a fresh shell, times library loading, then the first
public strict conversion including reading, validation and any lazy entity
initialization. Filesystem caches may already be warm. It verifies output
outside timing, then makes 20 conversions in the same shell with output
redirected to `/dev/null`. Median is the lower middle sorted sample (10th of
20); p95 is nearest rank (19th of 20). Summaries are checked against the
raw decimal-millisecond samples using arithmetic ordering, including values
sharing an integer prefix. The CLI column includes a separate
fresh selected-Zsh process and wrapper/library loading, conversion and exit.
Load timings are retained in the TSVs; their range is summarized below.

GNU time supplies optional peak RSS in KiB. Worker RSS includes verification
buffers and allocator retention across calls; CLI RSS measures a single
conversion process. Neither is a direct measurement of live captured payload.
`zsh/datetime`, GNU time, strace, Python and optional token/Markdown tools are
development tooling only. Timed conversion uses no external executable or
native module. One serial benchmark job ran on the developer workstation;
other development checks and final suites ran on the same host. All inputs
are offline; benchmark drivers and workers perform no network access.

| Family | Input bytes | Output bytes | Warm median ms | p95 ms | First ms | CLI ms | Worker / CLI peak KiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| code | 10240 | 8459 | 11.649 | 11.949 | 12.709 | 21.772 | 5792 / 5116 |
| code | 102400 | 99827 | 128.912 | 133.730 | 134.325 | 138.071 | 7244 / 5504 |
| code | 1048576 | 1027043 | 1319.856 | 1334.805 | 1338.960 | 1333.100 | 21832 / 13640 |
| code | 4194304 | 4113251 | 5282.764 | 5359.667 | 5258.423 | 5289.659 | 71944 / 44664 |
| discard | 10240 | 11 | 4.375 | 4.758 | 5.538 | 15.006 | 3656 / 3360 |
| discard | 102400 | 125 | 40.477 | 43.418 | 46.422 | 51.203 | 5372 / 4632 |
| discard | 1048576 | 1307 | 419.956 | 434.824 | 442.648 | 430.704 | 17636 / 13812 |
| discard | 4194304 | 5249 | 1735.207 | 1750.832 | 1839.657 | 1777.269 | 55356 / 44644 |
| entities | 10240 | 7382 | 7.264 | 8.634 | 164.927 | 159.219 | 4888 / 4632 |
| entities | 102400 | 95978 | 83.826 | 87.517 | 231.828 | 231.513 | 5584 / 5508 |
| entities | 1048576 | 989321 | 872.296 | 883.362 | 1030.230 | 1036.976 | 19016 / 13772 |
| entities | 4194304 | 3964670 | 3549.140 | 3610.315 | 3806.563 | 3674.600 | 63776 / 44528 |
| nested | 10240 | 9531 | 21.074 | 23.953 | 22.682 | 30.403 | 4108 / 3812 |
| nested | 102400 | 100085 | 214.358 | 217.378 | 217.209 | 224.300 | 5680 / 4632 |
| nested | 1048576 | 1024689 | 2225.865 | 2259.954 | 2285.891 | 2264.627 | 21652 / 14004 |
| nested | 4194304 | 4101142 | 9081.164 | 9245.152 | 9111.356 | 9039.453 | 71540 / 44636 |
| prose | 10240 | 9563 | 14.494 | 15.843 | 16.266 | 24.144 | 4152 / 3636 |
| prose | 102400 | 100421 | 148.422 | 149.935 | 158.773 | 163.505 | 5548 / 4936 |
| prose | 1048576 | 1037693 | 1565.954 | 1580.932 | 1636.926 | 1543.576 | 21276 / 13560 |
| prose | 4194304 | 4157948 | 6202.800 | 6246.759 | 6260.571 | 6349.507 | 73212 / 44736 |
| short-tags | 10240 | 7577 | 78.131 | 80.229 | 82.372 | 87.046 | 4072 / 3792 |
| short-tags | 102400 | 85883 | 902.122 | 927.400 | 930.588 | 923.155 | 7148 / 5476 |
| short-tags | 1048576 | 896729 | 9706.881 | 9860.807 | 9632.641 | 9918.328 | 31692 / 23348 |
| short-tags | 4194304 | 3594497 | 40346.123 | 40840.071 | 40678.989 | 40665.524 | 112304 / 80868 |
| tables | 10240 | 9667 | 32.522 | 35.137 | 34.011 | 41.069 | 3856 / 3152 |
| tables | 102400 | 99096 | 327.010 | 330.280 | 335.103 | 338.348 | 5696 / 4936 |
| tables | 1048576 | 1024807 | 3337.209 | 3398.636 | 3517.802 | 3460.356 | 22112 / 13616 |
| tables | 4194304 | 4099231 | 13594.137 | 13693.489 | 13608.329 | 13835.877 | 77108 / 44232 |

Cold library loading ranged from **5.024 to 10.143 ms**. Entity-heavy first calls include the one-time validated entity table; warm calls reuse its immutable cache. Worker and CLI RSS are reported separately above.


## Scaling and measured optimization

The initial 4 MiB code measurement exposed a full-input byte subscript in the
pre-leading-newline check. An instrumented profile attributed 67.56% of self
time to `_zhtml2md_render_event`: 16.412 seconds total in that single run.
Using the tokenizer's existing source segments for that byte reduced the
profile to 5.406 seconds; the renderer's self share became 4.91%. All code
sizes were then remeasured with 20 warm runs. The profiles are diagnostic
evidence, not substitutes for the distributions in the results table.
New exact-byte tests cover quoted `<` attributes, Unicode, growing tag
windows, CRLF, child-code LF and EOF. Both complete offline suites pass
after the change.

Earlier measured lexer improvements remain in place: geometrically grown
tag candidates and associative source-segment lookup. A dense-markup profile
is also retained. No output semantics or runtime dependencies changed to
meet the performance targets.

Typical prose meets the initial median targets: **148.422 ms at
100 KiB** (≤1 second) and **1565.954 ms at 1 MiB** (≤10 seconds).
Every family stays below 15× warm runtime in the two approximately 10× size
steps. The 4× limit step is reported separately; these are observations,
not a proof of complexity or a guarantee for all accepted HTML.

| Family | 10 KiB → 100 KiB (10× input) | 100 KiB → 1 MiB (10.24×) | 1 MiB → 4 MiB (4×) |
| --- | ---: | ---: | ---: |
| prose | 10.24× | 10.55× | 3.96× |
| short-tags | 11.55× | 10.76× | 4.16× |
| nested | 10.17× | 10.38× | 4.08× |
| code | 11.07× | 10.24× | 4.00× |
| tables | 10.06× | 10.21× | 4.07× |
| entities | 11.54× | 10.41× | 4.07× |
| discard | 9.25× | 10.38× | 4.13× |

At 4 MiB, the measured warm medians range from **1.74 to 40.35
seconds**, with CLI peak RSS from **43.2 to 79.0 MiB**. Many
short tags are the slowest family. v1 supports the documented 4 MiB bound;
it makes no fixed latency promise at that bound. Dense Unicode input and
more unusual structures require separate measurement before making claims.

The process target is explicitly clarified: loading performs no external
executable work, but module-free alias-state snapshots create eight
builtin-only children (nine via CLI). Conversion creates no children and
requires no native module. Process audits verify both shells. Fixed
persistent parameters and descriptors are checked over 100 consecutive
complete conversions. This is the recorded change to the original
zero-process-at-load target; timing includes the snapshot cost.


## Optional token measurements

Token counts use **tiktoken 0.11.0 / cl100k_base**, outside all timed shell
measurements. They describe that encoding only; byte reduction is a separate
representation metric. Token data is recorded for all 28 corpus cases and
five source/clean/Markdown contract pairs. zoup's removed image destinations
and language hints cannot be credited to the converter or recovered by it.
Complex Markdown fallbacks may grow to preserve relationships.

| Contract | Source bytes | Cleaned bytes | Markdown bytes | Source tokens | Cleaned tokens | Markdown tokens | Conversion token change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| article | 166 | 98 | 57 | 50 | 32 | 15 | -53.1% |
| boundaries | 126 | 129 | 33 | 46 | 47 | 15 | -68.1% |
| code | 97 | 76 | 41 | 34 | 29 | 17 | -41.4% |
| lists | 130 | 123 | 46 | 48 | 45 | 19 | -57.8% |
| tables | 157 | 144 | 137 | 52 | 49 | 54 | +10.2% |

The span-bearing table contract grows from 49 to 54 tokens (**+10.2%**) while
bytes fall from 144 to 137. Its explicit fallback retains cell/span facts;
size reduction is not an acceptance requirement. Positive percentages mean
growth. The other contract cases reduce tokens, with upstream cleanup
counted separately.

| 1 MiB corpus family | HTML tokens | Markdown tokens | Conversion token change |
| --- | ---: | ---: | ---: |
| code | 348431 | 343562 | -1.4% |
| discard | 180316 | 654 | -99.6% |
| entities | 201825 | 184116 | -8.8% |
| nested | 183190 | 176730 | -3.5% |
| prose | 183166 | 177506 | -3.1% |
| short-tags | 212309 | 154070 | -27.4% |
| tables | 186564 | 176808 | -5.2% |

## Artifacts and reproduction

The [environment](../bench/results/2026-10-11-environment.json),
[hashed manifest](../bench/results/2026-10-11-manifest.json),
[raw warm samples](../bench/results/2026-10-11-samples.tsv),
[small](../bench/results/2026-10-11-small.tsv) and
[large](../bench/results/2026-10-11-large.tsv) timing data and
[token counts](../bench/results/2026-10-11-tokens.json) contain exact values.
The code optimization's before/after distributions and profiles are retained
in the same results directory.

```zsh
zsh -df bench/gen-corpus.zsh
ZHTML2MD_BENCH_SAMPLES=/tmp/warm-samples.tsv \
  zsh -df bench/run.zsh 20 bench/generated/*-10240.html > /tmp/small.tsv
ZHTML2MD_BENCH_SAMPLES=/tmp/warm-samples.tsv \
  zsh -df bench/run.zsh 20 bench/generated/*-102400.html \
    bench/generated/*-1048576.html bench/generated/*-4194304.html > /tmp/large.tsv
```

Copy the two timing TSVs and warm-samples.tsv to the matching dated paths
consumed by bench/report.py, then run it with optional tiktoken installed to
regenerate hashes, environment, tables and counts. The report verifies its
summaries against those raw samples. Do not
overwrite the historical report with a different environment without updating
its date and narrative. The default `bench/run.zsh 20` runs the same 28 cases
and can take over 30 minutes. No zoup installation is needed.

The profiles can be reproduced with development-only `zmodload zsh/zprof`,
sourcing the library, converting the indicated input, then calling `zprof`.

## Historical parser-only probe, 2026-10-10

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

These historical results exclude loading, reading, UTF-8 validation, first
entity initialization and all Markdown rendering/capture costs. The family
differs from the full-conversion prose family above and cannot be compared
directly. Its three-run 1 MiB observation is exploratory; the complete report
above supplies 20-run public-conversion measurements at every size instead.
The historical driver used integer-prefix sorting, so fractional ties could
alter its reported median/p95 within a millisecond; those raw samples were
not retained. Current drivers use arithmetic ordering, and the full report
checks every summary against its saved samples. Historical aggregates are
not used for candidate acceptance.
