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
- **Functions** do one thing at one level of abstraction, and are short enough
  to see at once. When a function needs a comment to separate its steps, those
  steps are functions of their own.
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

## 3. Vertical over horizontal

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

## 4. Blocks are always spelled out

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
