# Code guidelines

These rules apply to every source file in this repository: Nix, Bash, Python,
QML, JavaScript, Lua, and configuration files written by hand. They are
binding. Code that breaks one of them gets changed, unless a review explicitly
says otherwise for that case.

## 1. Readability comes first

Code is written for the next person who reads it. Code that only works isn't
done yet. A reader has to be able to follow it from top to bottom without
stopping to work out what a line does.

When readability conflicts with brevity, cleverness or habit, readability
wins. Performance only wins where it was measured to matter, and then a
comment says so.

## 2. Clean Code

- **Names** say what something is or does, in whole words. Only well-known
  abbreviations (`id`, `url`, `i` in a short loop) are fine. Functions are
  named after what they do (`build_alias`), booleans read as a question
  (`is_empty`, `has_domain`).
- **Functions** do one thing at one level of abstraction, and fit on one
  screen: about 30 to 40 lines at most. When a function needs a comment to
  separate its steps, those steps are functions of their own.
- **At most two levels of nesting** inside a function (an `if` in a loop, say).
  Anything deeper moves into a function of its own or is flattened with guard
  clauses.
- **Few parameters.** Values that belong together travel together (a
  dataclass, an object, an attribute set).
- **No magic values.** Numbers and strings with a meaning are named constants
  at the top of the file.
- **No duplication.** Logic that is needed twice lives in one function.
- **Guard clauses** instead of deep nesting: handle the special case first and
  return early.
- **No dead code** and no commented-out code. Git keeps the history.
- **Comments say why, not what.** If code needs a comment to say what it
  does, rename or split it instead.
- **Leave code better than you found it.** A function that is changed is
  brought in line with these guidelines in the same change, also when the
  rest of the file isn't yet.

## 3. Explicit over implicit

- **Positive conditions.** `if is_enabled` instead of `if not is_disabled`; no
  double negatives.
- **Say what is checked.** Compare against the value that matters (`== 0`,
  `is None`, `== ""`, `-z`) where an empty string, zero or a missing value
  mean different things, instead of relying on what counts as false. In
  JavaScript always `===` and `!==`.
- **Errors are never swallowed silently.** No empty `except: pass`, `catch {}`
  or `2>/dev/null || true`: either handle the error, or catch only the expected
  exception and say in a comment why it can be ignored.
- **Types are written down.** Every Python file starts with
  `# pyright: strict` and has type annotations.

## 4. Vertical over horizontal

Prefer more short lines over fewer long ones.

- **One statement per line.**
- **Name the intermediate steps.** A long expression is split into variables
  whose names explain each step, instead of one nested expression.
- **Short lines.** The formatter's limit (ruff: 120) is a hard ceiling, not a
  target. Split a line long before it gets there.
- **One argument per line** when a call, a list or a dict doesn't fit on one
  short line.
- **One step per line** in chains: method chains, pipes, `.replace(...)`
  sequences.

## 5. Blocks are always spelled out

- **Braces always**, in every language that has them (JavaScript, QML):
  no `if (x) return;`, also for a single statement.
- **The body never shares the line with its condition**, in any language:
  - Python: no `if x: return`, no `for ...: ...` on one line.
  - Bash: no `if ...; then ...; fi` on one line, and no `test && command` or
    `test || command` as an `if`. `|| exit 1` and `|| return 1` right after a
    command, to stop on its failure, are the one exception.
  - Lua: no `if ... then ... end` on one line.
- **No one-liners that hide several steps:** no arrow functions with several
  statements on one line, no comprehensions with more than one `for` or a
  condition that needs thought, no `a and b or c` tricks.
- **No nested conditional expressions.** A ternary (`x ? a : b`,
  `a if x else b`) is fine for a simple choice of value; anything more is an
  `if`/`else`.

## 6. Tools and tests

- **Every language has a formatter**, run by `check.sh`, so that layout isn't
  a matter of taste: nixfmt, ruff format, shfmt for Bash and Zsh
  (`.editorconfig`), stylua for Lua and qmlformat for QML. The formatter's
  output is final; these guidelines decide what it leaves open (names,
  splitting into variables, one argument per line).
- **Exceptions to a formatter are rare and marked.** Where its output is
  clearly harder to read, e.g. qmlformat joining a list of one entry per line
  into a single line, the block is wrapped in the formatter's own markers
  (`// qmlformat off` … `// qmlformat on`, `-- stylua: ignore start` …
  `-- stylua: ignore end`), with a comment above that says why. Such a block
  is a candidate for the cleanup: splitting it into named parts usually makes
  the exception unnecessary.
- **Logic that can be tested is tested.** Parsing, arithmetic and file
  handling get unit tests in `tests/` (see `CLAUDE.md`); what needs the
  desktop is tried by hand.
