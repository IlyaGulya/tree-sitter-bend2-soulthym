# Neovim installation

The filetype is **`bend`**, the parser language is **`bend2`**, and queries belong
under **`queries/bend2/`** on Neovim's runtimepath. Keeping filetype `bend`
preserves existing Bend LSP, formatter and filetype configuration. Do not select
an older `bend` parser intended for Bend1.

Choose one installation method:

- [nvim-treesitter main / lazy.nvim](#nvim-treesitter-main--lazynvim) — recommended
- [Local development checkout](#local-development-checkout) — optional, offline
- [Legacy nvim-treesitter master](#legacy-nvim-treesitter-master)
- [Manual installation without nvim-treesitter](#manual-installation-without-nvim-treesitter)

Installation does not itself enable highlighting on `main`. The complete
example below includes the required FileType callback. To run a multi-line
one-shot Lua snippet, save it to a temporary `.lua` file and run
`:luafile <path-to-that-file>`.

## nvim-treesitter main / lazy.nvim

The tested setup is Neovim **0.12.1**, nvim-treesitter **main** and Tree-sitter
CLI **0.26.9**. The installed main branch requires Neovim 0.12+, a C compiler,
Tree-sitter CLI 0.26.1+, `curl` and `tar`. Check the requirements of your plugin
revision when upgrading. The grammar ships generated ABI-15 C sources.

Add this **plugin spec** to your existing `require('lazy').setup(...)` list.
If you already configure nvim-treesitter, **merge into that spec instead of
adding a second config function**. Preserve your existing parser list and other
language settings.

```lua
-- example: main-lazy
{
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  lazy = false,
  build = ':TSUpdate',
  config = function()
    local function register_bend2()
      require('nvim-treesitter.parsers').bend2 = {
        install_info = {
          url = 'https://github.com/Soulthym/tree-sitter-bend2',
          queries = 'queries',
          -- revision = '<commit-sha>', -- optional: pin a tested parser revision
        },
      }
    end

    -- Register immediately, and restore the entry when the registry is updated.
    -- Do this before get_available() or any install() calls.
    register_bend2()
    vim.api.nvim_create_autocmd('User', {
      group = vim.api.nvim_create_augroup('Bend2ParserRegistration', { clear = true }),
      pattern = 'TSUpdate',
      callback = register_bend2,
    })

    vim.filetype.add({ extension = { bend = 'bend' } })
    vim.treesitter.language.register('bend2', 'bend')

    -- Omit this callback if your existing one already starts Tree-sitter and
    -- sets indentexpr for all installed parser languages.
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('Bend2Treesitter', { clear = true }),
      pattern = 'bend',
      callback = function(args)
        local loaded, err = vim.treesitter.language.add('bend2')
        if not loaded then
          vim.notify('Bend2: run :TSInstall bend2\n' .. tostring(err), vim.log.levels.WARN)
          return
        end
        vim.treesitter.start(args.buf, 'bend2')
        vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        vim.bo[args.buf].commentstring = '# %s'
      end,
    })
  end,
}
```

Then:

1. Let your plugin manager install nvim-treesitter if needed, then restart Neovim.
2. Run **`:TSInstall bend2`** and wait for completion.
3. Reopen a `.bend` file (`:edit`) so its FileType callback runs.
4. Check `:set filetype?` (must say `bend`) and `:InspectTree`.

The HTTPS GitHub URL requires no SSH key. nvim-treesitter downloads the parser
sources, builds them and installs both the parser and queries in its managed
installation directory (by default `stdpath('data') .. '/site'`). A grammar repo
checkout under `~/.config/nvim` is **not** necessary.

Use **`:TSUpdate bend2`** to rebuild/update, then restart Neovim to unload the old
shared library. A `revision` pin must be changed to receive newer parser commits.
Only published commits can be installed through the GitHub URL.

## Local development checkout

In the `main` example, replace **only** `install_info` with:

```lua
-- example: local-install-info
install_info = {
  path = '<path>/<to>/tree-sitter-bend2/', -- replace with your local checkout
  queries = 'queries',
},
```

Use an absolute path, remove `url`/`revision`, and leave registration, filetype
mapping and highlighting enabled as above. For a checkout deliberately placed
inside your Neovim config, the path can instead be:

```lua
-- example: config-checkout-path
path = vim.fn.stdpath('config') .. '/tree-sitter-bend2',
```

That directory must already contain the checkout; setting `path` does not clone
anything. `:TSInstall bend2` builds locally and links the local queries. After
editing the grammar, run `tree-sitter generate` in the checkout and
`:TSUpdate bend2` in Neovim, then restart. Avoid modifying a checkout while a
parser build is running.

## Legacy nvim-treesitter master

This is a **different API**; do not combine it with the `main` example.
Use a Neovim release supporting **Tree-sitter ABI 15** (Neovim 0.11+), and a
compatible pinned `master` plugin revision. This recipe follows the legacy
custom-parser API; it has not been integration-tested against a legacy plugin
checkout in this environment.

Merge this spec with your existing legacy configuration:

```lua
-- example: legacy-lazy
{
  'nvim-treesitter/nvim-treesitter',
  branch = 'master',
  lazy = false,
  build = ':TSUpdate',
  config = function()
    require('nvim-treesitter.parsers').get_parser_configs().bend2 = {
      install_info = {
        url = 'https://github.com/Soulthym/tree-sitter-bend2',
        files = { 'src/parser.c', 'src/scanner.c' },
        branch = 'main',
        -- revision = '<commit-sha>', -- optional parser revision pin
      },
      filetype = 'bend',
    }
    vim.filetype.add({ extension = { bend = 'bend' } })
    vim.treesitter.language.register('bend2', 'bend')
    require('nvim-treesitter.configs').setup({
      highlight = { enable = true },
      indent = { enable = true },
    })
  end,
}
```

Restart and run **`:TSInstall bend2`**. **Legacy custom-parser installation does
not install this repo's queries automatically.** Obtain a checkout or source
archive matching your chosen parser revision, then copy its `queries/*.scm`
into `stdpath('config') .. '/queries/bend2/'` (usually
`~/.config/nvim/queries/bend2/`). For example, run this once in Neovim after
replacing the placeholder:

```lua
-- example: copy-legacy-queries
local repo = '<path>/<to>/tree-sitter-bend2/'
local dest = vim.fn.stdpath('config') .. '/queries/bend2'
vim.fn.mkdir(dest, 'p')
for _, file in ipairs(vim.fn.glob(repo .. '/queries/*.scm', false, true)) do
  vim.fn.writefile(vim.fn.readfile(file), dest .. '/' .. vim.fn.fnamemodify(file, ':t'))
end
```

Keep these copies synchronized with parser updates. When switching to `main`,
remove stale manually copied queries: config-directory queries can override the
new managed copies. Reopen the Bend buffer after installation.

## Manual installation without nvim-treesitter

Use Neovim 0.11+ for ABI 15. From a local checkout, build with a C compiler and
Tree-sitter CLI:

```sh
cd '<path>/<to>/tree-sitter-bend2/'
tree-sitter build -o build/bend2.so
```

On Linux/Termux, run this Lua once in Neovim, replacing the placeholder. It copies only into Neovim's config runtime directories:

```lua
-- example: copy-manual-runtime
local repo = '<path>/<to>/tree-sitter-bend2/'
local config = vim.fn.stdpath('config')
vim.fn.mkdir(config .. '/parser', 'p')
vim.fn.mkdir(config .. '/queries/bend2', 'p')
local ok, err = (vim.uv or vim.loop).fs_copyfile(repo .. '/build/bend2.so', config .. '/parser/bend2.so')
assert(ok, err)
for _, file in ipairs(vim.fn.glob(repo .. '/queries/*.scm', false, true)) do
  vim.fn.writefile(vim.fn.readfile(file), config .. '/queries/bend2/' .. vim.fn.fnamemodify(file, ':t'))
end
```

Add this configuration to `init.lua`:

```lua
-- example: manual-attach
vim.filetype.add({ extension = { bend = 'bend' } })
vim.treesitter.language.register('bend2', 'bend')
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('Bend2ManualTreesitter', { clear = true }),
  pattern = 'bend',
  callback = function(args)
    vim.treesitter.start(args.buf, 'bend2')
    vim.bo[args.buf].commentstring = '# %s'
  end,
})
```

Restart Neovim. Highlighting and built-in Tree-sitter folds do not need
nvim-treesitter, but its query-driven **indentation does**; do not set its
`indentexpr` without installing the plugin. Rebuild and recopy the parser and
queries together when updating. Do not mix manual copies with a managed
installation; remove the manual copies before switching.

## Optional editor features

### Folding and indentation style

Add a FileType callback, or merge these options into your existing one:

```lua
-- example: folds
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'bend',
  callback = function()
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.bo.expandtab = true
    vim.bo.shiftwidth = 2
  end,
})
```

### Context and textobjects

If `nvim-treesitter-context` is installed and enabled, it discovers the installed
`context.scm` automatically. Textobjects require a consumer, such as mini.ai or
nvim-treesitter-textobjects; queries alone do not create mappings.

For mini.ai, merge these entries into your existing setup (do not replace other
custom textobjects):

```lua
-- example: mini-ai
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

This provides `af`/`if` for functions, `ac`/`ic` for types/laws, and `ao`/`io`
for matches/cases. Locals/tags are supplied for tools consuming those queries;
they do not replace an LSP or automatically provide LSP navigation.

## Troubleshooting missing highlighting

Run these in a `.bend` buffer:

| Check | Expected / remedy |
| --- | --- |
| `:set filetype?` | `filetype=bend`. If empty or different, add `vim.filetype.add(...)` and reopen. |
| `:lua print(vim.treesitter.language.get_lang(vim.bo.filetype))` | `bend2`. If `bend`, add the `language.register(...)` call. |
| `:lua print(vim.inspect(vim.api.nvim_get_runtime_file('parser/bend2.*', true)))` | An installed library. If empty, register first, then `:TSInstall bend2`. |
| `:lua print(vim.inspect(vim.api.nvim_get_runtime_file('queries/bend2/highlights.scm', true)))` | A query file. If empty, check `queries = 'queries'` on main or copy queries for legacy/manual setups. |
| `:lua vim.treesitter.start(0, 'bend2')` | If highlighting starts, your FileType callback was missing or ran before installation. |
| `:InspectTree` | A structured Bend2 tree. Parser loading errors usually mean a missing/stale library or incompatible ABI. |
| `:Inspect` | Shows the highlight capture under the cursor. If captures exist but colors do not change, check your colorscheme. |

After fixing configuration, restart Neovim and reopen the file. Check
`:messages` and `:checkhealth nvim-treesitter` for compiler/installer errors.
On `main`, use `:TSUpdate bend2` to refresh both parser and queries. If a query
reports an invalid node type, ensure parser and queries come from the **same
revision** and remove stale copies earlier on runtimepath. Loading a new `.so`
generally requires restarting Neovim; reinstalling alone does not unload it.

If colors change only while the source is incomplete, inspect its `ERROR` or
missing nodes with `:InspectTree`. See [editing recovery and its limits](../README.md#recovery-while-editing),
especially damaged match arms and multiline strings; these are distinct from
installation or colorscheme problems.

If installation says the language is unknown, registration must run **before**
installation and before any `get_available()` result is cached. If `require`
for `nvim-treesitter.configs` fails, you are probably using a `master` example on
`main`: use the matching setup above.
