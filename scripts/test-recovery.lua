-- Error locality and highlight recovery, including real broken/repaired buffer
-- edits. Run from the repo after: tree-sitter build -o build/bend2.so
local root = vim.fn.getcwd()
vim.treesitter.language.add('bend2', { path = root .. '/build/bend2.so' })
local highlights = vim.treesitter.query.parse('bend2', table.concat(vim.fn.readfile('queries/highlights.scm'), '\n'))

local cases = {
  { 'extra operator', 'def broken() -> U32: (1 + * 2 : U32)', 'def broken() -> U32: (1 + 2 : U32)' },
  { 'missing parenthesis', 'def broken() -> U32: (1 + 2', 'def broken() -> U32: (1 + 2)' },
  { 'missing let value', 'def broken() -> U32:\n  x =', 'def broken() -> U32:\n  x = 1; x' },
  { 'incomplete case pattern', 'def broken(x: T) -> U32:\n  match x:\n    case A{:', 'def broken(x: T) -> U32:\n  match x:\n    case A{}: 1' },
  { 'invalid character', 'def broken() -> U32: $', 'def broken() -> U32: 1' },
  { 'missing call closer', 'def broken() -> U32: g(1, 2', 'def broken() -> U32: g(1, 2)' },
  { 'missing function body', 'def broken() -> U32:', 'def broken() -> U32: 1' },
  { 'missing header colon', 'def broken() -> U32', 'def broken() -> U32: 1' },
  { 'missing function name', 'def () -> U32: 1', 'def broken() -> U32: 1' },
  { 'unfinished parameters', 'def broken(x: U32', 'def broken(x: U32) -> U32: x' },
  { 'unfinished type argument', 'def broken(x: List<U32', 'def broken(x: List<U32>) -> U32: 1' },
  { 'missing typed let value', 'def broken() -> U32:\n  x: U32 =', 'def broken() -> U32:\n  x: U32 = 1; x' },
  { 'missing parallel value', 'def broken() -> U32:\n  a b = g(1)', 'def broken() -> U32:\n  a b = g(1) g(2); a' },
  { 'unfinished do bind', 'def broken() -> IO(U32):\n  do IO<U32>:\n    x: U32 <-', 'def broken() -> IO(U32):\n  do IO<U32>:\n    x: U32 <- get(); return x' },
  { 'unfinished rewrite', 'def broken(e: P) -> P: %e :', 'def broken(e: P) -> P: %e : P; {==}' },
  { 'missing constructor closer', 'def broken() -> T: C{1', 'def broken() -> T: C{1}' },
  { 'missing list closer', 'def broken() -> T: [1, 2', 'def broken() -> T: [1, 2]' },
  { 'unfinished lambda', 'def broken() -> T: x =>', 'def broken() -> T: x => x' },
}
local prefix = 'def before() -> U32: 1\n'
local suffix = '\n' .. [[
type Recovered is Data: Recovered{}
law recovered_law: U32
@unsafe
def after(x: U32) -> U32: g(42)
]]

local function parse(text)
  return vim.treesitter.get_string_parser(text, 'bend2'):parse()[1]:root()
end
local function signature(node)
  local result = { node:type(), node:range() }
  for child in node:iter_children() do result[#result + 1] = signature(child) end
  return result
end
local function check_neighbors(node, text, label)
  assert(node:has_error(), label .. ': broken input must remain an error')
  local definitions = {}
  for child in node:iter_children() do
    local names = child:field('name')
    if names[1] then definitions[vim.treesitter.get_node_text(names[1], text)] = child end
  end
  for _, name in ipairs({ 'before', 'Recovered', 'recovered_law', 'after' }) do
    local def = definitions[name]
    assert(def and not def:has_error(), label .. ': lost intact declaration ' .. name)
    local _, _, start_byte = def:start()
    local _, _, end_byte = def:end_()
    local actual = text:sub(start_byte + 1, end_byte)
    assert(not actual:find('broken', 1, true), label .. ': neighboring declaration absorbed damaged text')
  end
  local captures = {}
  for id, capture in highlights:iter_captures(node, text, 0, -1) do
    captures[highlights.captures[id] .. ':' .. vim.treesitter.get_node_text(capture, text)] = true
  end
  for _, capture in ipairs({ 'function:before', 'type.definition:Recovered', 'function:recovered_law',
    'function:after', 'variable.parameter:x', 'function.call:g', 'number:42' }) do
    assert(captures[capture], label .. ': lost highlight ' .. capture)
  end
end
local function position(text, offset)
  local preceding = text:sub(1, offset)
  local _, row = preceding:gsub('\n', '')
  return row, #preceding - (preceding:match('.*\n()') or 1) + 1
end
local function edit(buf, from, to)
  local first, last = 0, 0
  while first < math.min(#from, #to) and from:byte(first + 1) == to:byte(first + 1) do first = first + 1 end
  while last < math.min(#from, #to) - first and from:byte(#from - last) == to:byte(#to - last) do last = last + 1 end
  local sr, sc = position(from, first)
  local er, ec = position(from, #from - last)
  vim.api.nvim_buf_set_text(buf, sr, sc, er, ec, vim.split(to:sub(first + 1, #to - last), '\n', { plain = true }))
end
local failed = {}
for _, case in ipairs(cases) do
  local ok, err = pcall(function()
    local broken, fixed = prefix .. case[2] .. suffix, prefix .. case[3] .. suffix
    local expected = parse(fixed)
    assert(not expected:has_error(), case[1] .. ': invalid control fixture')
    check_neighbors(parse(broken), broken, case[1])
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(fixed:sub(1, -2), '\n', { plain = true }))
    local parser = vim.treesitter.get_parser(buf, 'bend2')
    parser:parse()
    for _ = 1, 2 do
      edit(buf, fixed, broken)
      local damaged = parser:parse()[1]:root()
      check_neighbors(damaged, broken, case[1] .. ' (incremental)')
      assert(vim.deep_equal(signature(damaged), signature(parse(broken))), case[1] .. ': incremental error tree differs')
      edit(buf, broken, fixed)
      assert(vim.deep_equal(signature(parser:parse()[1]:root()), signature(expected)), case[1] .. ': repair differs')
    end
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
  if ok then print('PASS ' .. case[1]) else failed[#failed + 1] = tostring(err); print('FAIL ' .. tostring(err)) end
end
assert(#failed == 0, table.concat(failed, '\n'))
print(('Recovery: %d editing scenarios preserve neighboring declarations and highlight captures.'):format(#cases))
vim.cmd('qa!')
