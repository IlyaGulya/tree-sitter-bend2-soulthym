-- Validate documented Lua without loading the user's config or contacting GitHub.
-- Run from the repo after: tree-sitter build -o build/bend2.so
local root = vim.fn.getcwd()
local examples, count = {}, 0
for _, file in ipairs({ 'README.md', 'docs/neovim.md' }) do
  local text = table.concat(vim.fn.readfile(root .. '/' .. file), '\n')
  for code in text:gmatch('```lua\n(.-)\n```') do
    count = count + 1
    local name = code:match('^%-%- example: ([^\n]+)') or (file .. ':' .. count)
    code = code:gsub('^%-%- example:[^\n]+\n', '')
    local chunk = code
    if code:match('^%s*{') then
      chunk = 'return ' .. code:gsub(',%s*$', '')
    elseif code:match('^%s*[%w_]+%s*=') then
      chunk = 'return {\n' .. code .. '\n}'
    end
    local fn, err = loadstring(chunk, '@' .. file .. ':' .. name)
    assert(fn, err)
    examples[name] = { run = fn, code = code }
  end
end

-- Execute the documented main-branch configuration against a temporary runtime.
-- No installer/plugin entrypoint is loaded; parser/queries come from this repo.
local plugin = vim.env.BEND2_NVIM_TREESITTER or (vim.fn.stdpath('data') .. '/lazy/nvim-treesitter')
assert(vim.fn.isdirectory(plugin .. '/lua/nvim-treesitter') == 1,
  'Set BEND2_NVIM_TREESITTER to an installed main-branch checkout')
vim.opt.runtimepath:append(plugin)
local tmp = vim.fn.tempname()
local uv = vim.uv or vim.loop
local ok, err = pcall(function()
  vim.fn.mkdir(tmp .. '/parser', 'p')
  vim.fn.mkdir(tmp .. '/queries/bend2', 'p')
  assert(uv.fs_copyfile(root .. '/build/bend2.so', tmp .. '/parser/bend2.so'))
  for _, file in ipairs(vim.fn.glob(root .. '/queries/*.scm', false, true)) do
    assert(uv.fs_copyfile(file, tmp .. '/queries/bend2/' .. vim.fn.fnamemodify(file, ':t')))
  end
  vim.opt.runtimepath:prepend(tmp)
  local spec = examples['main-lazy'].run()
  assert(spec[1] == 'nvim-treesitter/nvim-treesitter' and spec.branch == 'main')
  spec.config()
  local registry = require('nvim-treesitter.parsers')
  assert(registry.bend2.install_info.url == 'https://github.com/Soulthym/tree-sitter-bend2')
  assert(registry.bend2.install_info.queries == 'queries')
  registry.bend2 = nil
  vim.api.nvim_exec_autocmds('User', { pattern = 'TSUpdate' })
  assert(registry.bend2, 'TSUpdate must restore custom registration')

  vim.fn.writefile({ 'def main() -> U32: 42' }, tmp .. '/example.bend')
  vim.cmd('filetype on')
  vim.cmd('edit ' .. vim.fn.fnameescape(tmp .. '/example.bend'))
  local buf = vim.api.nvim_get_current_buf()
  assert(vim.bo[buf].filetype == 'bend', 'filetype detection')
  assert(vim.treesitter.language.get_lang('bend') == 'bend2', 'language mapping')
  assert(vim.treesitter.highlighter.active[buf], 'main example must start highlighting')
  assert(vim.bo[buf].indentexpr:find('nvim%-treesitter'), 'main example must enable indentation')
  assert(not vim.treesitter.get_parser(buf, 'bend2'):parse()[1]:root():has_error())
  for _, query in ipairs({ 'highlights', 'folds', 'indents', 'context', 'textobjects', 'locals', 'tags' }) do
    assert(vim.treesitter.query.get('bend2', query), 'runtime query discovery: ' .. query)
  end

  vim.treesitter.stop(buf)
  vim.api.nvim_del_augroup_by_name('Bend2Treesitter')
  examples['manual-attach'].run()
  vim.api.nvim_exec_autocmds('FileType', { buffer = buf })
  assert(vim.treesitter.highlighter.active[buf], 'manual example must start highlighting')
end)
vim.fn.delete(tmp, 'rf')
assert(ok, err)
print(('Docs: %d Lua snippets compile; main registration, FileType attachment, runtime queries and manual attachment pass.'):format(count))
print('Legacy configuration is syntax-checked only; no downloads or user-config changes.')
vim.cmd('qa!')
