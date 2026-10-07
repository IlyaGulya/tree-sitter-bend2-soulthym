-- Run from the repository: nvim --headless -u NONE -l scripts/test-neovim.lua
-- Does not load the user's init.lua or install plugins/parsers.
local root = vim.fn.getcwd()
vim.treesitter.language.add('bend2', { path = root .. '/build/bend2.so' })
vim.treesitter.language.register('bend2', 'bend')
for _, file in ipairs(vim.fn.glob(root .. '/queries/*.scm', false, true)) do
  local name = vim.fn.fnamemodify(file, ':t:r')
  vim.treesitter.query.set('bend2', name, table.concat(vim.fn.readfile(file), '\n'))
  assert(vim.treesitter.query.get('bend2', name), name)
end

local source = [[type T is Data:
  A{}
  B{}
def f(x: T, y: T) -> T: match x:
  case A{}:
    match y:
      case A{}: B{}
      case B{}: A{}
  case B{}: x
def main() -> IO(Unit):
  do IO<Unit>:
    log("#hello")
    n: U32 <- do IO<U32>:
      return 2
    log(show(n))
def work(x: U32) -> U32:
  a b = g!(x) g(x)
  +m = h(a, b)
  (m + 1 * 2 : U32)
]]
local function parse(text)
  return vim.treesitter.get_string_parser(text, 'bend2'):parse()[1]:root()
end
local function signature(node)
  local out = { node:type(), node:range() }
  for child in node:iter_children() do out[#out + 1] = signature(child) end
  return out
end
assert(not parse(source):has_error(), 'smoke source contains syntax errors')
assert(not parse(source:gsub('\n', '\r\n')):has_error(), 'CRLF input')
assert(not parse(source:sub(1, -2)):has_error(), 'EOF without final newline')
assert(not parse(''):has_error(), 'empty file')
assert(not parse('# comment at EOF'):has_error(), 'comment-only file')
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
local function set_text(text)
  local lines = vim.split(text, '\n', { plain = true })
  if lines[#lines] == '' then table.remove(lines) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end
set_text(source)
vim.bo[buf].filetype = 'bend'
local parser = vim.treesitter.get_parser(buf, 'bend2')
vim.treesitter.start(buf, 'bend2')
parser:parse()
local query = vim.treesitter.query.get('bend2', 'highlights')
vim.wo.foldmethod = 'expr'
vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
vim.cmd('normal! zx')
assert(vim.fn.foldlevel(2) > 0, 'missing declaration fold')

-- Role captures must cover the intended token, not neighboring delimiters.
local role_source = [[
@unsafe
def work?(x: U32) -> T: g!(x)
def elim() -> T: \{A: x => x; B: y => y; fallback}
def hole() -> T: ?TODO
]]
local role_tree = parse(role_source)
assert(not role_tree:has_error(), 'invalid highlight role fixture')
local expected_roles = {
  ['attribute:?'] = false, ['keyword.modifier:!'] = false,
  ['punctuation.bracket:('] = false, ['constructor:A'] = false,
  ['constructor:B'] = false, ['variable.builtin:?TODO'] = false,
  ['function:work'] = false, ['function.call:g'] = false,
  ['variable.parameter:x'] = false,
}
for id, node in query:iter_captures(role_tree, role_source, 0, -1) do
  local key = query.captures[id] .. ':' .. vim.treesitter.get_node_text(node, role_source)
  if expected_roles[key] ~= nil then expected_roles[key] = true end
  assert(key ~= 'operator:?', 'unsafe/hole marker incorrectly overrides its semantic role')
  assert(key ~= 'keyword.modifier:!(', 'GPU modifier includes its opening bracket')
end
for role, found in pairs(expected_roles) do assert(found, 'missing token role: ' .. role) end
local brackets = vim.treesitter.query.parse('bend2',
  '(arguments (gpu_call "(" @open) ")" @close) @pair')
local gpu_pair = {}
for id, node in brackets:iter_captures(role_tree, role_source, 0, -1) do
  gpu_pair[brackets.captures[id]] = vim.treesitter.get_node_text(node, role_source)
end
assert(gpu_pair.open == '(' and gpu_pair.close == ')' and gpu_pair.pair == '!(x)',
  'GPU argument parentheses are not available to bracket queries')

-- Check trees after real buffer edits against independent full parses. Include
-- unfinished strings, altered columns, deleted delimiters, comments and EOF.
math.randomseed(20260926)
local edits = { '', '#', '\n', ' ', '=>', '"', ')', '+x', 'case ', ';', '\\' }
for i = 1, 180 do
  if i % 15 == 1 then set_text(source); parser:parse() end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local row = math.random(#lines) - 1
  local col = math.random(#lines[row + 1] + 1) - 1
  local last = math.min(col + math.random(0, 3), #lines[row + 1])
  local insert = edits[math.random(#edits)]
  vim.api.nvim_buf_set_text(buf, row, col, row, last, vim.split(insert, '\n', { plain = true }))
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n'
  local incremental = parser:parse()[1]:root()
  assert(vim.deep_equal(signature(incremental), signature(parse(text))), 'incremental mismatch at edit ' .. i)
end

-- Exercise the installed main-branch indent implementation without its plugin
-- entrypoint (which could install packages). Optional outside this environment.
local plugin = vim.env.BEND2_NVIM_TREESITTER or (vim.fn.stdpath('data') .. '/lazy/nvim-treesitter')
if vim.fn.isdirectory(plugin .. '/lua/nvim-treesitter') == 1 then
  vim.opt.runtimepath:append(plugin)
  set_text('def f(x: T) -> T:\n  match x:\n    case A{}:\n      x\n    case B{}:\n      x\n')
  vim.bo.shiftwidth = 2
  vim.bo.expandtab = true
  parser:parse()
  local indent = require('nvim-treesitter.indent')
  for line, want in ipairs({ 0, 2, 4, 6, 4, 6 }) do
    local got = indent.get_indent(line)
    assert(got == want, ('indent line %d: wanted %d, got %d'):format(line, want, got))
  end
  print('Indentation checked against installed nvim-treesitter.')
else
  print('SKIP optional nvim-treesitter indentation implementation (not installed).')
end
print('Neovim: seven queries, captures, folds and 180 incremental edits passed.')
vim.cmd('qa!')
