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
  local header = 'def broken(x: U32) -> U32:\n  g!'
  -- Baseline recovery leaves the invalid GPU prefix before the body field.
  -- Keep header/body highlights without pinning the damaged GPU-call tree.
  cases[#cases + 1] = { 'GPU opener after ' .. gap[1],
    header .. gap[2] .. '(7)', header .. '(7)', false, 'body_prefix' }
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
-- An invalid do body must not swallow the next complete declaration header.
-- This is recovery coverage, not support for match/ordinary lets inside do.
local invalid_do = 'def broken(x: Bool) -> IO(Bool):\n  do IO<Bool>:\n'
  .. '    y = x\n    match x:\n      case False{}: return x\n'
  .. '      case True{}:\n        r : Bool <- work(x)\n        return r'
local valid_do = 'def broken(x: Bool) -> IO(Bool):\n  do IO<Bool>:\n    return x'
local definition_first = '\ndef after(x: U32) -> U32: g(42)\n'
  .. 'type Recovered is Data: Recovered{}\nlaw recovered_law: U32\n'
for _, crlf in ipairs({ false, true }) do
  cases[#cases + 1] = {
    'invalid nested do body ' .. (crlf and 'CRLF' or 'LF'),
    invalid_do, valid_do, suffix = definition_first, crlf = crlf,
  }
end
-- A decorated definition can be the very first intact recovery neighbor.
for _, crlf in ipairs({ false, true }) do
  for _, scenario in ipairs({
    { 'invalid do before immediate decorated def', invalid_do, valid_do, '\n@unsafe' .. definition_first },
    { 'stray inline decorator', 'def broken() -> U32: 1 @unsafe garbage', 'def broken() -> U32: 1' },
    { 'decorator on type', invalid_do .. '\n@unsafe type Extra is Data: Extra{}', valid_do .. '\ntype Extra is Data: Extra{}' },
    { 'decorator on law', invalid_do .. '\n@unsafe law extra: U32', valid_do .. '\nlaw extra: U32' },
  }) do
    cases[#cases + 1] = { scenario[1] .. (crlf and ' CRLF' or ' LF'), scenario[2], scenario[3],
      suffix = scenario[4], crlf = crlf }
  end
end
local structure_queries = {}
for file, capture in pairs({ folds = 'fold', tags = 'definition.function', context = 'context',
  textobjects = 'function.outer', locals = 'local.scope', indents = 'indent.begin' }) do
  structure_queries[file] = { capture = capture, query = vim.treesitter.query.parse('bend2',
    table.concat(vim.fn.readfile('queries/' .. file .. '.scm'), '\n')) }
end
local locality_count = #cases
-- Missing call/constructor closers must retain sibling arms and editor
-- captures. Other damaged-arm forms still promise only consistency/repair;
-- do not enshrine their current error trees.
for _, arm in ipairs({
  { 'missing let value', 'y =', 'y = 1; y' },
  { 'missing parenthesis', '(1 + 2', '(1 + 2)' },
  { 'missing call closer', 'g(1, 2', 'g(1, 2)', retain_siblings = true },
  { 'invalid character', '$', '1' },
  { 'missing constructor closer', 'C{1', 'C{1}', retain_siblings = true },
  { 'missing quote', '"unfinished', '"unfinished"' },
  { 'missing body', '', '1' },
}) do
  local start = 'def broken(x: T) -> U32:\n  match x:\n    case A{}:\n      '
  local finish = '\n    case B{}: 42\n    case C{}: 43'
  local retain = arm.retain_siblings
  for _, crlf in ipairs(retain and { false, true } or { false }) do
    cases[#cases + 1] = {
      'match arm: ' .. arm[1] .. (crlf and ' CRLF' or ' LF'),
      start .. arm[2] .. finish, start .. arm[3] .. finish, true, crlf = crlf,
      following_cases = retain and { ['B{}'] = '42', ['C{}'] = '43' } or nil,
    }
  end
end
for _, inner_sibling in ipairs({ false, true }) do
  for _, crlf in ipairs({ false, true }) do
    local start = 'def broken(x: T) -> U32:\n  match x:\n    case A{}:\n'
      .. '      match x:\n        case InnerA{}:\n          g(1, 2'
    local finish = (inner_sibling and '\n        case InnerB{}: 44' or '')
      .. '\n    case B{}: 42\n    case C{}: 43'
    local retained = { ['B{}'] = '42', ['C{}'] = '43' }
    if inner_sibling then retained['InnerB{}'] = '44' end
    cases[#cases + 1] = {
      (inner_sibling and 'inner' or 'outer') .. ' match boundary ' .. (crlf and 'CRLF' or 'LF'),
      start .. finish, start .. ')' .. finish, true, crlf = crlf, following_cases = retained,
    }
  end
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
local function position(text, offset)
  local preceding = text:sub(1, offset)
  local _, row = preceding:gsub('\n', '')
  return row, #preceding - (preceding:match('.*\n()') or 1) + 1
end
-- Source offsets are independent of the recovered tree. Comparing text alone
-- would miss borrowed fields or captures extending into a damaged neighbor.
local function check_range(node, text, first, last, label)
  assert(node, label .. ': missing node')
  local sr, sc = position(text, first - 1)
  local er, ec = position(text, last)
  local _, _, a = node:start()
  local _, _, b = node:end_()
  assert(a == first - 1 and b == last and vim.deep_equal({ node:range() }, { sr, sc, er, ec }),
    label .. ': wrong range for ' .. node:type())
end
local function source_range(text, fragment, from)
  local first, last = text:find(fragment, from or 1, true)
  assert(first, 'fixture missing source fragment: ' .. fragment)
  return first, last
end
local function check_capture(query, node, text, name, first, last, label)
  for id, capture in query:iter_captures(node, text, 0, -1) do
    local _, _, a = capture:start()
    local _, _, b = capture:end_()
    if query.captures[id] == name and a == first - 1 and b == last then
      check_range(capture, text, first, last, label .. ' @' .. name)
      return
    end
  end
  error(label .. ': lost exact capture @' .. name .. ' at bytes ' .. (first - 1) .. '..' .. last)
end
local function check_intact_function(def, text, label)
  local declaration = 'def after(x: U32) -> U32: g(42)'
  local first, last = source_range(text, declaration)
  local header = first
  local decorator = text:sub(1, first - 1):match('@unsafe\r?\n$')
  if decorator then first = first - #decorator end
  assert(def:type() == 'function_definition', label .. ': wrong intact definition type')
  check_range(def, text, first, last, label .. ' after definition')
  local parts = {}
  for _, spec in ipairs({
    { 'name', 'after' }, { 'parameters', '(x: U32)' },
    { 'return_type', 'U32', header + #('def after(x: U32) -> ') }, { 'body', 'g(42)' },
  }) do
    local a, b = source_range(text, spec[2], spec[3] or header)
    local field = def:field(spec[1])
    assert(#field == 1 and not field[1]:has_error(), label .. ': damaged after field ' .. spec[1])
    check_range(field[1], text, a, b, label .. ' after field ' .. spec[1])
    parts[spec[1]] = { a, b, field[1] }
  end
  local parameter = parts.parameters[3]:named_child(0)
  local x = header + #('def after(')
  check_range(parameter, text, x, x + #('x: U32') - 1, label .. ' after parameter')
  check_range(parameter:field('name')[1], text, x, x, label .. ' after parameter name')
  check_range(parameter:field('type')[1], text, x + 3, x + 5, label .. ' after parameter type')
  local body = parts.body[1]
  for _, spec in ipairs({
    { 'function', parts.name[1], parts.name[2] }, { 'variable.parameter', x, x },
    { 'function.call', body, body }, { 'number', body + 2, body + 3 },
  }) do
    check_capture(highlights, def, text, spec[1], spec[2], spec[3], label .. ' after highlights')
  end
  for file, captures in pairs({
    folds = { { 'fold', first, last } },
    tags = { { 'definition.function', first, last }, { 'name', parts.name[1], parts.name[2] },
      { 'reference.call', body, parts.body[2] }, { 'name', body, body } },
    context = { { 'context', first, last }, { 'context.end', body, parts.body[2] } },
    textobjects = { { 'function.outer', first, last }, { 'function.inner', body, parts.body[2] },
      { 'parameter.outer', x, x + 5 }, { 'parameter.inner', x, x + 5 },
      { 'call.outer', body, parts.body[2] }, { 'call.inner', body + 2, body + 3 } },
    locals = { { 'local.scope', first, last }, { 'local.definition', x, x },
      { 'local.reference', parts.name[1], parts.name[2] }, { 'local.reference', body, body } },
    indents = { { 'indent.begin', first, last },
      { 'indent.align', parts.parameters[1], parts.parameters[2] },
      { 'indent.align', body + 1, parts.body[2] } },
  }) do
    for _, spec in ipairs(captures) do
      check_capture(structure_queries[file].query, def, text, spec[1], spec[2], spec[3], label .. ' after ' .. file)
    end
  end
  local decorations = {}
  for child in def:iter_children() do
    if child:type() == 'decorator' then decorations[#decorations + 1] = child end
  end
  assert(#decorations == (decorator and 1 or 0), label .. ': changed after decorator')
  if decorator then
    check_range(decorations[1], text, first, first + 6, label .. ' after decorator')
    check_capture(highlights, def, text, 'attribute', first, first + 6, label .. ' after decorator highlight')
  end
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
  check_intact_function(definitions.after, text, label)
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
    local affected = (damaged_field == 'parameter' and field == 'parameters')
      or ((damaged_field == 'body' or damaged_field == 'body_prefix') and field == 'body')
    assert(part and (affected or not part:has_error()), label .. ': damaged intact field ' .. field)
  end
  if damaged_field ~= 'body' and damaged_field ~= 'body_prefix' then
    assert(vim.treesitter.get_node_text(def:field('body')[1], text) == 'g(7)', label .. ': changed function body')
  end
  local captures = {}
  for id, capture in highlights:iter_captures(def, text, 0, -1) do
    captures[highlights.captures[id] .. ':' .. vim.treesitter.get_node_text(capture, text)] = true
  end
  local wanted = { 'function:broken', 'variable.parameter:x' }
  if damaged_field == 'body_prefix' then
    wanted[#wanted + 1] = 'number:7'
  elseif damaged_field ~= 'body' then
    vim.list_extend(wanted, { 'function.call:g', 'number:7' })
  end
  for _, capture in ipairs(wanted) do
    assert(captures[capture], label .. ': lost edited-function highlight ' .. capture)
  end
  local _, _, start_byte = def:field('name')[1]:end_()
  local _, _, end_byte = def:field('parameters')[1]:start()
  if damaged_field == 'parameter' or damaged_field == 'body' then
    local affected = def:field(damaged_field == 'parameter' and 'parameters' or 'body')[1]
    _, _, start_byte = affected:start()
    _, _, end_byte = affected:end_()
  elseif damaged_field == 'body_prefix' then
    _, _, start_byte = def:field('return_type')[1]:end_()
    _, _, end_byte = def:end_()
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
local function check_following_cases(node, text, label, expected)
  local arms = {}
  local function collect(n)
    if n:type() == 'case_clause' then
      local pattern = n:field('pattern')[1]
      if pattern then arms[vim.treesitter.get_node_text(pattern, text)] = n end
    end
    for child in n:iter_children() do collect(child) end
  end
  collect(node)
  for pattern, value in pairs(expected) do
    local arm = arms[pattern]
    assert(arm and not arm:has_error(), label .. ': lost intact following arm ' .. pattern)
    local body = arm:field('body')[1]
    assert(body and vim.treesitter.get_node_text(body, text) == value,
      label .. ': changed following arm body ' .. pattern)
    local got = {}
    for id, capture in highlights:iter_captures(arm, text, 0, -1) do
      got[highlights.captures[id] .. ':' .. vim.treesitter.get_node_text(capture, text)] = true
    end
    for _, wanted in ipairs({ 'keyword.conditional:case', 'constructor:' .. pattern:sub(1, -3), 'number:' .. value }) do
      assert(got[wanted], label .. ': lost following-arm highlight ' .. wanted)
    end
    local _, _, arm_start = arm:start()
    local _, _, arm_end = arm:end_()
    local function check_errors(n)
      if n:type() == 'ERROR' or n:missing() then
        local _, _, first = n:start()
        local _, _, last = n:end_()
        assert(last <= arm_start or first >= arm_end, label .. ': error overlaps intact arm ' .. pattern)
      end
      for child in n:iter_children() do check_errors(child) end
    end
    check_errors(node)
    for file, capture_name in pairs({
      folds = 'fold', context = 'context', textobjects = 'conditional.outer',
      locals = 'local.scope', indents = 'indent.begin',
    }) do
      local query = structure_queries[file].query
      local found = false
      for id, capture in query:iter_captures(arm, text, 0, -1) do
        found = found or (query.captures[id] == capture_name and capture:id() == arm:id())
      end
      assert(found, label .. ': lost ' .. file .. ' capture for ' .. pattern)
    end
  end
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
-- A valid multiline string can contain a same-column case-looking line.
-- It must not trigger damaged-arm recovery or create a phantom sibling.
for _, crlf in ipairs({ false, true }) do
  local text = 'def quoted(x: T) -> String:\n  match x:\n    case A{}:\n'
    .. '      "first\n    case NotAnArm{}: 99\nlast"\n    case B{}: "other"\n'
  if crlf then text = text:gsub('\n', '\r\n') end
  local tree = parse(text)
  assert(not tree:has_error(), 'case-looking multiline string rejected')
  local query = vim.treesitter.query.parse('bend2', '(case_clause pattern: (_) @pattern)')
  local patterns = {}
  for _, capture in query:iter_captures(tree, text, 0, -1) do
    patterns[#patterns + 1] = vim.treesitter.get_node_text(capture, text)
  end
  assert(vim.deep_equal(patterns, { 'A{}', 'B{}' }), 'string contents became match arms')
end
for _, text in ipairs({
  '@ # marker\nunsafe # keyword\ndef f() -> U32: g!(1)\n',
  'def f() -> Type: (@unsafe: U32 -> U32)\n',
}) do
  assert(not parse(text):has_error(), 'valid contextual/decorator control rejected')
end
local failed = {}
local retained_arm_count = 0
for _, case in ipairs(cases) do
  local ok, err = pcall(function()
    local tail = case.suffix or suffix
    local broken, fixed = prefix .. case[2] .. tail, prefix .. case[3] .. tail
    if case.crlf then
      broken, fixed = broken:gsub('\n', '\r\n'), fixed:gsub('\n', '\r\n')
    end
    local expected = parse(fixed)
    assert(not expected:has_error(), case[1] .. ': invalid control fixture')
    local function check_damaged(node, label)
      if case[4] then
        assert(node:has_error(), label .. ': broken match must remain an error')
        if case.following_cases then
          check_neighbors(node, broken, label)
          check_following_cases(node, broken, label, case.following_cases)
        end
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
    if case.following_cases then retained_arm_count = retained_arm_count + 1 end
    local scope = case.following_cases and ' (sibling-arm locality/captures)'
      or (case[4] and ' (consistency/repair only)' or '')
    print('PASS ' .. case[1] .. scope)
  else
    failed[#failed + 1] = tostring(err); print('FAIL ' .. tostring(err))
  end
end
assert(#failed == 0, table.concat(failed, '\n'))
print(('Recovery: %d declaration locality/highlight scenarios; %d sibling-arm locality/capture scenarios; %d match repair/consistency-only scenarios.'):format(
  locality_count, retained_arm_count, #cases - locality_count - retained_arm_count))
vim.cmd('qa!')
