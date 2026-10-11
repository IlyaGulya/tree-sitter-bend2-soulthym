// Standalone serialization/bounds regression; no Tree-sitter runtime needed.
#include <assert.h>
#include <stdio.h>
#include "../src/scanner.c"

static void round_trip(Scanner *s) {
  char buffer[TREE_SITTER_SERIALIZATION_BUFFER_SIZE + 16];
  memset(buffer, 0x5a, sizeof(buffer));
  unsigned n = tree_sitter_bend2_external_scanner_serialize(s, buffer);
  assert(n <= TREE_SITTER_SERIALIZATION_BUFFER_SIZE);
  for (unsigned i = n; i < sizeof(buffer); ++i) assert(buffer[i] == 0x5a);
  Scanner restored = {0};
  tree_sitter_bend2_external_scanner_deserialize(&restored, buffer, n);
  assert(restored.size == s->size);
  assert(restored.declaration_name == s->declaration_name);
  assert(restored.closed_string == s->closed_string);
  assert(restored.decorator_name == s->decorator_name);
  for (unsigned i = 0; i < s->size; ++i) {
    assert(restored.frames[i].kind == s->frames[i].kind);
    assert(restored.frames[i].column == s->frames[i].column);
    assert(restored.frames[i].first == s->frames[i].first);
  }
  char again[TREE_SITTER_SERIALIZATION_BUFFER_SIZE];
  assert(tree_sitter_bend2_external_scanner_serialize(&restored, again) == n);
  assert(memcmp(buffer, again, n) == 0);
  for (unsigned length = 0; length < n; ++length) {
    tree_sitter_bend2_external_scanner_deserialize(&restored, buffer, length);
    assert(restored.size == 0);
  }
}
// Mock lexer for grammar-owned, zero-width phase transitions.
typedef struct { TSLexer lexer; const char *text; unsigned at, end; } Probe;
static void probe_advance(TSLexer *l, bool skip) {
  (void)skip; Probe *p = (Probe *)l;
  if (p->text[p->at]) ++p->at;
  l->lookahead = p->text[p->at];
}
static void probe_mark(TSLexer *l) { Probe *p = (Probe *)l; p->end = p->at; }
static uint32_t probe_column(TSLexer *l) { return ((Probe *)l)->at; }
static bool probe_eof(const TSLexer *l) { return !l->lookahead; }
static Probe probe(const char *text) {
  return (Probe){.text = text, .lexer = {.lookahead = text[0], .advance = probe_advance,
    .mark_end = probe_mark, .get_column = probe_column, .eof = probe_eof}};
}
static void checkpoint_tests(void) {
  bool v[ARRAY_TYPE_END + 1] = {0}; v[BODY_ENTRY] = true;
  for (unsigned phase = PAR; phase <= PAR_HEADER; phase += PAR_HEADER - PAR) {
    Scanner s = {0}; assert(push(&s, BODY, 0) && push(&s, phase, 2));
    Probe p = probe("Type");
    assert(tree_sitter_bend2_external_scanner_scan(&s, &p.lexer, v));
    assert(p.lexer.result_symbol == BODY_ENTRY && p.end == 0 && p.at == 0);
    assert(s.size == (phase == PAR_HEADER ? 1 : 2));
    round_trip(&s);
    for (unsigned i = 0; i < 300; ++i) {
      p = probe("Type"); assert(tree_sitter_bend2_external_scanner_scan(&s, &p.lexer, v));
      assert(s.size == (phase == PAR_HEADER ? 1 : 2));
      assert(s.frames[0].kind == BODY && s.frames[0].column == 0 && s.frames[0].first == UINT32_MAX);
      if (phase == PAR) assert(s.frames[1].kind == PAR && s.frames[1].column == 2 && s.frames[1].first == UINT32_MAX);
      assert(!s.declaration_name && !s.closed_string && !s.decorator_name);
      round_trip(&s);
    }
  }
  // Live value phases retain the full serialized payload, including flags.
  for (unsigned flags = 0; flags < 8; ++flags) {
    for (unsigned i = 0; i < 3; ++i) {
      uint32_t counts[] = {0, 1, UINT32_MAX};
      Scanner s = {.declaration_name = flags & 1, .decorator_name = flags & 2, .closed_string = flags & 4};
      assert(push(&s, BODY, 7) && push(&s, PAR, counts[i]));
      char before[TREE_SITTER_SERIALIZATION_BUFFER_SIZE], after[TREE_SITTER_SERIALIZATION_BUFFER_SIZE];
      unsigned n = tree_sitter_bend2_external_scanner_serialize(&s, before);
      Probe p = probe("Type");
      assert(tree_sitter_bend2_external_scanner_scan(&s, &p.lexer, v));
      assert(p.lexer.result_symbol == BODY_ENTRY && p.at == 0 && p.end == 0);
      assert(tree_sitter_bend2_external_scanner_serialize(&s, after) == n && !memcmp(before, after, n));
      round_trip(&s);
    }
  }
  Scanner s = {0}; assert(push(&s, BODY, 0) && push(&s, PAR_HEADER, 2));
  v[ERROR_SENTINEL] = true; Probe p = probe("Type");
  assert(!tree_sitter_bend2_external_scanner_scan(&s, &p.lexer, v));
  assert(s.size == 2 && s.frames[1].kind == PAR_HEADER); round_trip(&s);
  v[ERROR_SENTINEL] = false;
  for (unsigned literal = 0; literal < 2; ++literal) {
    s = (Scanner){0}; assert(push(&s, BODY, 0) && push(&s, PAR_HEADER, 2));
    p = probe(literal ? "\"s\"" : "Type");
    assert(tree_sitter_bend2_external_scanner_scan(&s, &p.lexer, v));
    assert(p.lexer.result_symbol == BODY_ENTRY && p.end == 0 && s.size == 1);
    char state[TREE_SITTER_SERIALIZATION_BUFFER_SIZE];
    unsigned bytes = tree_sitter_bend2_external_scanner_serialize(&s, state);
    Scanner restored = {0}; tree_sitter_bend2_external_scanner_deserialize(&restored, state, bytes);
    bool terms[ARRAY_TYPE_END + 1] = {0}; terms[WRITE_START] = terms[IDENTIFIER] = terms[STRING_START] = true;
    p = probe(literal ? "\"s\"" : "Type");
    bool ok = tree_sitter_bend2_external_scanner_scan(&restored, &p.lexer, terms);
    assert(ok == (literal != 0));
    if (ok) assert(p.lexer.result_symbol == STRING_START && p.end == 1);
    assert(restored.size == 1 && restored.frames[0].kind == BODY); round_trip(&restored);
  }
  puts("BODY_ENTRY: zero-width, only stale header retired, actual values retained, error-mode inert, 300 entries bounded, phase persists before string/builtin lexing.");
}
int main(void) {
  checkpoint_tests();
  Scanner s = {0};
  s.declaration_name = s.closed_string = s.decorator_name = true;
  for (unsigned i = 0; i < 200; ++i) {
    assert(push(&s, BODY, UINT32_MAX - i));
    round_trip(&s);
  }
  assert(!push(&s, BODY, 0));
  round_trip(&s);
  for (unsigned kind = BODY; kind <= MATCH_CLOSED_ARM; ++kind) {
    memset(&s, 0, sizeof(s));
    while (push(&s, kind, UINT32_MAX)) {
      if (kind == MATCH || kind == MATCH_CLOSED_ARM)
        s.frames[s.size - 1].first = s.size % 2 ? UINT32_MAX : 70000;
      round_trip(&s);
    }
    assert(s.size >= 100);
    round_trip(&s);
  }
  for (unsigned flags = 0; flags < 8; ++flags) {
    memset(&s, 0, sizeof(s));
    s.declaration_name = flags & 1;
    s.decorator_name = flags & 2;
    s.closed_string = flags & 4;
    assert(push(&s, CASE_HEADER, 7) && push(&s, BLOCK, 9));
    round_trip(&s);
  }
  char invalid[] = {1, 3, 1, MATCH_CLOSED_ARM + 1, 0, 0, 0, 0};
  tree_sitter_bend2_external_scanner_deserialize(&s, invalid, sizeof(invalid));
  assert(!s.size && !s.declaration_name && !s.decorator_name && !s.closed_string);
  invalid[0] = 0; invalid[1] = 4;
  tree_sitter_bend2_external_scanner_deserialize(&s, invalid, 3);
  assert(!s.size && !s.declaration_name && !s.decorator_name && !s.closed_string);
  puts("Scanner: deep stacks, all frame kinds/flags, full-width columns, bounded serialization and truncated states passed.");
}
