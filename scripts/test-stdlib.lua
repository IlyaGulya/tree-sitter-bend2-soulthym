-- Parse every Bend source in the standard-library tree, without executing it.
-- BEND2_PARSER selects an old/new compiled library for release comparisons.
local root = vim.env.BEND2_UPSTREAM or (vim.fn.getcwd() .. '/../bend')
local library = vim.env.BEND2_PARSER or (vim.fn.getcwd() .. '/build/bend2.so')
vim.treesitter.language.add('bend2', { path = library })
local files = vim.fn.globpath(root .. '/bend2', '**/*.bend', false, true)
table.sort(files)
assert(#files > 0 and vim.fn.filereadable(root .. '/bend2/base.bend') == 1, 'missing Bend standard library')
local report = { parser = library, upstream = root, files = {} }
for _, file in ipairs(files) do
  local text = table.concat(vim.fn.readfile(file, 'b'), '\n')
  local node = vim.treesitter.get_string_parser(text, 'bend2'):parse()[1]:root()
  assert(not node:has_error(), 'stdlib parse failed: ' .. file)
  local nodes, declarations = {}, { function_definition = 0, type_definition = 0, law_definition = 0 }
  local function visit(n)
    nodes[#nodes + 1] = n:type() .. ':' .. table.concat({ n:range() }, ',')
    for child in n:iter_children() do visit(child) end
  end
  visit(node)
  for child in node:iter_children() do
    if declarations[child:type()] then declarations[child:type()] = declarations[child:type()] + 1 end
  end
  local _, lines = text:gsub('\n', '')
  report.files[#report.files + 1] = {
    file = file:sub(#root + 2), bytes = #text, lines = lines,
    source_sha256 = vim.fn.sha256(text), tree_sha256 = vim.fn.sha256(table.concat(nodes, '\n')),
    declarations = declarations, nodes = #nodes,
  }
  print(('PASS %s: %d lines, %d nodes, %d functions, %d types, %d laws'):format(
    file, lines, #nodes, declarations.function_definition, declarations.type_definition, declarations.law_definition))
end
if vim.env.BEND2_REPORT then
  vim.fn.writefile({ vim.json.encode(report) }, vim.env.BEND2_REPORT)
end
print(('Stdlib: %d/%d files parsed cleanly.'):format(#files, #files))
vim.cmd('qa!')
