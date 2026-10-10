local work, side, querydir = assert(arg[1]), assert(arg[2]), assert(arg[3])
vim.treesitter.language.add('bend2', { path = work .. '/' .. side .. '.so' })
local query = vim.treesitter.query.parse('bend2', table.concat(vim.fn.readfile(querydir .. '/highlights.scm'), '\n'))
local cases = vim.json.decode(table.concat(vim.fn.readfile(work .. '/cases.json'), '\n'))
local function measure(source)
  local root = vim.treesitter.get_string_parser(source, 'bend2'):parse()[1]:root()
  local errors, functions = {}, {}
  local function walk(node)
    local sr, sc, sb = node:start()
    local er, ec, eb = node:end_()
    local kind = node:type()
    if kind == 'ERROR' or node:missing() then
      errors[#errors + 1] = { type = kind, missing = node:missing(), sr = sr, sc = sc, er = er, ec = ec, start_byte = sb, end_byte = eb, text = source:sub(sb + 1, eb) }
    end
    if kind == 'function_definition' then
      local bodies = node:field('body')
      functions[#functions + 1] = { sr = sr, er = er, text = source:sub(sb + 1, eb), clean = not node:has_error(), body = bodies[1] and vim.treesitter.get_node_text(bodies[1], source) or false }
    end
    for child in node:iter_children() do walk(child) end
  end
  walk(root)
  local captures = {}
  for id, node, metadata in query:iter_captures(root, source, 0, -1) do
    local sr, sc, sb = node:start()
    local er, ec, eb = node:end_()
    local info = metadata[id] or {}
    captures[#captures + 1] = { name = query.captures[id], sr = sr, sc = sc, er = er, ec = ec, start_byte = sb, end_byte = eb, priority = tonumber(info.priority or metadata.priority) or 100, text = source:sub(sb + 1, eb) }
  end
  local after = false
  for _, fn in ipairs(functions) do
    if fn.text == 'def after() -> U32:\n  42' and fn.clean and fn.body == '42' then after = true end
  end
  return { has_error = root:has_error(), tree = root:sexpr(), errors = errors, captures = captures, functions = functions, after_retained = after }
end
local rows = {}
for _, case in ipairs(cases) do
  local result, repair = measure(case.source), measure(case.repair)
  assert(result.after_retained, case.id .. ': intact after() not retained')
  assert(not repair.has_error and repair.after_retained, case.id .. ': repair not clean')
  assert(result.has_error == (side == 'current'), case.id .. ': unexpected acceptance')
  rows[#rows + 1] = { id = case.id, result = result, repair = repair }
end
vim.fn.writefile({ vim.json.encode(rows) }, work .. '/' .. side .. '-measured.json')
print(side .. ': measured four examples; native errors, following declarations and clean repairs verified')
