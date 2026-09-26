#include "tree_sitter/parser.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Order must match grammar.js. Layout is Bend's case-column / do-continuation
// rule, not Python indentation. All state is serialized for incremental parsing.
enum Token {
  FUNCTION_START, BLOCK_START, BODY_END, LAMBDA_START, MATCH_START, MATCH_END, CASE,
  DO_START, DO_END, DO_MORE, CALL_OPEN, INDEX_OPEN,
  PLUS, MINUS, GT, GE, SHR, MOD, PARALLEL, PARALLEL_START, PARALLEL_VALUE, PARALLEL_END,
  WRITE_START, WRITE_MORE, WRITE_END, IMPORT_START, IMPORT_END, INTEGER, NATURAL, FLOAT, ERROR_SENTINEL,
};
enum Kind { BODY, MATCH, DO, PAR, LAMBDA, WRITE };
typedef struct { uint32_t column, first; uint8_t kind; } Frame;
#define MAX_FRAMES 100
_Static_assert(1 + 9 * MAX_FRAMES <= TREE_SITTER_SERIALIZATION_BUFFER_SIZE,
               "scanner state must fit Tree-sitter's serialization buffer");
typedef struct { uint8_t size; Frame frames[MAX_FRAMES]; } Scanner;

static bool space(int32_t c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }
static bool head(int32_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
static bool name(int32_t c) { return head(c) || (c >= '0' && c <= '9') || c == '.'; }
static void advance(TSLexer *l) { l->advance(l, false); }
// Bend speculatively reads `: T` and rewinds unless it is followed by `=`.
// At a lambda boundary the colon can instead belong to an enclosing annotation.
static bool typed_assignment(TSLexer *l) {
  unsigned depth = 0;
  advance(l); // colon
  while (!l->eof(l)) {
    int32_t c = l->lookahead;
    if (c == '"' || c == '\'') {
      advance(l);
      while (!l->eof(l) && l->lookahead != c) {
        if (l->lookahead == '\\') advance(l);
        if (!l->eof(l)) advance(l);
      }
      if (!l->eof(l)) advance(l);
      continue;
    }
    if (c == '#') {
      while (!l->eof(l) && l->lookahead != '\n') advance(l);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') ++depth;
    if (c == ')' || c == ']' || c == '}') {
      if (!depth) return false;
      --depth;
    }
    if (!depth && c == ';') return false;
    advance(l);
    if (!depth && c == '=') {
      if (l->lookahead != '=' && l->lookahead != '>') return true;
      advance(l);
    }
  }
  return false;
}
static bool push(Scanner *s, uint8_t kind, uint32_t column) {
  if (s->size == MAX_FRAMES) return false;
  s->frames[s->size++] = (Frame){column, UINT32_MAX, kind};
  return true;
}
static uint32_t body_column(const Scanner *s) {
  for (unsigned i = s->size; i; --i)
    if (s->frames[i-1].kind == BODY || s->frames[i-1].kind == LAMBDA) return s->frames[i-1].column;
  return 0;
}
void *tree_sitter_bend2_external_scanner_create(void) { return calloc(1, sizeof(Scanner)); }
void tree_sitter_bend2_external_scanner_destroy(void *p) { free(p); }
unsigned tree_sitter_bend2_external_scanner_serialize(void *p, char *b) {
  Scanner *s = p;
  unsigned n = 0;
  b[n++] = (char)s->size;
  for (unsigned i = 0; i < s->size; ++i) {
    Frame f = s->frames[i];
    b[n++] = (char)f.kind;
    for (unsigned j = 0; j < 4; ++j) b[n++] = (char)(f.column >> (8*j));
    for (unsigned j = 0; j < 4; ++j) b[n++] = (char)(f.first >> (8*j));
  }
  return n;
}
void tree_sitter_bend2_external_scanner_deserialize(void *p, const char *b, unsigned n) {
  Scanner *s = p;
  s->size = 0;
  if (!n || (uint8_t)b[0] > MAX_FRAMES || n != 1u + 9u*(uint8_t)b[0]) return;
  s->size = (uint8_t)b[0];
  unsigned at = 1;
  for (unsigned i = 0; i < s->size; ++i) {
    Frame *f = &s->frames[i];
    f->kind = (uint8_t)b[at++]; f->column = f->first = 0;
    for (unsigned j = 0; j < 4; ++j) f->column |= (uint32_t)(uint8_t)b[at++] << (8*j);
    for (unsigned j = 0; j < 4; ++j) f->first |= (uint32_t)(uint8_t)b[at++] << (8*j);
  }
}
bool tree_sitter_bend2_external_scanner_scan(void *p, TSLexer *l, const bool *v) {
  Scanner *s = p;
  if (v[ERROR_SENTINEL]) return false;
  l->mark_end(l); // Zero-width layout tokens must not include following whitespace.
  bool newline = l->get_column(l) == 0, spaced = false;
  while (space(l->lookahead)) {
    newline |= l->lookahead == '\n'; spaced = true; l->advance(l, true);
  }
  if (l->lookahead == '#') return false; // Let the grammar retain comment nodes.
  uint32_t col = l->get_column(l);
  Frame *top = s->size ? &s->frames[s->size-1] : NULL;
  if (v[IMPORT_END]) {
    if (!newline && !l->eof(l)) return false;
    l->result_symbol = IMPORT_END; return true;
  }
  if (v[IMPORT_START]) {
    if (!newline || l->lookahead != 'i') return false;
    l->mark_end(l);
    const char *word = "import";
    for (unsigned i = 0; word[i]; ++i) {
      if (l->lookahead != word[i]) return false;
      advance(l);
    }
    if (!space(l->lookahead)) return false;
    l->result_symbol = IMPORT_START; return true;
  }
  if (!newline && ((v[CALL_OPEN] && l->lookahead == '(') || (v[INDEX_OPEN] && l->lookahead == '['))) {
    l->result_symbol = l->lookahead == '(' ? CALL_OPEN : INDEX_OPEN;
    advance(l); l->mark_end(l); return true;
  }
  if (v[FUNCTION_START] || v[BLOCK_START] || v[LAMBDA_START] || v[DO_START]) {
    if (v[CALL_OPEN] && l->lookahead && strchr("&|*/.<", l->lookahead)) return false;
    if (head(l->lookahead)) {
      char word[32]; unsigned n = 0;
      while (name(l->lookahead)) {
        if (n < sizeof(word)-1) word[n++] = (char)l->lookahead;
        advance(l);
      }
      word[n] = 0;
      if (!strcmp(word, "for") || !strcmp(word, "exs") || !strcmp(word, "import") || !strcmp(word, "where")) return false;
    } else if (l->lookahead == '-') {
      advance(l);
      if (l->lookahead == '>') return false;
    } else if (!strchr("+@&\\\\%{(['\"?", l->lookahead) && !(l->lookahead >= '0' && l->lookahead <= '9')) {
      return false;
    }
    enum Token t = v[FUNCTION_START] ? FUNCTION_START : v[BLOCK_START] ? BLOCK_START : v[LAMBDA_START] ? LAMBDA_START : DO_START;
    if (!push(s, t == DO_START ? DO : t == LAMBDA_START ? LAMBDA : BODY, t == FUNCTION_START ? 0 : col)) return false;
    l->result_symbol = t; return true;
  }
  if (v[WRITE_START] && head(l->lookahead)) {
    l->mark_end(l);
    while (name(l->lookahead)) advance(l);
    while (l->lookahead == ' ' || l->lookahead == '\t' || l->lookahead == '\r') advance(l);
    if (l->lookahead != '[') return false;
    unsigned depth = 1; advance(l);
    while (depth && !l->eof(l)) {
      if (l->lookahead == '\'' || l->lookahead == '"') {
        int32_t quote = l->lookahead; advance(l);
        while (!l->eof(l) && l->lookahead != quote) {
          if (l->lookahead == '\\') advance(l);
          if (!l->eof(l)) advance(l);
        }
        if (!l->eof(l)) advance(l);
      } else if (l->lookahead == '#') {
        while (!l->eof(l) && l->lookahead != '\n') advance(l);
      } else {
        if (l->lookahead == '[') ++depth;
        if (l->lookahead == ']') --depth;
        advance(l);
      }
    }
    while (l->lookahead == ' ' || l->lookahead == '\t' || l->lookahead == '\r') advance(l);
    if (l->lookahead != '<') return false;
    advance(l);
    if (l->lookahead != '-') return false;
    if (!push(s, WRITE, col)) return false;
    l->result_symbol = WRITE_START; return true;
  }
  if (v[MATCH_START]) {
    if (!push(s, MATCH, body_column(s))) return false;
    l->result_symbol = MATCH_START; return true;
  }
  if ((v[CASE] || v[MATCH_END]) && top && top->kind == MATCH) {
    // A case owns its keyword, not the whitespace after the previous body.
    // MATCH_END must instead remain at the previous body's end.
    if (v[CASE] && col >= top->column && (top->first == UINT32_MAX || col >= top->first) && l->lookahead == 'c') l->mark_end(l);
    bool is_case = true;
    const char *word = "case";
    for (unsigned i = 0; i < 4; ++i) {
      if (l->lookahead != word[i]) { is_case = false; break; }
      advance(l);
    }
    is_case &= !name(l->lookahead);
    bool eligible = is_case && col >= top->column && (top->first == UINT32_MAX || col >= top->first);
    if (eligible && v[CASE]) {
      if (!push(s, BODY, col + 1)) return false;
      top->first = top->first == UINT32_MAX ? col : top->first;
      l->result_symbol = CASE; return true;
    }
    if (!eligible && v[MATCH_END]) {
      --s->size; l->result_symbol = MATCH_END; return true;
    }
    return false;
  }
  if (v[WRITE_MORE] && top && top->kind == WRITE && col == top->column && !l->eof(l)) {
    l->result_symbol = WRITE_MORE; return true;
  }
  if (v[DO_MORE] && top && top->kind == DO && col == top->column && !l->eof(l)) {
    l->result_symbol = DO_MORE; return true;
  }
  if ((v[PARALLEL] || v[PARALLEL_START]) && !newline && (head(l->lookahead) || (spaced && l->lookahead == '+'))) {
    if (l->lookahead == '+') {
      advance(l);
      if (!head(l->lookahead)) {
        if (v[PLUS] && l->lookahead != '+' && l->lookahead != '>') {
          l->mark_end(l); l->result_symbol = PLUS; return true;
        }
        return false;
      }
    }
    char word[32]; unsigned n = 0;
    while (name(l->lookahead)) {
      if (n < sizeof(word)-1) word[n++] = (char)l->lookahead;
      advance(l);
    }
    word[n] = 0;
    const char *reserved[] = {"def", "type", "law", "match", "case", "do", "return", "for", "exs", "where", "is", "import", "Type", "Data", "Kind", "Quant"};
    bool keyword = false;
    for (unsigned i = 0; i < sizeof(reserved)/sizeof(*reserved); ++i) keyword |= !strcmp(word, reserved[i]);
    if (!keyword) {
      if (v[PARALLEL_START]) {
        if (!push(s, PAR, 2)) return false;
        l->result_symbol = PARALLEL_START;
      } else {
        if (!top || top->kind != PAR) return false;
        ++top->column; l->result_symbol = PARALLEL;
      }
      return true;
    }
    if (v[BODY_END] && top && (top->kind == BODY || top->kind == LAMBDA)) {
      --s->size; l->result_symbol = BODY_END; return true;
    }
    return false;
  }
  if ((v[PLUS] && l->lookahead == '+') || (v[MINUS] && l->lookahead == '-')) {
    enum Token t = l->lookahead == '+' ? PLUS : MINUS;
    advance(l);
    if (head(l->lookahead)) {
      if (v[PARALLEL_END] && top && top->kind == PAR && !top->column) {
        --s->size; l->result_symbol = PARALLEL_END; return true;
      }
      if (spaced && top) {
        if (v[DO_END] && top->kind == DO) {
          --s->size; l->result_symbol = DO_END; return true;
        }
        if (v[BODY_END] && (top->kind == BODY || top->kind == LAMBDA)) {
          --s->size; l->result_symbol = BODY_END; return true;
        }
      }
      return false;
    }
    if (l->lookahead == '>' || (t == PLUS && l->lookahead == '+')) return false;
    l->mark_end(l); l->result_symbol = t; return true;
  }
  if (spaced && l->lookahead == '>' && (v[GT] || v[GE] || v[SHR])) {
    advance(l);
    enum Token t = GT;
    if (l->lookahead == '=') { t = GE; advance(l); }
    else if (l->lookahead == '>') { t = SHR; advance(l); }
    if (!v[t]) return false;
    l->mark_end(l); l->result_symbol = t; return true;
  }
  if (v[MOD] && l->lookahead == '%') {
    advance(l);
    if (!space(l->lookahead)) return false;
    l->mark_end(l); l->result_symbol = MOD; return true;
  }
  if (l->lookahead == ';' && (v[DO_MORE] || v[WRITE_MORE])) return false;
  if (l->lookahead == ':' && v[BODY_END] && top && top->kind == LAMBDA) {
    if (typed_assignment(l)) return false;
    --s->size; l->result_symbol = BODY_END; return true;
  }
  if (v[CALL_OPEN] && l->lookahead && (strchr("<|&*/.!=:", l->lookahead) || (!spaced && l->lookahead == '{'))) return false;
  if (v[PARALLEL_VALUE] && top && top->kind == PAR && top->column) {
    --top->column; l->result_symbol = PARALLEL_VALUE; return true;
  }
  if ((v[INTEGER] || v[NATURAL] || v[FLOAT]) && l->lookahead >= '0' && l->lookahead <= '9') {
    do { advance(l); } while (l->lookahead >= '0' && l->lookahead <= '9');
    enum Token t = INTEGER;
    if (l->lookahead == 'n') { t = NATURAL; advance(l); }
    else if (l->lookahead == '.') {
      advance(l);
      if (l->lookahead < '0' || l->lookahead > '9') return false;
      t = FLOAT;
      do { advance(l); } while (l->lookahead >= '0' && l->lookahead <= '9');
      l->mark_end(l);
      if (l->lookahead == 'e' || l->lookahead == 'E') {
        advance(l);
        if (l->lookahead == '+' || l->lookahead == '-') advance(l);
        if (l->lookahead < '0' || l->lookahead > '9') {
          if (!v[FLOAT]) return false;
          l->result_symbol = FLOAT; return true;
        }
        do { advance(l); } while (l->lookahead >= '0' && l->lookahead <= '9');
      }
    }
    if (!v[t] || (t != FLOAT && name(l->lookahead))) return false;
    l->mark_end(l); l->result_symbol = t; return true;
  }
  // Give ordinary grammar tokens a chance to extend the current expression.
  if (strchr("<{|&*/.!=:", l->lookahead) && l->lookahead) return false;
  if (v[PARALLEL_END] && top && top->kind == PAR && !top->column) {
    --s->size; l->result_symbol = PARALLEL_END; return true;
  }
  if (v[BODY_END] && top && (top->kind == BODY || top->kind == LAMBDA)) {
    --s->size; l->result_symbol = BODY_END; return true;
  }
  if (v[WRITE_END] && top && top->kind == WRITE) {
    --s->size; l->result_symbol = WRITE_END; return true;
  }
  if (v[DO_END] && top && top->kind == DO) {
    --s->size; l->result_symbol = DO_END; return true;
  }
  return false;
}
