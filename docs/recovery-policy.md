# Error-tolerant editor parsing policy

This is an editor parser, not a compiler gate. **Maximize useful structure and
keep tooling working through incomplete or mistaken code, while reporting
localized syntax errors wherever possible.** Apply this policy to grammar,
scanner, query, language-upgrade and recovery changes—not just known examples.

## Priorities

1. Parse valid Bend accurately, against a pinned **release tag and commit**.
   Do not track upstream `main` as the language reference. New upstream commits
   are review material, not automatically the target language.
2. On malformed input, prefer a useful partial tree with native Tree-sitter
   `ERROR`/`MISSING` nodes to either swallowing surrounding code or pretending
   the mistake is valid syntax.
3. Preserve all unambiguous structure: the edited declaration's name, parameters,
   return type and unaffected body; intact siblings and following declarations;
   and their highlight, fold, tag, context and textobject captures as applicable.
   A syntax error must not automatically invalidate every editor feature on its
   enclosing declaration.
4. Keep errors as local as practical. Continue parsing beyond them, and restore
   the normal tree and captures when the edit is repaired. Scanner state must
   remain bounded, serializable and consistent under incremental edits.

Bend remains authoritative for typing, binding, elaboration and runtime validity.
A clean syntax tree is not a claim that a program compiles. Likewise, an error
node is not a reason for consumers to discard the rest of a useful tree.

## Tightening syntax requires an editor-quality gate

Compiler rejection alone does **not** justify tightening the grammar. Before
changing permissive behavior:

- Record the current tree and captures for valid, mistyped and partially typed
  variants. Compare the proposed parser on the same input.
- Add a regression test for each identified failure and demonstrate it failing
  before the fix. Keep positive controls for valid lookalikes.
- Assert error detection **and** the useful nodes/ranges/fields/captures that
  must survive. Test the edited construct, not only a later clean function.
- Test neighboring declarations and realistic buffer edits followed by repairs.
  Compare recursive node types/ranges with fresh parses. Equality alone is not
  a recovery-quality test: two equally bad trees can agree.
- Re-run corpus, scanner, query, recovery and compatibility tests, plus the
  entire tagged standard library and full upstream `.bend` sweep.
- Do not rewrite expectations merely to bless a worse tree. Correct tests only
  for demonstrated fixture mistakes or deliberate API/schema changes, explaining
  why; do not turn a locality test into a consistency-only test to make it pass.

If stricter recognition degrades useful recovery, improve recovery first or
retain the existing tolerant behavior pending that fix. Any permissive exception
must be explicit: document its scope, why it helps editing, the diagnostic left
to Bend/the LSP, and the missing recovery work. Do not silently broaden the
claimed language or count such an exception as a successful error-detection test.

## Concrete examples

- `def value ?(x: U32) -> U32: x` is invalid Bend because the suffix must touch
  the name. The desired editor result is still a `function_definition`, with
  intact fields and captures and an error confined to the misplaced suffix.
  Space, tab, newline, CRLF and comment variants need break/repair tests.
- A malformed type argument should not destroy the enclosing declaration or
  unrelated parameters/body. Test the surviving structure as well as rejection.
- An unfinished string should not unnecessarily consume the rest of the file,
  but valid Bend multiline strings must remain valid. A later quote can be a
  genuine closer; do not reinterpret valid text just because it resembles code.
- Missing call/constructor closers in a match arm must retain same-column
  sibling `case_clause` nodes, fields and editor captures, with native errors
  confined away from the intact arms. Nested matches must keep the correct
  inner/outer owner; case-looking text inside valid strings is not a boundary.
  Other damaged-arm forms remain coarse: consistency/repair tests alone do not
  establish preservation of the following arms' highlighting.

## Honest reporting

Distinguish acceptance/rejection, error locality, retained tooling captures,
incremental consistency, and repair. Report measured guarantees and known limits
separately; do not imply tolerance for every malformed byte sequence. Keep
recovery limitations visible in the README and add focused tests as they improve.

See [`scripts/test-recovery.lua`](../scripts/test-recovery.lua) for locality,
highlight, field, structural-query and break/repair checks, and
[`scripts/test-upgrade.lua`](../scripts/test-upgrade.lua) for release compatibility
and incremental checks. The two suites complement, not replace, one another.
