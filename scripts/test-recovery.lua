-- Error locality and highlight recovery, including real broken/repaired buffer
-- edits. Run from the repo after: tree-sitter build -o build/bend2.so
local root = vim.fn.getcwd()
vim.treesitter.language.add('bend2', { path = vim.env.BEND2_PARSER or (root .. '/build/bend2.so') })
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
  { 'missing closing quote', 'def broken() -> String: "unfinished', 'def broken() -> String: "unfinished"' },
  { 'missing opening quote', 'def broken() -> String: text"', 'def broken() -> String: "text"' },
  { 'invalid escape', 'def broken() -> String: "\\q"', 'def broken() -> String: "\\n"' },
  { 'unfinished escape', 'def broken() -> String: "text\\', 'def broken() -> String: "text\\n"' },
  { 'multiline closing quote', 'def broken() -> String: "first\nsecond', 'def broken() -> String: "first\nsecond"' },
  { 'distant closing quote', 'def broken() -> String: "' .. ('line\n'):rep(400), 'def broken() -> String: "' .. ('line\n'):rep(400) .. '"' },
}
-- A rejected typo must not cost the surrounding declaration its useful CST.
for _, gap in ipairs({
  { 'space', ' ' }, { 'tab', '\t' }, { 'newline', '\n' },
  { 'CRLF', '\r\n' }, { 'comment', ' # comment\n' },
}) do
  local tail = '?(x: U32) -> U32:\n  g(7)'
  cases[#cases + 1] = { 'unsafe suffix after ' .. gap[1],
    'def broken' .. gap[2] .. tail, 'def broken' .. tail, false, true }
end
for _, op in ipairs({ '&', '|', '->' }) do
  local term = 'A ' .. op .. ' B'
  cases[#cases + 1] = { 'compound parameter argument ' .. op,
    'def broken(x: F<' .. term .. '>) -> U32:\n  g(7)',
    'def broken(x: F<(' .. term .. ')>) -> U32:\n  g(7)', false, 'parameter' }
  cases[#cases + 1] = { 'unfinished compound body argument ' .. op,
    'def broken(x: U32) -> U32:\n  F<' .. term,
    'def broken(x: U32) -> U32:\n  F<(' .. term .. ')>', false, 'body' }
end
local structure_queries = {}
for file, capture in pairs({ folds = 'fold', tags = 'definition.function', context = 'context',
  textobjects = 'function.outer', locals = 'local.scope', indents = 'indent.begin' }) do
  structure_queries[file] = { capture = capture, query = vim.treesitter.query.parse('bend2',
    table.concat(vim.fn.readfile('queries/' .. file .. '.scm'), '\n')) }
end
local locality_count = #cases
-- Known limits: later arms in the SAME damaged match can still be swallowed.
-- Exercise repair/incremental consistency without enshrining today's error
-- tree or requiring highlighting to stay broken after a future improvement.
for _, arm in ipairs({
  { 'missing let value', 'y =', 'y = 1; y' },
  { 'missing parenthesis', '(1 + 2', '(1 + 2)' },
  { 'missing call closer', 'g(1, 2', 'g(1, 2)' },
  { 'invalid character', '$', '1' },
  { 'missing constructor closer', 'C{1', 'C{1}' },
  { 'missing quote', '"unfinished', '"unfinished"' },
  { 'missing body', '', '1' },
}) do
  local start = 'def broken(x: T) -> U32:\n  match x:\n    case A{}:\n      '
  local finish = '\n    case B{}: 42\n    case C{}: 43'
  cases[#cases + 1] = { 'match arm: ' .. arm[1], start .. arm[2] .. finish, start .. arm[3] .. finish, true }
end
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
  for name, wanted in pairs({
    before = { 'function:before' },
    Recovered = { 'type.definition:Recovered', 'constructor:Recovered' },
    recovered_law = { 'function:recovered_law' },
    after = { 'function:after', 'variable.parameter:x', 'function.call:g', 'number:42' },
  }) do
    local captures = {}
    for id, capture in highlights:iter_captures(definitions[name], text, 0, -1) do
      captures[highlights.captures[id] .. ':' .. vim.treesitter.get_node_text(capture, text)] = true
    end
    for _, capture in ipairs(wanted) do
      assert(captures[capture], label .. ': lost highlight ' .. capture .. ' in ' .. name)
    end
  end
end
local function check_edited_function(node, text, label, damaged_field)
  local def
  for child in node:iter_children() do
    local name = child:field('name')[1]
    if name and vim.treesitter.get_node_text(name, text) == 'broken' then def = child end
  end
  assert(def and def:type() == 'function_definition', label .. ': lost the edited function')
  assert(def:has_error(), label .. ': error detached from the edited function')
  for _, field in ipairs({ 'name', 'parameters', 'return_type', 'body' }) do
    local part = def:field(field)[1]
    local affected = (damaged_field == 'parameter' and field == 'parameters') or (damaged_field == 'body' and field == 'body')
    assert(part and (affected or not part:has_error()), label .. ': damaged intact field ' .. field)
  end
  if damaged_field ~= 'body' then
    assert(vim.treesitter.get_node_text(def:field('body')[1], text) == 'g(7)', label .. ': changed function body')
  end
  local captures = {}
  for id, capture in highlights:iter_captures(def, text, 0, -1) do
    captures[highlights.captures[id] .. ':' .. vim.treesitter.get_node_text(capture, text)] = true
  end
  local wanted = { 'function:broken', 'variable.parameter:x' }
  if damaged_field ~= 'body' then vim.list_extend(wanted, { 'function.call:g', 'number:7' }) end
  for _, capture in ipairs(wanted) do
    assert(captures[capture], label .. ': lost edited-function highlight ' .. capture)
  end
  local _, _, start_byte = def:field('name')[1]:end_()
  local _, _, end_byte = def:field('parameters')[1]:start()
  if damaged_field == 'parameter' or damaged_field == 'body' then
    local affected = def:field(damaged_field == 'parameter' and 'parameters' or 'body')[1]
    _, _, start_byte = affected:start()
    _, _, end_byte = affected:end_()
  end
  local function check_errors(n)
    if n:type() == 'ERROR' or n:missing() then
      local _, _, a = n:start()
      local _, _, b = n:end_()
      assert(a >= start_byte and b <= end_byte, label .. ': error escaped the damaged field')
    end
    for child in n:iter_children() do check_errors(child) end
  end
  check_errors(def)
  for file, spec in pairs(structure_queries) do
    local found = false
    for id, capture in spec.query:iter_captures(def, text, 0, -1) do
      found = found or (spec.query.captures[id] == spec.capture and capture:id() == def:id())
    end
    assert(found, label .. ': lost ' .. file .. ' capture for edited function')
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
-- These are valid Bend multiline strings, not declaration recovery points.
-- In particular a later unescaped quote must still close the literal, even
-- when its contents look like source code.
for _, literal in ipairs({
  '"first\ndef not_a_definition() -> U32: 1\nlast"',
  '"first\n# not a comment\n\\"escaped\\"\nlast"',
  '"\n\n"',
  '"first\r\nlast"',
}) do
  local text = prefix .. 'def text() -> String: ' .. literal .. suffix
  local tree = parse(text)
  assert(not tree:has_error(), 'valid multiline string rejected: ' .. literal)
  local strings = vim.treesitter.query.parse('bend2', '(string) @string')
  local count = 0
  for _, capture in strings:iter_captures(tree, text, 0, -1) do
    assert(vim.treesitter.get_node_text(capture, text) == literal, 'multiline string cut short')
    count = count + 1
  end
  assert(count == 1, 'expected exactly one complete multiline string')
end
local failed = {}
for _, case in ipairs(cases) do
  local ok, err = pcall(function()
    local broken, fixed = prefix .. case[2] .. suffix, prefix .. case[3] .. suffix
    local expected = parse(fixed)
    assert(not expected:has_error(), case[1] .. ': invalid control fixture')
    local function check_damaged(node, label)
      if case[4] then
        assert(node:has_error(), label .. ': broken match must remain an error')
      else
        check_neighbors(node, broken, label)
        if case[5] then check_edited_function(node, broken, label, case[5]) end
      end
    end
    check_damaged(parse(broken), case[1])
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(fixed:sub(1, -2), '\n', { plain = true }))
    local parser = vim.treesitter.get_parser(buf, 'bend2')
    parser:parse()
    for _ = 1, 2 do
      edit(buf, fixed, broken)
      local damaged = parser:parse()[1]:root()
      check_damaged(damaged, case[1] .. ' (incremental)')
      assert(vim.deep_equal(signature(damaged), signature(parse(broken))), case[1] .. ': incremental error tree differs')
      edit(buf, broken, fixed)
      assert(vim.deep_equal(signature(parser:parse()[1]:root()), signature(expected)), case[1] .. ': repair differs')
    end
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
  if ok then
    print('PASS ' .. case[1] .. (case[4] and ' (consistency/repair only)' or ''))
  else
    failed[#failed + 1] = tostring(err); print('FAIL ' .. tostring(err))
  end
end
assert(#failed == 0, table.concat(failed, '\n'))
print(('Recovery: %d locality/highlight scenarios; %d additional match repair/consistency scenarios.'):format(locality_count, #cases - locality_count))
vim.cmd('qa!')
