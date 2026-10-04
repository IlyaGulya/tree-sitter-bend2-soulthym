# Bend v2.0.35 compatibility audit

## Reference and scope

- Previous parser line: **0.1.0**, compared at `aff57e9`.
- Previous Bend pin: **2.0.29**, `574b6d39a235b539eb19a5c532993a0abb3d11ad`.
  This was the flake-version commit immediately after tag `v2.0.29`.
- New target: **tag `v2.0.35`**, commit
  `79df8d9c40722ee9507a1e253f283b51025f9d6c`.
- Parser version prepared for this target: **0.2.0**, still ABI 15. The minor
  bump reflects revised syntax boundaries, larger supported nesting, and the
  additional possible `binary_expression` in the public array-type CST schema,
  and refined call/index head schemas.

The review covers all **72 upstream commits** and **688 net changed paths**
between the previous pin and the release tag. Every commit's scope and parser
impact is classified below. The language/parser, loader, standard-library and
CLI changes were inspected directly; this is a syntax/tooling audit, not an
independent proof of runtime or kernel correctness. No upstream source was
edited, and no upstream gates, foreign effects, fetches or pushes were run.

The initial checkout was `2bfc83fd`, seven commits beyond the release. It was
also swept, but is **not the reference**. In particular the array-write lowering
fix `653e391b`, revised match diagnostics `a950fd68`, and formatter changes
`f48a8365`/`2bfc83fd` are post-release changes. They are not advertised as new
v2.0.35 syntax. The formatter prompted a check of the *already existing*
adjacency requirement on `def name?`; `parse_def` at the tag confirms it.

## Were there syntax changes?

**Yes: a stricter glued type-argument boundary, not a new language construct.**
In 2.0.32, `parse_term_ops` started explicitly rejecting a glued `<` whose first
operand stops before bare `&`, `|` or `->`. For example `F<A & B>` needs
`F<(A & B)>`. The old grammar already rejected the closed malformed form, but
could accept `F<A & B` as a comparison followed by a type operator. The upgrade
adds an explicit boundary, with positive controls for parenthesized types,
quantities, nested applications, spaced comparisons and boolean comparisons.
Error-locality/tooling checks are required by the [recovery policy](../recovery-policy.md);
rejection alone does not establish an improvement.

Other relevant changes do **not** add source syntax:

- Internal names now use `ns:name`; source names still use dots. Import
  canonicalization and alias resolution changed, not the import-line grammar.
- F32 text rounds once to F32 instead of via F64. Literal spelling is unchanged;
  numerical range/rounding belongs to Bend, not Tree-sitter.
- Conversion, eta equality, sharing, dead fallback arms, template caches,
  quantity diagnostics and match diagnostics are checker/elaboration changes.
- `--safe`, later `--verdict`, `.bendtt` output, `.mjs` output and proof-verdict
  wording concern the CLI/kernel. They are not `.bend` productions.
- `TCP.listen`/`UDP.bind` gained host arguments; `IO.args` changed its result;
  `IO.within`, TCP byte APIs, `Window.grab`, `Look` and `Scroll` were added.
  These are library/API changes, already expressible by the grammar.
- The new deep-operator compiler witness exposed our **existing 100-frame
  scanner limit**, not new Bend syntax. Compact serialization now permits up
  to 200 frames, subject to the same 1,024-byte bound; full-width columns and
  all frame kinds are round-trip tested.

## Old versus upgraded parser

The entire standard-library tree contains one `.bend` source at this tag:
**`bend2/base.bend`**, 3,009 lines / 71,530 bytes. Its source SHA-256 is
`c742fae9c49b14f0cc9128429a2c6109364c8a933a142f2c90b9f2e5fd976661`.
The C/JS files under `bend2/effs` are foreign implementations, not Bend sources.

| Input | Old parser | Upgraded parser |
| --- | --- | --- |
| Entire v2.0.35 stdlib | 1/1 clean | 1/1 clean |
| All 1,644 `.bend` files at v2.0.35 | 1,531 clean / 113 rejected | 1,532 clean / 112 rejected |
| Rejected non-diagnostic fixtures at v2.0.35 | 1 | 0 |
| Initial post-release sweep, before recovery refinement (1,647 files) | 1,534 clean / 113 rejected | 1,535 clean / 112 rejected |

The stdlib retains **389 functions, 22 types and 73 laws**, with **32,072 nodes**.
Old/new recursive node-type/range fingerprints agree:
`6355c29fe75ee6ea1c7f18a39c4562424b775b516273911eb709947541b429eb`.
The tagged and initial post-release stdlibs are byte-identical.

The genuine old-parser failure was `tests/reg/intr_chain_deep.bend` (100 nested
U32 operators and 140 F32 operators). This now parses cleanly. The one addition
to the previous 111-file rejection baseline is
`tests/parse/type_arg_parens.bend`: it intentionally contains the malformed
compound argument and expects a parser error. It was reviewed rather than
whitelisting the valid deep-operator failure. None of the previous baseline
rejections became accepted in the full sweep.

Before implementation changes, regression tests failed on deep nesting,
missing glued-type boundaries, and gaps before unsafe suffixes. A standalone C
scanner test also failed at the old capacity. Positive compatibility controls
and incremental break/repair checks complement these rejection tests. The
later recovery audit additionally tests the edited declaration's fields,
highlights, folds and tags—not merely survival of a following declaration.

Per-file reports and before/after libraries are local artifacts under `build/`.
To repeat comparisons, build the old revision separately and set
`BEND2_PARSER=/absolute/path/to/old.so`; both `scripts/validate-upstream.mjs` and
`scripts/test-stdlib.lua` support that override and `BEND2_REPORT` for the report
path. The sweep takes the checkout as its first argument; the stdlib test uses
`BEND2_UPSTREAM`. Nothing executes a Bend program or resolves its imports.

## Editor-recovery reanalysis

The recovery review accompanying the tagged-release version bump added eleven
targeted editing cases: five gaps before `?` and six malformed compound type arguments.
The suffix cases retained their function, fields, highlights and structural
captures without another grammar change. **Three unfinished-body tests failed**:
`F<A & B`, `F<A | B` and `F<A -> B` turned the entire function into `ERROR`.

The cause was overly broad expression heads on calls, indexes and glued
comparisons: recovery could consume a forbidden operator while waiting for
another postfix token, then discard the declaration. Atomic heads remove that
path. The same failing tests now preserve `function_definition`, intact fields
and all seven query groups' captures. Errors stay inside the damaged field:
unfinished bodies recover with a native missing `>`; closed malformed parameter
types retain a localized `ERROR`. No permissive exception or custom fake error
node was needed. Each test breaks and repairs twice using minimal buffer edits.

Thirteen additional controls cover arithmetic/glued-comparison operand ownership,
postfix calls/indexes, parenthesized heads and unrestricted later type arguments.
They also caught the old incorrect grouping of `1 + 2<3`; the corrected tree is
`1 + (2<3)`, verified against the tagged `Bend.parse_term` without executing a
program. The upgrade suite now has **53** checks; recovery has **35** locality/
highlight scenarios plus **seven** explicitly weaker match repair/consistency
probes. Capture preservation is not a claim that every plugin's UI behavior was
exercised for every malformed input. Damaged matches and later-quote string
ambiguity remain documented limitations.

## Commit-by-commit impact ledger

“None” means no new `.bend` grammar requirement, not that the upstream change
is unimportant. Added/modified Bend witnesses are included in the full sweep.

| Commit | Change and syntax/tooling assessment |
| --- | --- |
| `a0107463` | Kernel-backed `--safe`, Base Array/Map recursion rewrites; existing syntax. |
| `27dc2f69` | BendTT kernel replaces old Lean file, full J and `.bendtt` emission; none. |
| `56330b24` | 2.0.30 release metadata/docs; none. |
| `58e5a8ac` | Flake version 2.0.30; none. |
| `1e80ddce` | 2.0.31, aligned CLI help; none. |
| `af569d48` | Flake version 2.0.31; none. |
| `4eb344b6` | Unified verdict output and diagnostic golden updates; comment/output changes. |
| `84a16cf3` | Rename to `--verdict` and `ALL PROOFS CHECK`; no source keywords. |
| `573002f0` | 2.0.32: glued type-argument guard; API, rounding, loader, checker and runtime fixes described above. |
| `4f856f61` | Flake version 2.0.32; none. |
| `d2066a52` | Compiler simplification; none. |
| `b2111cf4` | Base destructures before copying; existing patterns/quantities. |
| `d850e053` | Film sources/assets; none. |
| `d871e1eb` | Word/nullary-constructor emission optimization; none. |
| `a0627e0a` | Shared effect result macro; foreign implementation only. |
| `35b71e37` | Zero-length TCP receive returns EINVAL; runtime behavior, same syntax. |
| `6de56b97` | Base helper simplification and U32.log2 optimization; existing syntax. |
| `ef66a7cc` | Shared-array redirect race fix; runtime only. |
| `c97ebd53` | Widen U32.to_nat in C; runtime numeric correctness. |
| `5d13d179` | Film title sizing; none. |
| `cb029ebe` | README update; none. |
| `0ce83552` | Film scene/text update; none. |
| `713349fa` | Film transitions; none. |
| `5ccc6431` | Film label; none. |
| `f3332e4f` | Film C slide; none. |
| `79748bce` | Film aspect ratio; none. |
| `44d40264` | Film timing/layout; none. |
| `e41fa7b8` | Ignore foreign CID names inside C comments/strings; not Bend lexing. |
| `685726e5` | Compiler/effect refactoring; none. |
| `7bb78dcb` | Key display descriptors by layout; runtime only. |
| `839ff9c8` | Share compiler graph traversal; none. |
| `3378e623` | Kernel annotates lambda argument domain; proof-checking only. |
| `c05efd95` | 2.0.33 rigid-first conversion; semantics, unchanged equality syntax. |
| `ed4ec4e6` | Flake version 2.0.33; none. |
| `7d8a3eb0` | 2.0.34 share-cell conversion; semantics, no grammar change. |
| `777ee0b5` | Flake version 2.0.34; none. |
| `3ffc1f90` | CPU task-column allocation; runtime only. |
| `68f870e3` | Publisher strips leading BOM; packaging, not a new source token. |
| `eb8f58b1` | Elaborate matches at checked goals; kernel boundary only. |
| `dfeb0c59` | Kernel proof simplification; none. |
| `01875127` | Elaborate specialized arguments at each use; none. |
| `1adb0a61` | Empty-datatype eliminator in BendTT; existing Bend syntax. |
| `7d24b8d0` | Reject incompatible CLI publishing/verdict flags; none. |
| `0070d08f` | Compiler simplification; none. |
| `a1f759fc` | Ansible cluster gates; none; not executed. |
| `43513c48` | Gate allowlist; none. |
| `babf4c71` | Avoid expanding shared display layouts; none. |
| `cdfd21c2` | Spill deeply nested C operands; witness exposed our scanner capacity gap. |
| `607a095a` | More specific scrutinee diagnostic; unchanged match grammar. |
| `f370026f` | Internal `ns:name` keys, matching foreign IDs; source remains dotted. |
| `70df9250` | Preserve CLI exit status on EPIPE; none. |
| `675381e7` | Uppercase names in test gate; none. |
| `f2cc47cd` | Timer/deadline fairness under busy computation; runtime only. |
| `6ef615a8` | Elaborate dead default arms to BendTT; existing eliminators. |
| `0443100f` | C output works at -O0; none. |
| `281494cc` | Elaborator spine-walk simplification; none. |
| `57b6c150` | Replace cluster gate transport; none; not executed. |
| `fb6f32a8` | Task-column/ring scheduling changes; runtime only. |
| `d0fda2f7` | Shared constructor layout optimization; none. |
| `e1ed2435` | Resolve BendTT recursive groups; none. |
| `43efc780` | Restore M1/M2 Metal compilation; none. |
| `7facb8e3` | Template cache uses Map; unchanged `~` syntax. |
| `22ad9dc8` | Native division/remainder paths; unchanged operators. |
| `d04cf05e` | Histogram benchmark; all Bend source uses existing syntax. |
| `fddefd4c` | Compile equality-proof arrays; existing array/equality syntax. |
| `75cc3602` | Compiler simplification; none. |
| `25dc99a7` | Bound kernel model search; none. |
| `ee8a156e` | Reject empty token counts in repo gate; none. |
| `39f41011` | Compiler simplification/token cap; none. |
| `947db722` | JS random failure becomes Result; foreign/runtime behavior. |
| `5e56772e` | Release borrowed variable across spin/jump; runtime ownership. |
| `79df8d9c` | 2.0.35 release metadata; selected tag/commit. |

## Validation boundaries

The final installed-tool offline gate passed: 41 corpus tests, scanner tests,
53 upgrade checks, 35 recovery scenarios plus seven match repair probes, seven
Neovim queries/180 edits, 11 documentation snippets, the whole stdlib, all 1,644
upstream files and release-metadata checks. Strict C compilation and a CMake
shared-library build passed. The npm pack dry-run includes generated sources,
all seven queries, the declared MIT license, changelog and documentation.

The parser tests exercise syntax and Neovim tooling, not the compiler's runtime,
GPU or Lean gates. The Node binding suite was attempted but could not start:
its `tree-sitter` package is not installed. Python's core package and Go/Swift
tools are absent; the Rust binding suite was not run. These optional binding
suites are **not claimed to pass**. No dependencies were installed, and no
remote operations or publishing were performed.
