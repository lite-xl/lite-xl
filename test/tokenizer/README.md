# Tokenizer golden corpus

A regression gate for the syntax tokenizer. It tokenizes every line of every
file under [`corpus/`](corpus) with `core.tokenizer` — driven exactly as
`core.doc.highlighter` drives it, feeding each line's outgoing state into the
next — and reduces the output to one digest per line in
[`golden.txt`](golden.txt).

Any change that alters the token stream for the corpus shows up as a diff:
`data/core/tokenizer.lua`, the pattern matcher in `src/api/utf8.c`,
`src/api/regex.c`, `data/core/syntax.lua`, or a bundled `language_*` plugin.

## Running

```sh
test/tokenizer/run.sh            # check corpus against golden.txt, exit 1 on drift
test/tokenizer/run.sh record     # regenerate golden.txt after an intended change
```

The binary is taken from `$LITE_XL`, then `build/src/lite-xl`, then `PATH`.
It runs through the headless `LITE_XL_RUNTIME` hook, so no window opens.

On a mismatch the current token stream for each affected file is written to
`test/tokenizer/actual/<file>.tokens` (git-ignored) for eyeballing.

## Corpus

`sample.*` are real files copied from the tree. `edge_*` are hand-written for
cases that have regressed before or stress the state machine: nested Lua long
comments, an unterminated C block comment, a Python docstring open at EOF, a
16k-character single line, subsyntax nesting (HTML → JS/CSS, Markdown fences),
and invalid UTF-8 bytes (#1484 / #1870 / #2023).

A line the tokenizer *raises* on is recorded as `raised:<hash>` rather than
skipped, so fixing the crash registers as a diff. On stock `master` the
invalid-UTF-8 lines are in that state.

## What it does not cover

The `resume` / time-budget coroutine path, and re-tokenization after edits —
this is whole-file, cold-state only.
