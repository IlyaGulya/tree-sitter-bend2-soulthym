# Changelog

## 0.2.0

Bend reference: **v2.0.35**, `79df8d9c40722ee9507a1e253f283b51025f9d6c`.
This is a tagged-release reference, not upstream `main`. Tree-sitter ABI stays 15.

- Support the deep-operator regression in Bend's release tests by compacting
  scanner serialization: up to 200 frames within the fixed 1,024-byte budget.
- Respect the glued compound-type argument boundary introduced in Bend 2.0.32,
  while retaining parenthesized arguments, quantities, ordinary comparisons and
  spaced generic closers. Public array-type nodes may now contain a
  `binary_expression` for glued comparisons.
- Report misplaced whitespace/comments before a declaration's `?` suffix,
  preserving its structure, highlights, folds and tags.
- Keep functions, unaffected fields and all seven query groups' captures intact
  through malformed compound type arguments. Atomic postfix/glued-comparison
  heads also fix the CST precedence of `1 + 2<3`; call/index head schemas narrow
  accordingly (parenthesized functions and expressions remain supported).
- Raise Python's optional Tree-sitter core minimum to 0.25 for ABI 15.
- Make editor usefulness and localized recovery an explicit project policy.
  Add field/capture/locality tests alongside acceptance and incremental tests.
- Add standalone scanner, upgrade, whole-stdlib and release-metadata gates,
  plus selectable old/new parser libraries for upstream comparison reports.
- Validate the entire 3,009-line stdlib with old and new parsers; its recursive
  node types/ranges are unchanged. At the tag, visit all 1,644 `.bend` files:
  1,532 clean parses and 112 reviewed diagnostic rejections, with no rejected
  non-diagnostic fixtures.

See the [complete upstream audit](docs/upgrades/bend-2.0.35.md) and
[recovery policy](docs/recovery-policy.md). Preparing these sources does not
publish a package or imply that dependency-specific binding suites were run.

## 0.1.0

Initial Bend 2.0.29 grammar, serializable layout scanner and seven Neovim
queries; full upstream sweep, editor tests and installation documentation.
Follow-up work added declaration/string recovery and explicit editing tests.
