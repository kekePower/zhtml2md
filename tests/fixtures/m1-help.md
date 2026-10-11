usage: zhtml2md [--strict] [--] [FILE|-]
       zhtml2md --help
       zhtml2md --version

Convert UTF-8 HTML to compact, deterministic Markdown.
With no operand, or -, read standard input.

Options:
  --strict   fail on recoverable syntax defects instead of repairing
  --         end option parsing (allow paths beginning with -)
  --help     print this text and exit
  --version  print the version and exit

Status: 0 ok, 1 io/internal, 2 usage, 3 input rejected, 4 limit exceeded
