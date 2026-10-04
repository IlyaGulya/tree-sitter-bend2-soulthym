-- Bend 2.0.35 compatibility regressions. No upstream checkout is required.
-- Override BEND2_PARSER to demonstrate failures in the pre-upgrade library.
vim.treesitter.language.add('bend2', { path = vim.env.BEND2_PARSER or (vim.fn.getcwd() .. '/build/bend2.so') })
local failures, count = {}, 0
local function fingerprint(node)
  local out = {}
  local function visit(n)
    out[#out + 1] = n:type() .. ':' .. table.concat({ n:range() }, ',')
    for child in n:iter_children() do visit(child) end
  end
  visit(node)
  return table.concat(out, '\n')
end
local function check(name, text, erroneous, inspect)
  count = count + 1
  local ok, err = pcall(function()
    local node = vim.treesitter.get_string_parser(text, 'bend2'):parse()[1]:root()
    assert(node:has_error() == erroneous, name .. ': expected ' .. (erroneous and 'an error' or 'a clean tree'))
    if inspect then inspect(node, text) end
    -- Change a byte position in the middle, then repair it. This exercises
    -- scanner snapshots deep inside the new nesting/angle-boundary cases.
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text:sub(1, -2), '\n', { plain = true }))
    local parser = vim.treesitter.get_parser(buf, 'bend2')
    assert(fingerprint(parser:parse()[1]:root()) == fingerprint(node), name .. ': buffer parse differs')
    local at = math.floor(#text / 2)
    local prefix = text:sub(1, at)
    local _, row = prefix:gsub('\n', '')
    local col = #prefix - (prefix:match('.*\n()') or 1) + 1
    vim.api.nvim_buf_set_text(buf, row, col, row, col, { ' ' })
    local edited = prefix .. ' ' .. text:sub(at + 1)
    local fresh = vim.treesitter.get_string_parser(edited, 'bend2'):parse()[1]:root()
    assert(fingerprint(parser:parse()[1]:root()) == fingerprint(fresh), name .. ': incremental parse differs')
    vim.api.nvim_buf_set_text(buf, row, col, row, col + 1, { '' })
    assert(fingerprint(parser:parse()[1]:root()) == fingerprint(node), name .. ': repair differs')
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
  if ok then print('PASS ' .. name) else failures[#failures + 1] = tostring(err); print('FAIL ' .. tostring(err)) end
end
for _, depth in ipairs({ 99, 100, 140, 190, 199 }) do
  local expression = 'a'
  for _ = 1, depth do expression = '(' .. expression .. ' + b : U32)' end
  check('nested operators depth ' .. depth, 'def deep(+a: U32, +b: U32) -> U32: ' .. expression .. '\n', false)
end
check('nesting overflow remains an error', 'def f() -> T: ' .. ('('):rep(200) .. '1' .. (')'):rep(200) .. '\n', true)
check('deep mixed match frames', 'def f(x: T) -> T: ' .. ('('):rep(140) .. 'match x:\n' .. (' '):rep(180) .. 'case A{}: 1' .. (')'):rep(140) .. '\n', false)
for _, op in ipairs({ '&', '|', '->' }) do
  check('compound type needs parentheses ' .. op, 'def f(x: F<A ' .. op .. ' B>) -> T: x\n', true)
  check('glued comparison cannot hide compound type ' .. op, 'def f() -> T: F<A ' .. op .. ' B\n', true)
  check('parenthesized type argument ' .. op, 'def f(x: F<(A ' .. op .. ' B)>) -> T: x\n', false)
  check('spaced comparison before type operator ' .. op, 'def f() -> T: F < A ' .. op .. ' B\n', false)
end
for _, expression in ipairs({
  '1<2<=3', '1<2 < 3', '1<2<3', '1<2 + 3 * 4', '1<2 << 3',
  '1<2 && 3', '1<2 || 3',
  'F<A<B>>', 'F<&2, A>', 'F < A >', 'F<(A & B)>',
}) do
  check('comparison/type control ' .. expression, 'def f() -> T: ' .. expression .. '\n', false)
end
-- Postfix/glued operations bind within arithmetic operands; accepting the
-- tokens is insufficient if the CST assigns them to the wrong expression.
for _, case in ipairs({
  { '1<2 + 3 * 4', '<', '2 + 3 * 4' },
  { '1 + 2<3', '+', '2<3' },
  { '1<2 << 3', '<', '2 << 3' },
  { '1<2<3', '<', '2<3' },
  { '1<2(3)', '<', '2(3)' },
  { '1<2[3]', '<', '2[3]' },
  { '1 + f(2)', '+', 'f(2)' },
  { '1 + a[2]', '+', 'a[2]' },
  { '(f)(2)(3)', nil, nil },
  { '(a + b)[2]', nil, nil },
  { 'F<A, B & C>', nil, nil },
  { 'F<A, B | C>', nil, nil },
  { 'F<A, B -> C>', nil, nil },
}) do
  check('precedence/recovery control ' .. case[1], 'def f() -> T: ' .. case[1] .. '\n', false, function(node, text)
    if not case[2] then return end
    local expr = node:named_child(0):field('body')[1]:named_child(0)
    assert(expr:type() == 'binary_expression', 'lost binary expression')
    local op, rhs = expr:field('operator')[1], expr:field('right')[1]
    assert(op and vim.treesitter.get_node_text(op, text) == case[2], 'wrong root operator')
    assert(rhs and vim.treesitter.get_node_text(rhs, text) == case[3], 'wrong right-operand ownership')
  end)
end
-- Verified with Bend.parse_term: these are interpreted as attempted family
-- applications, not chained numeric comparisons (the family head is invalid).
for _, expression in ipairs({ '1<2 > 3', '1<2 >= 3' }) do
  check('numeric family head refused ' .. expression, 'def f() -> T: ' .. expression .. '\n', true)
end
check('generic law clauses retain their body', 'law f:\n  for xs: List<&2, U32>\n  U32\n', false)
check('glued boolean comparisons', 'def f() -> U32: (1<2 && 2<3 : U32)\n', false)
check('unsafe suffix', '@unsafe def Value.get? () -> U32: 1\n', false)
check('unsafe suffix rejects space', 'def value ?() -> U32: 1\n', true)
check('unsafe suffix rejects newline', 'def value\n?() -> U32: 1\n', true)
check('unsafe suffix rejects comment', 'def value # comment\n?() -> U32: 1\n', true)
check('explicit Array.set keeps eliminator fallback', 'def f() -> T: \\{False: w => Array.set(U32, w, 0, 9); sx => v => v}\n', false, function(node)
  local q = vim.treesitter.query.parse('bend2', '(eliminator fallback: (lambda_expression)) @fallback')
  local n = 0
  for _ in q:iter_captures(node, '', 0, -1) do n = n + 1 end
  assert(n == 1, 'explicit Array.set absorbed the next eliminator row')
end)
check('parenthesized write keeps eliminator fallback', 'def f() -> T: \\{False: w => (w[0] <- 9); sx => v => v}\n', false, function(node)
  local q = vim.treesitter.query.parse('bend2', '(eliminator fallback: (lambda_expression)) @fallback')
  local n = 0
  for _ in q:iter_captures(node, '', 0, -1) do n = n + 1 end
  assert(n == 1, 'parenthesized write absorbed the next eliminator row')
end)
assert(#failures == 0, table.concat(failures, '\n'))
print(('Upgrade: %d compatibility checks passed.'):format(count))
vim.cmd('qa!')
