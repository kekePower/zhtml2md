#!/usr/bin/env python3
"""Summarize committed benchmark TSVs; optional tiktoken token metrics."""
import csv
import hashlib
import json
import platform
from pathlib import Path
from importlib.metadata import version

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'bench/results'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    rows = []
    for name in ['2026-10-11-small.tsv','2026-10-11-large.tsv']:
        with (OUT / name).open() as source:
            rows.extend(csv.DictReader(source,delimiter='\t'))
    assert len(rows) == 28 and len({r['case'] for r in rows}) == 28
    with (OUT / '2026-10-11-samples.tsv').open() as source:
        samples = {r['case']: [float(v) for k,v in r.items() if k != 'case']
                   for r in csv.DictReader(source,delimiter='\t')}
    assert set(samples) == {r['case'] for r in rows}
    manifest = []
    for row in rows:
        path = ROOT / 'bench/generated' / row['case']
        expected = path.with_suffix('.md')
        assert path.stat().st_size == int(row['input_bytes'])
        assert expected.stat().st_size == int(row['output_bytes'])
        assert int(row['runs']) >= 20
        ordered = sorted(samples[row['case']])
        runs = int(row['runs'])
        assert len(ordered) == runs and all(v > 0 for v in ordered)
        assert abs(ordered[(runs+1)//2-1] - float(row['warm_median_ms'])) < 0.00051
        assert abs(ordered[(95*runs+99)//100-1] - float(row['warm_p95_ms'])) < 0.00051
        manifest.append({'case':path.name,'input_sha256':digest(path),'output_sha256':digest(expected),**row})
    (OUT / '2026-10-11-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    cpu = next((line.split(':',1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')), 'unknown')
    environment = {'os':platform.platform(),'cpu':cpu,'architecture':platform.machine(),'python':platform.python_version(),
        'clock':'zsh/datetime EPOCHREALTIME (development only)','rss':'GNU time maximum resident set size in KiB',
        'converter':'1.0.0-rc.1','zsh':rows[0]['zsh'],'warm_runs_per_case':20,
        'cold_semantics':'fresh process/entity cache; filesystem cache may be warm',
        'measurement_revision':'code cases remeasured after source-index pre-newline optimization; other families do not enter the changed branch',
        'contention':'developer workstation; one serial benchmark job; other development checks and final test suites ran on the same host'}
    (OUT / '2026-10-11-environment.json').write_text(json.dumps(environment,indent=2)+'\n')
    table = ['| Family | Input bytes | Output bytes | Warm median ms | p95 ms | First ms | CLI ms | Worker / CLI peak KiB |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for row in sorted(rows,key=lambda r:(r['case'].rsplit('-',1)[0],int(r['input_bytes']))):
        family = row['case'].rsplit('-',1)[0]
        table.append(f"| {family} | {row['input_bytes']} | {row['output_bytes']} | {row['warm_median_ms']} | {row['warm_p95_ms']} | {row['first_ms']} | {row['cli_ms']} | {row['worker_peak_kib']} / {row['cli_peak_kib']} |")
    (OUT / '2026-10-11-table.md').write_text('\n'.join(table)+'\n')
    # Encoding is pre-warmed in development setup. Report generation alone
    # uses this optional tokenizer; timed shell measurements never import it.
    try:
        import tiktoken
    except ImportError:
        print('benchmark table/manifest written; tokens skipped (no tiktoken)')
        return
    encoding = tiktoken.get_encoding('cl100k_base')
    tokens = {'tokenizer':f'tiktoken {version("tiktoken")} / cl100k_base','contracts':[],'corpus':[]}
    def count(path): return len(encoding.encode(path.read_bytes().decode('utf-8'),disallowed_special=()))
    for source in sorted((ROOT/'tests/contracts').glob('*.source.html')):
        name = source.name.removesuffix('.source.html')
        cleaned = source.with_name(name+'.clean.html')
        markdown = source.with_name(name+'.md')
        tokens['contracts'].append({'case':name,'source_bytes':source.stat().st_size,'cleaned_bytes':cleaned.stat().st_size,'markdown_bytes':markdown.stat().st_size,
            'source_tokens':count(source),'cleaned_tokens':count(cleaned),'markdown_tokens':count(markdown)})
    for row in rows:
        source=ROOT/'bench/generated'/row['case']
        tokens['corpus'].append({'case':source.name,'html_tokens':count(source),'markdown_tokens':count(source.with_suffix('.md'))})
    (OUT/'2026-10-11-tokens.json').write_text(json.dumps(tokens,indent=2)+'\n')
    print('benchmark table, environment, hashes and optional token counts written')


if __name__ == '__main__':
    main()
