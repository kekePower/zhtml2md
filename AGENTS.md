# Project essentials

**`zhtml2md` is a pure Zsh project.** It converts UTF-8 HTML into compact, deterministic Markdown for AI agents. The deliverable is a sourceable Zsh library with a small CLI wrapper around the same converter.

- **Use native Zsh 5.8+ semantics.** Linux is the initial supported platform. Bash/POSIX-shell compatibility is not a goal.
- **Keep the runtime 100% pure Zsh.** Loading, input handling, parsing, rendering, and static-data loading must use Zsh code and builtins. No external commands, parsers, codecs, compiled helpers, or required `zmodload` modules. External development tools are allowed; they must not become runtime dependencies.
- **Preserve meaning before minimizing size.** Keep text order, headings, lists, links and destinations, image descriptions, code whitespace, and table data. Token savings must be measured, not assumed from byte counts.
- **Respect the boundary with `zoup`.** `zoup` selects and cleans content; `zhtml2md` converts the retained semantic HTML. The converter must also work independently for its documented HTML subset. Fetching, article extraction, CSS analysis, and JavaScript execution are outside this project's scope.
- **Follow the implementation contract.** Read [docs/implementation-plan.md](docs/implementation-plan.md) before implementing or changing behavior. It defines the API, supported HTML, recovery rules, limits, milestones, and completion criteria. Update the plan and fixtures when changing that contract.

## Implementation rules

- Use a stateful tokenizer and iterative semantic stack. Simple tag stripping or a sequence of global substitutions is insufficient for quoted attributes, nesting, raw text, and code.
- Preserve the caller's shell environment. Localize options and locale, protect loading from parse-time aliases, namespace helpers/state, and clean up owned descriptors. Repeated sourcing and repeated conversions must be safe.
- Treat HTML and attributes as literal data. Never evaluate them as shell code, patterns, variable names, or unchecked arithmetic. Vendored entity data must be parsed as data, not sourced as code.
- Keep stdout for Markdown and stderr for bounded diagnostics. Buffer conversion output until parsing/rendering succeeds; use the plan's documented status codes and resource limits.
- Generate Markdown using context-specific escaping and documented fallbacks. Do not embed raw HTML as a fallback or silently discard supported content to simplify rendering.

## Verification

- Parse changed Zsh files with `zsh -f -n` and run relevant tests under `zsh -df`.
- Verify exact Markdown bytes, strict/tolerant recovery, Unicode, code whitespace, nesting, and resource boundaries with reviewed fixtures.
- Test loading and calls under adverse caller options and preexisting aliases; check shell-state preservation and descriptor cleanup on success and failure.
- Verify runtime loading/conversion with external commands unavailable on `PATH`, and inspect for absolute-path or otherwise hidden external execution.
- Benchmark representative inputs before making performance or token-reduction claims. Keep `zoup` integration optional for standalone tests.

# Bit Lantern (bitlantern mcp server)

## Code navigation

When Bit Lantern MCP tools are available, **always** use them as the primary navigation path for repository
investigations that need the correct file, source range, or structural relationship. This includes
definitions, named symbols, unknown locations, callers, references, dependency paths, architecture,
and edit impact.

- If the file and range are already known, read that range directly.
- If a file is known but the relevant range is not, use `symbol_outline` before reading the file.
- If the location is unknown, use `symbol_search`, then `symbol_resolve` when exact metadata is
  needed.
- Use `symbol_references`, `symbol_graph`, `symbol_trace`, `symbol_path`, or `edit_impact` for the
  corresponding structural question.
- Read the exact source ranges returned by Bit Lantern before drawing conclusions or editing.
- Use `rg` or other raw-text search for literals, regexes, unmodeled text, unsupported/partial
  language coverage, an explicit user request, or after focused Bit Lantern queries miss.

Do not use shell text search as the default substitute for Bit Lantern when the task is structural
code navigation.
