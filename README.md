# tree-sitter-bend2

Tree-sitter grammar for **Bend 2**, with Neovim highlighting, folding,
indentation, textobjects, locals, symbol tags and treesitter-context queries.
This is **not** the older Bend/HVM language grammar.

Syntax reference: Bend **2.0.29**, checkout `574b6d39`, specifically
[`bend2/bend.ts`](../bend/bend2/bend.ts).

## Build and test (offline)

Requires a C compiler and Tree-sitter CLI **0.26.9** (used for development).
Generated ABI-15 sources are included, so consumers need not generate the parser.
Node is needed for the upstream sweep; Neovim is needed for editor tests.
The upstream sweep expects the Bend checkout in a sibling directory named
`bend` (`../bend` relative to this repository). You can pass a different checkout
path to `scripts/validate-upstream.mjs`. Corpus and Neovim tests do not require
the Bend checkout.

These commands use installed tools; no npm installation is necessary:

```sh
tree-sitter generate
tree-sitter test
tree-sitter build -o build/bend2.so
nvim --headless -u NONE -l scripts/test-neovim.lua
node scripts/validate-upstream.mjs ../bend
```

Equivalent npm scripts: `generate`, `test`, `test:neovim`, `test:upstream`.
`test:bindings` retains the scaffold's Node binding test, requiring its npm
dependencies to be installed separately.

### Validation results

On the pinned checkout:

- **1,577 / 1,577 `.bend` files visited**, with a per-file timeout.
- **1,466 clean parses**, including the entire 3,018-line standard library,
  all demos, all benchmarks and every fixture without an expected diagnostic.
- **111 rejections**, pinned in `test/upstream-rejections.json`. These contain
  malformed or removed syntax. Some upstream goldens stop at an *earlier*
  semantic error, so “expects an error” alone is not used as an exemption.
- **41 corpus cases**, covering tree shape, precedence, column ownership,
  literals, proofs, do notation, templates, parallel lets, arrays and rejection.
- All seven queries compile in Neovim **0.12.1**; captures, folds, conventional
  indentation and **180 deterministic incremental edits** are checked.

The sweep writes **every file's result** to `build/upstream-report.json`, not
just failures. New rejections (including diagnostic fixtures) and formerly
rejected fixtures require review against the baseline. No Bend code, foreign
effects, import resolution or network requests are executed by this sweep.
A clean Tree-sitter tree is not proof that a program typechecks.

## Neovim: nvim-treesitter `main`

Keep the existing **`bend` filetype** (including any Bend2 LSP autocmd), and map
it to the **`bend2` parser**. No user configuration is changed by this repo.

Place this at the **start of your existing nvim-treesitter `config` function**,
before computing `get_available()` or installing parsers:

```lua
local function register_bend2()
  require('nvim-treesitter.parsers').bend2 = {
    install_info = {
      path = '<path>/<to>/tree-sitter-bend2/', -- your local checkout
      queries = 'queries',
    },
  }
end
register_bend2()
vim.api.nvim_create_autocmd('User', {
  pattern = 'TSUpdate',
  callback = register_bend2,
})
vim.filetype.add({ extension = { bend = 'bend' } })
vim.treesitter.language.register('bend2', 'bend')
```

Adjust the checkout path if necessary, then run **`:TSInstall bend2`**.
This uses the local checkout, not an SSH/Git remote. Your existing FileType
callback can start highlighting and `nvim-treesitter` indentation as usual.
After modifying the grammar, regenerate it and run `:TSUpdate bend2`.

Optional folding (your config currently leaves it disabled):

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'bend',
  callback = function()
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.bo.commentstring = '# %s'
    vim.bo.shiftwidth = 2
  end,
})
```

Your installed treesitter-context plugin can use `context.scm` automatically.
Textobject captures need a consumer; for your existing mini.ai setup, add:

```lua
local ai = require('mini.ai')
ai.setup({
  n_lines = 500,
  custom_textobjects = {
    f = ai.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
    c = ai.gen_spec.treesitter({ a = '@class.outer', i = '@class.inner' }),
    o = ai.gen_spec.treesitter({ a = '@conditional.outer', i = '@conditional.inner' }),
  },
})
```

### Direct installation without a plugin installer

Alternatively, compile into a temporary location and copy `bend2.so` into
`stdpath('data') .. '/site/parser/'`, and the contents of `queries/` into
`stdpath('data') .. '/site/queries/bend2/'`. Register `bend2` for `bend` as above
and call `vim.treesitter.start()` for Bend buffers. Do not install both ways.

## Syntax and scope

The grammar follows the implementation, including:

- `def`, `law`, `type`, ordinary/foreign imports, `@unsafe`, `?` definitions;
- quantities, dependent arrows, existential binders, equality and rewrites;
- constructor/list/tuple/natural patterns, local and counted parallel lets;
- templates, GPU calls, do binds/lets/steps, arrays and implicit write rebinding;
- optional argument commas, adjacency-sensitive constructors and operators;
- nested case ownership by **case columns**, not Python INDENT/DEDENT tokens.

Indentation queries suggest conventional formatting; they do not define the
language. Native C/JS foreign imports contain **paths**, not embedded source,
so there is deliberately no fake C/JS injection query.

### Boundaries and remaining limitations

- Bend's parser performs name-sensitive checks and elaboration which cannot be
  represented by a context-free editor grammar: constructor arities, binder
  validity, template counts, law filling, import aliases, quantities, literal
  ranges, finite F32 values and type correctness remain Bend's responsibility.
- Pattern positions retain expression-shaped CST nodes; syntactic locals cover
  simple binders conservatively, not all nested destructuring or dependent
  name resolution. Use the LSP for authoritative references and definitions.
- The serializable scanner supports **100 simultaneously active layout/counting
  frames** (not 100 parentheses). Excessive nesting fails safely instead of
  overflowing Tree-sitter's 1,024-byte serialization buffer.
- Lambda `: T =` lookahead is lexical rather than an embedded second Bend
  parser. Exotic malformed types may recover differently. Source columns use
  Tree-sitter's column API; unusual Unicode-containing same-line layout should
  be tested before relying on equivalence to Bend's JavaScript offsets.
- This is a tested syntax implementation, **not a claim of formal equivalence**
  for every possible byte sequence. Recovery deliberately remains useful on
  incomplete source. Further differences should become focused corpus tests.
- C/CLI and Neovim builds were exercised. Other generated language bindings are
  retained, but their dependency-specific test suites have not all been run.

## Updating the language reference

Review upstream parser/loader changes first, add positive and negative corpus
cases with reviewed trees, regenerate, run the complete sweep and editor tests,
and review changes to the rejection baseline. Never blindly approve generated
expected trees or treat all diagnostic fixtures as syntactically invalid.
