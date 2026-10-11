-- Retained introduced failures: intact callers must survive a bad proof/value.
vim.treesitter.language.add('bend2', { path = vim.env.BEND2_PARSER or 'build/bend2.so' })
local queries = {}
for _, file in ipairs({ 'highlights', 'tags', 'textobjects', 'context', 'folds', 'locals', 'indents' }) do
  queries[file] = vim.treesitter.query.parse('bend2', table.concat(vim.fn.readfile('queries/'..file..'.scm'), '\n'))
end
local function parse(s) return vim.treesitter.get_string_parser(s, 'bend2'):parse()[1]:root() end
local function walk(n, f) f(n); for c in n:iter_children() do walk(c, f) end end
local function field(n, key) local f = n and n:field(key); assert(f and #f == 1, 'lost field '..key); return f[1] end
local function definition(n, s, name)
  for c in n:iter_children() do
    local f = c:field('name')[1]
    if f and c:type():match('_definition$') and vim.treesitter.get_node_text(f, s) == name then return c end
  end
  error('lost declaration '..name)
end
local function sig(n, origin)
  origin = origin or n
  local row, col, byte = origin:start(); local a, ac, ab = n:start(); local b, bc, bb = n:end_()
  local out = { n:type(), ab-byte, bb-byte, a-row, ac-(a==row and col or 0), b-row,
    bc-(b==row and col or 0), n:missing(), n:named(), n:extra() }
  for c, f in n:iter_children() do out[#out+1] = { f or '', sig(c, origin) } end
  return out
end
local function captures(n, s)
  local out = {}; local base = select(3, n:start())
  for file, q in pairs(queries) do
    local rows = {}
    for id, c in q:iter_captures(n, s, 0, -1) do
      rows[#rows+1] = { q.captures[id], c:type(), select(3,c:start())-base, select(3,c:end_())-base }
    end
    table.sort(rows, function(a,b) return vim.json.encode(a)<vim.json.encode(b) end); out[file] = rows
  end
  return out
end
local function pos(s, at)
  local p = s:sub(1, at); local _, row = p:gsub('\n', ''); return row, #p-(p:match('.*\n()') or 1)+1
end
local function exact(n, s, a, b)
  local sr, sc = pos(s, a); local er, ec = pos(s, b)
  assert(n and not n:missing() and select(3,n:start())==a and select(3,n:end_())==b
    and vim.deep_equal({n:range()}, {sr,sc,er,ec}), 'wrong actual range/owner')
end
local specs = {
  { 'next law', 'law b:for v:a=>%$:T;0\nT\nlaw n:T', '$', 'e', 'neighbor' },
  { 'nested proof law body', 'law b:for v:%$:%f:T;0;0\nT', '$', 'e', 'body' },
  { 'outer law body', 'law b:for v:%e:T;v=$;v\nT', '$', '0', 'body' },
  { 'retained rewrite scope', 'def b()->T:%e:T;v=$;v\nlaw n:T', '$', '0', 'scope' },
  { 'successor GPU arguments', 'def b()->T:%e:0n+g-!(x);0', '-', '', 'gpu' },
}
local failures, total = {}, 0
for _, spec in ipairs(specs) do for _, nl in ipairs({ '\n', '\r\n' }) do for _, ending in ipairs({ '', '\n' }) do
  total = total+1
  local broken = (spec[2]..ending):gsub('\n', nl)
  local at = assert(broken:find(spec[3], spec[5]=='gpu' and assert(broken:find('g-',1,true)) or 1, true))-1
  local fixed = broken:sub(1,at)..spec[4]..broken:sub(at+#spec[3]+1)
  local ok, err = pcall(function()
    local clean = parse(fixed); assert(not clean:has_error(), 'invalid exact repair')
    local function unchanged(n, ref)
      assert(not n:has_error() and vim.deep_equal(sig(n),sig(ref)), 'changed healthy CST/fields')
      assert(vim.deep_equal(captures(n,broken),captures(ref,fixed)), 'changed healthy captures')
    end
    local function check(n)
      assert(n:has_error(), 'actual syntax error disappeared')
      if spec[5]=='neighbor' then
        local d = definition(n,broken,'n'); local ref = definition(clean,fixed,'n')
        local a, b = assert(broken:find('law n:T',1,true)); exact(d,broken,a-1,b); unchanged(d,ref)
      elseif spec[5]=='body' then
        local d = definition(n,broken,'b'); local ref = definition(clean,fixed,'b')
        local body = field(d,'body'); local a = assert(broken:find(nl..'T',1,true))+#nl-1
        exact(body,broken,a,a+1); assert(body:parent():id()==d:id(), 'borrowed law body')
        unchanged(body,field(ref,'body')); unchanged(field(d,'name'),field(ref,'name'))
      elseif spec[5]=='scope' then
        local r, ref
        walk(n,function(c) if c:type()=='rewrite_expression' and select(3,c:start())==11 then r=c end end)
        walk(clean,function(c) if c:type()=='rewrite_expression' and select(3,c:start())==11 then ref=c end end)
        assert(r and ref, 'lost rewrite owner')
        exact(r,broken,select(3,ref:start()),select(3,ref:end_()))
        for _, name in ipairs({ 'proof', 'motive' }) do
          unchanged(field(r,name),field(ref,name))
          assert(field(r,name):parent():id()==r:id(), 'borrowed rewrite field')
        end
        local found = false
        for id, c in queries.locals:iter_captures(n,broken,0,-1) do
          if queries.locals.captures[id]=='local.scope' and c:id()==r:id() then found=true end
        end
        assert(found, 'lost actual rewrite local scope')
      else
        local args, ref; local a, b = assert(broken:find('!(x)',1,true))
        walk(n,function(c) if c:type()=='arguments' and select(3,c:start())==a-1 then args=c end end)
        walk(clean,function(c) if c:type()=='arguments' and select(3,c:start())==a-2 then ref=c end end)
        assert(args and ref, 'lost actual GPU arguments'); exact(args,broken,a-1,b); unchanged(args,ref)
        assert(args:parent():type()=='call_expression' and args:parent():field('arguments')[1]:id()==args:id(), 'wrong call owner')
        exact(args:named_child(0),broken,a-1,a+1)
        local closer = args:child(args:child_count()-1); exact(closer,broken,b-1,b)
        assert(closer:type()==')' and closer:parent():id()==args:id(), 'borrowed real closer')
      end
    end
    local fresh = parse(broken); check(fresh)
    -- String parsers check exact EOF; buffers necessarily add a final LF.
    if ending~='' then
      local buf = vim.api.nvim_create_buf(false,true)
      vim.api.nvim_buf_set_lines(buf,0,-1,false,vim.split(fixed:sub(1,-2),'\n',{plain=true}))
      local function bytes() return table.concat(vim.api.nvim_buf_get_lines(buf,0,-1,false),'\n')..'\n' end
      assert(bytes()==fixed, 'wrong initial buffer bytes')
      local parser = vim.treesitter.get_parser(buf,'bend2'); parser:parse()
      local row, col = pos(broken,at)
      for _=1,3 do
        vim.api.nvim_buf_set_text(buf,row,col,row,col+#spec[4],{spec[3]})
        assert(bytes()==broken, 'wrong inserted bytes')
        local n = parser:parse()[1]:root(); check(n)
        assert(vim.deep_equal(sig(n),sig(fresh)) and vim.deep_equal(captures(n,broken),captures(fresh,broken)), 'incremental mismatch')
        vim.api.nvim_buf_set_text(buf,row,col,row,col+#spec[3],{spec[4]})
        assert(bytes()==fixed, 'wrong restored bytes')
        n = parser:parse()[1]:root()
        assert(vim.deep_equal(sig(n),sig(clean)) and vim.deep_equal(captures(n,fixed),captures(clean,fixed)), 'repair mismatch')
      end
      vim.api.nvim_buf_delete(buf,{force=true})
    end
  end)
  local label = spec[1]..' '..(nl=='\n' and 'LF' or 'CRLF')..(ending=='' and ' EOF' or ' final LF')
  print((ok and 'PASS ' or 'FAIL ')..label..(ok and '' or ': '..tostring(err)))
  if not ok then failures[#failures+1]=tostring(err) end
end end end
assert(#failures==0,table.concat(failures,'\n'))
print(('Rewrite recovery: %d strict sources, exact repairs, fields/owners/captures and three minimal edit cycles.'):format(total))
vim.cmd('qa!')
