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
int main(void) {
  Scanner s = {0};
  s.declaration_name = s.closed_string = true;
  for (unsigned i = 0; i < 200; ++i) {
    assert(push(&s, BODY, UINT32_MAX - i));
    round_trip(&s);
  }
  assert(!push(&s, BODY, 0));
  round_trip(&s);
  for (unsigned kind = BODY; kind <= MATCH_CLOSED_ARM; ++kind) {
    memset(&s, 0, sizeof(s));
    while (push(&s, kind, UINT32_MAX)) {
      if (match_frame(kind)) s.frames[s.size - 1].first = s.size % 2 ? UINT32_MAX : 70000;
      round_trip(&s);
    }
    assert(s.size >= 100);
    round_trip(&s);
  }
  puts("Scanner: deep stacks, all frame kinds, full-width columns, bounded serialization and truncated states passed.");
}
