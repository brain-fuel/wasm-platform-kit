# Rust Grammar

This grammar is based on official language reference
at https://doc.rust-lang.org/reference/.

## Reference
* [pldb](http://pldb.info/concepts/rust)


## License
MIT

## Comments
Last updated for rust v1.60.0.

## Known limitations
- Only v2018+ stable feature is implemented.
- Checks about isolated `\r` are not implemented. 

## Provenance in canon

`RustLexer.g4` and `RustParser.g4` are from
[antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/8af0d4c26c796ea27c15c3d85418f2d0f77c3adb/rust)
at commit `8af0d4c26c796ea27c15c3d85418f2d0f77c3adb`, under the MIT license in
their headers (Copyright (c) 2010 The Rust Project Developers, Copyright (c)
2020-2022 Student Main). The README above is upstream's. canon interprets the
grammar itself and has no port of the `RustLexerBase` and `RustParserBase`
classes, so every change is marked `// canon:` in the grammar and recorded as
`DEC-rust-grammar` in canon's `canonical_decisions.yaml`:

- `SHEBANG` loses its start-of-file predicate and may not continue with `[`,
  so `#![no_std]` stays an inner attribute.
- `FLOAT_LITERAL` loses its two predicates and its bare-dot form (`1.`), so
  `1..2` and `1.max(2)` lex as integers; `tupleIndex` accepts the float that
  `x.0.1` then lexes to.
- `shl` and `shr` lose the predicates that required touching brackets.
- A backslash in a string or byte string always starts an escape, and a line
  continuation may end in `\r\n`.
- Outer attributes and visibility move from `item`, `associatedItem`, and
  `externalItem` into each kind of item through `itemPrefix`, so an item's
  node starts at its first attribute and the doc comment above binds to it;
  each attribute is labeled `marker` for test recognition.
- `tokenTree` and `macroMatch` take one token each instead of runs, which made
  macro bodies exponential to parse; the language is the same.
- Fixes for Rust upstream rejects: bounds on associated types, `union` as an
  identifier, `&&` before a type, keywords as macro metavariable names, the
  `~` token, and the underscore expression `_ = x;`.
- `LINE_COMMENT` and `OUTER_LINE_DOC` may not continue with a line break
  after `//` or `///`. Upstream's let an empty comment run on through the next
  line, which hid the code there.
- A bare `pub` is labeled `required`; `pub(crate)`, `pub(super)`, `pub(self)`,
  and `pub(in path)` are not. `#[macro_export]` is labeled `required`. The
  items of a trait and the variants of an enum are labeled `inherited`, so they
  need a comment when their trait or enum does. This is what rustc's
  `missing_docs` lint asks for, recorded as `DEC-rust-visibility`.
- A trait impl's trait and self type are one rule, `traitImplTarget`, which
  names the impl, so `impl Deref for Guard<T>` is `Deref-for-Guard<T>`.
- `async`, `try`, and `dyn` are identifiers too, as they are in the 2015
  edition, since canon reads a crate without knowing its edition. A later
  edition's async blocks and `dyn` types still parse as such.

The corpus below showed what the upstream grammar, last updated for Rust 1.60,
lacks; each fix is marked `// canon:` and tested in `RustTest.hs`:

- A block comment's body may hold a star, as in `/* a * b */`, and a nested
  comment nests: the body ends at the first `*/` outside one, as rustc reads
  it. Upstream let no star through but the closing one, so every comment with
  a star inside failed to lex, and its `/**` and `/***` openers ran on past
  `/**/` and `/***/`.
- Whitespace is Rust's `Pattern_White_Space`, so a tab separates tokens.
- A unicode escape's digits are one loop, which may hold underscores.
  Upstream's five optional digits matched `\u{202e}` in ten ways, and canon's
  lexer, which keeps every way, read the rest of a string once per way, so a
  string of eight such escapes took seconds.
- The `f16` and `f128` suffixes, C string literals (`c"..."`, `cr#"..."#`),
  and a float with a bare trailing dot, `0.`, read in the parser as an integer
  and a dot.
- Syntax stabilised since Rust 1.60: `let ... else`, `let` chains in `if`,
  `while`, and match guards, raw borrows (`&raw const x`), inline `const`
  blocks, labeled blocks, associated type bounds (`Iterator<Item: Debug>`),
  generic associated types with a `where` clause after the type, unsafe
  attributes (`#[unsafe(no_mangle)]`), any expression as an attribute's value
  (`#[doc = include_str!("x.md")]`), async closures and `async` bounds,
  precise capturing (`use<'a, T>`), exclusive and half-open range patterns,
  `safe` items of an `unsafe extern` block, and a named variadic parameter.
- The frontmatter of a Cargo script, a manifest between fences of three to
  twelve dashes, is hidden. Without a start-of-file predicate it is recognised
  wherever a fence opens a line of its own, which Rust code never does.
- A metavariable may be named `$_`.

The standard library is compiled with unstable features, and canon reads
`library/core`, `alloc`, and `std` as a reader of them sees them, so the
unstable syntax they use is accepted too: `const trait`, `const impl`,
`impl const Trait`, and `[const]`, `~const`, and `const` bounds; `default` and
`final` items and `default impl` (specialization); `auto trait`; impl
restrictions (`pub impl(crate) trait`); trait aliases; declarative macros 2.0
(`macro name(...) { ... }`), which the dialect documents as macros; `try`
blocks; `const` closures; `super let`; extern types; const parameter defaults;
and `..X` range patterns. Unstable syntax the standard library does not use is
not accepted.

## Canonically commented dialect

`canonically_commented/RustLexer.g4` and `RustParser.g4` are the grammar
above with doc comments as canonical comments, recorded as `DEC-rust-dialect`.
Each change is marked `// canon:`:

- `///` and `/**` open an outer doc comment, and `//!` and `/*!` an inner one,
  on the default channel, in the `DocLine`, `InnerDocLine`, and `DocBlock`
  modes, which tokenize prose, `ref:KEY`, and `license:KEY`. A following `///`
  or `//!` line continues a line comment. `////` and `/***` stay plain
  comments by the longest match. The block doc rules nested in a plain block
  comment are fragments.
- `canonicalComment`, `innerComment`, and `docPart` are the comment rules.
- Each item, named field, tuple field, and variant is a labeled unit
  alternative: `# function`, `# struct`, `# enum`, `# union`, `# trait`,
  `# macro`, `# type`, `# const`, `# static`, `# impl`, `# module`,
  `# field`, and `# variant`. The doc comment above the attributes is the
  `why`, and of several in a row the last binds. A tuple field has no name,
  so its type is labeled `ordinal` and the field is named by its position.
- A doc comment after an attribute, or where only an attribute may stand, as
  above a statement, a match arm, or a parameter, is an `orphan`, as rustc
  warns it is unused. An inner doc comment binds to the module whose body it
  opens, or at the top of a file to the file, and elsewhere is an `orphan`.
- A doc comment in a macro's input or matcher is a token of it.
- The `RustLexerBase` hook emits an empty `DOC_END` token where a line doc
  comment ends, at its line break, before a `////` line, or at the end of the
  file. The comment rules end at it, so a comment has one end rather than one
  after each word: canon's parser keeps a tree for every end, and the 900
  lines of `//!` that open the standard library's `pin.rs` took 2.5 GB. The
  plain grammar has no doc comment tokens and the hook leaves its tokens as
  they are.
- A block comment nested in a block doc comment is a word of its prose, so the
  doc comment ends where rustc ends it, as with `src/**/foo.rs` in ripgrep's.
- Anywhere else the grammar takes no doc comment, as inside an expression,
  before a closing bracket, or at the end of a block, the parser's
  `strayComment` options name `canonicalComment` and `innerComment`, so canon
  reads the file without the comment and reports it as an `orphan`
  (`DEC-stray-comments`). A doc comment never fails the parse.

## Corpus

`tools/corpus/rust.sh` checks the grammar against widely used Rust code. It
clones each repository below, shallow and pinned to a commit, into a directory
given as its argument (default `/tmp/corpus/rust`), checking out only the
listed subdirectories of the large ones; parses every `.rs` file with the plain
grammar and then with the dialect, each file under a limit of `TIMEOUT` (20)
seconds of CPU time; and prints per repository the files, the files parsed,
the deliberate exclusions, the failures, the CPU time, and the slowest files,
then the files the plain grammar parses and the dialect does not, and the
distribution of times. Rerun it with `tools/corpus/rust.sh [DIR]`; `JOBS` sets
the parallel parses and `ONLY` names one repository.

| Repository | Commit | Sampled | Files | Parsed | Excluded | CPU time, plain / dialect |
|---|---|---|---|---|---|---|
| rust-lang/rust | `602727f26878` | `library/core`, `library/alloc`, `library/std` | 1,092 | 1,092 | 0 | 83 s / 96 s |
| tokio-rs/tokio | `b26367524504` | whole | 808 | 808 | 0 | 45 s / 50 s |
| serde-rs/serde | `6693a89cca77` | whole | 208 | 208 | 0 | 12 s / 13 s |
| BurntSushi/ripgrep | `3fce3b5bb023` | whole | 110 | 110 | 0 | 11 s / 12 s |
| rust-lang/cargo | `bb2126cffae4` | whole | 1,374 | 1,354 | 20 | 73 s / 81 s |
| bevyengine/bevy | `14d79ccc341c` | `crates/bevy_ecs`, `bevy_app`, `bevy_math`, `bevy_reflect`, `bevy_transform`, `bevy_input` | 462 | 462 | 0 | 42 s / 44 s |
| `lang_samples/rust-scopeguard` | | | 1 | 1 | 0 | 0 s / 0 s |

The full commits are in the script. The dialect parses every file the plain
grammar parses. The 20 exclusions, each listed in the script with its reason,
are cargo fixtures: two rustfix inputs that hold the compiler error rustfix
fixes (E0178 and a missing comma between match arms), 17 of rustc's
frontmatter tests that rustc and Cargo reject for a malformed fence or
infostring, each with a `.stderr` expectation or a `//~ ERROR` annotation, and
one file of tokens a test includes as an expression, which is no crate.

Each file is parsed on one capability (`GHCRTS=-N1`) and timed in CPU
seconds, since the machine ran other work at a load of 60 to 140. Of the 4,055
files, the plain grammar parses 4,024 in under half a second, 29 in under one,
and 2 in under two; the slowest are `core/src/unicode/unicode_data.rs` at 1.6
s, ripgrep's `crates/core/flags/defs.rs` at 1.3 s, and bevy's
`crates/bevy_ecs/src/query/fetch.rs` at 0.8 s. The dialect's times are within
15% of these. Every failing file fails within 0.03 s.

## Known limitations in canon

Of the upstream limitations above, the first no longer holds for what canon
reads: the stable syntax of the crates in the corpus above and the unstable
syntax of the standard library parse, and syntax of the 2015 edition parses
too, the identifiers above being the only syntax it has that later editions do
not. The second holds: a carriage
return that no line feed follows is not rejected in a doc comment or a
string, where rustc rejects it. Rejecting it would only turn a file rustc
refuses into a parse failure; no unit of a file rustc compiles would change,
so canon does not check it (`DEC-rust-grammar`).

