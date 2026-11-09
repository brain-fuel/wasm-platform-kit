/*
Copyright (c) 2010 The Rust Project Developers
Copyright (c) 2020-2022 Student Main

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice (including the next paragraph) shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

// $antlr-format alignTrailingComments true, columnLimit 150, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine true, allowShortBlocksOnASingleLine true, minEmptyLines 0, alignSemicolons ownLine
// $antlr-format alignColons trailing, singleLineOverrulesHangingColon true, alignLexerCommands true, alignLabels true, alignTrailers true

lexer grammar RustLexer;

// Insert here @header for C++ lexer.

// canon: canon's interpreter has no port of RustLexerBase; the option selects canon's own Rust hook,
// which ends each line doc comment of the canonically commented dialect with a token and leaves the
// plain grammar's tokens as they are. The three predicates that called into the base class are
// replaced below, each marked.
options
{
    superClass = RustLexerBase;
}

// https://doc.rust-lang.org/reference/keywords.html strict
KW_AS        : 'as';
KW_BREAK     : 'break';
KW_CONST     : 'const';
KW_CONTINUE  : 'continue';
KW_CRATE     : 'crate';
KW_ELSE      : 'else';
KW_ENUM      : 'enum';
KW_EXTERN    : 'extern';
KW_FALSE     : 'false';
KW_FN        : 'fn';
KW_FOR       : 'for';
KW_IF        : 'if';
KW_IMPL      : 'impl';
KW_IN        : 'in';
KW_LET       : 'let';
KW_LOOP      : 'loop';
KW_MATCH     : 'match';
KW_MOD       : 'mod';
KW_MOVE      : 'move';
KW_MUT       : 'mut';
KW_PUB       : 'pub';
KW_REF       : 'ref';
KW_RETURN    : 'return';
KW_SELFVALUE : 'self';
KW_SELFTYPE  : 'Self';
KW_STATIC    : 'static';
KW_STRUCT    : 'struct';
KW_SUPER     : 'super';
KW_TRAIT     : 'trait';
KW_TRUE      : 'true';
KW_TYPE      : 'type';
KW_UNSAFE    : 'unsafe';
KW_USE       : 'use';
KW_WHERE     : 'where';
KW_WHILE     : 'while';

// 2018+
KW_ASYNC : 'async';
KW_AWAIT : 'await';
KW_DYN   : 'dyn';

// reserved
KW_ABSTRACT : 'abstract';
KW_BECOME   : 'become';
KW_BOX      : 'box';
KW_DO       : 'do';
KW_FINAL    : 'final';
KW_MACRO    : 'macro';
KW_OVERRIDE : 'override';
KW_PRIV     : 'priv';
KW_TYPEOF   : 'typeof';
KW_UNSIZED  : 'unsized';
KW_VIRTUAL  : 'virtual';
KW_YIELD    : 'yield';

// reserved 2018+
KW_TRY: 'try';

// weak
KW_UNION          : 'union';
KW_STATICLIFETIME : '\'static';

KW_MACRORULES        : 'macro_rules';
KW_UNDERLINELIFETIME : '\'_';
KW_DOLLARCRATE       : '$crate';

// rule itself allow any identifier, but keyword has been matched before
NON_KEYWORD_IDENTIFIER: XID_Start XID_Continue* | '_' XID_Continue+;

// [\p{L}\p{Nl}\p{Other_ID_Start}-\p{Pattern_Syntax}-\p{Pattern_White_Space}]
fragment XID_Start: [\p{L}\p{Nl}] | UNICODE_OIDS;

// [\p{ID_Start}\p{Mn}\p{Mc}\p{Nd}\p{Pc}\p{Other_ID_Continue}-\p{Pattern_Syntax}-\p{Pattern_White_Space}]
fragment XID_Continue: XID_Start | [\p{Mn}\p{Mc}\p{Nd}\p{Pc}] | UNICODE_OIDC;

fragment UNICODE_OIDS: '\u1885' ..'\u1886' | '\u2118' | '\u212e' | '\u309b' ..'\u309c';

fragment UNICODE_OIDC: '\u00b7' | '\u0387' | '\u1369' ..'\u1371' | '\u19da';

RAW_IDENTIFIER: 'r#' NON_KEYWORD_IDENTIFIER;
// comments https://doc.rust-lang.org/reference/comments.html
// canon: the character after // or /// may not be a line break. Upstream's ~[/!] and ~[/] matched
// one, so an empty // or /// comment ran on through the next line and hid the code on it.
LINE_COMMENT: ('//' (~[/!\r\n] | '//') ~[\r\n]* | '//') -> channel (HIDDEN);

// canon: the body of a block comment may hold a star, as in /* a * b */, and a nested comment nests:
// the body ends at the first */ outside one, read as rustc reads it. Upstream's ~[*] let no star
// through but the one that closes the comment, so every comment with a star inside failed to lex;
// and its /** and /*** openers could run on past a */, reading /**/ as the start of a doc comment.
// A comment of three or more stars, /***, ends at the first */ after them, as /***/ does at once.
BLOCK_COMMENT:
    (
        '/*' (~[*!] | BLOCK_COMMENT_OR_DOC) BLOCK_BODY
        | '/**/'
        | '/***' '*'* ('/' | ~[*/] BLOCK_BODY)
    ) -> channel (HIDDEN)
;

// canon: the rest of a block comment after its opener, up to and including its */.
fragment BLOCK_BODY: (BLOCK_COMMENT_OR_DOC | .)*? '*/';

INNER_LINE_DOC: '//!' ~[\n\r]* -> channel (HIDDEN); // isolated cr

// canon: as for BLOCK_COMMENT.
INNER_BLOCK_DOC: '/*!' BLOCK_BODY -> channel (HIDDEN);

// canon: as for LINE_COMMENT, an empty /// ends at its line break.
OUTER_LINE_DOC: '///' (~[/\n\r] ~[\n\r]*)? -> channel (HIDDEN); // isolated cr

// canon: as for BLOCK_COMMENT; /**/ is an empty plain comment.
OUTER_BLOCK_DOC: '/**' ~[*/] BLOCK_BODY -> channel (HIDDEN);

BLOCK_COMMENT_OR_DOC: ( BLOCK_COMMENT | INNER_BLOCK_DOC | OUTER_BLOCK_DOC) -> channel (HIDDEN);

// canon: the start-of-file predicate is gone, and a shebang may not continue with '[', so that an
// inner attribute such as #![no_std] is never read as one.
SHEBANG: '\ufeff'? '#!' ~[[\r\n] ~[\r\n]* -> channel(HIDDEN);

// canon: the frontmatter of a Cargo script, a fence of three or more dashes with an optional
// infostring, the manifest, and a closing fence of as many dashes, which nightly rustc and Cargo read
// at the top of a file. Without a start-of-file predicate it is recognised anywhere a fence opens a
// line of its own, which code never does, as -- is no Rust operator but two minus signs. Fences of
// three to twelve dashes are recognised; a longer fence lets the manifest hold a line of fewer
// dashes.
FRONTMATTER: (FM3 | FM4 | FM5 | FM6 | FM7 | FM8 | FM9 | FM10 | FM11 | FM12) -> channel(HIDDEN);

fragment FM_INFO  : [ \t]* ([a-zA-Z0-9_] [a-zA-Z0-9_.-]*)? [ \t]* ('\r'? '\n');
fragment FM_CLOSE : [ \t]* ('\r'? '\n' | EOF);
fragment FM3 : '---' FM_INFO (.*? '\n')? '---' FM_CLOSE;
fragment FM4 : '----' FM_INFO (.*? '\n')? '----' FM_CLOSE;
fragment FM5 : '-----' FM_INFO (.*? '\n')? '-----' FM_CLOSE;
fragment FM6 : '------' FM_INFO (.*? '\n')? '------' FM_CLOSE;
fragment FM7 : '-------' FM_INFO (.*? '\n')? '-------' FM_CLOSE;
fragment FM8 : '--------' FM_INFO (.*? '\n')? '--------' FM_CLOSE;
fragment FM9 : '---------' FM_INFO (.*? '\n')? '---------' FM_CLOSE;
fragment FM10 : '----------' FM_INFO (.*? '\n')? '----------' FM_CLOSE;
fragment FM11 : '-----------' FM_INFO (.*? '\n')? '-----------' FM_CLOSE;
fragment FM12 : '------------' FM_INFO (.*? '\n')? '------------' FM_CLOSE;

// whitespace https://doc.rust-lang.org/reference/whitespace.html
// canon: whitespace is Rust's Pattern_White_Space, which holds the tab, vertical tab, form feed, and
// the left-to-right, right-to-left, line, and paragraph separators as well as the space separators.
WHITESPACE : [\p{Zs}\t\u000B\u000C\u0085\u200E\u200F\u2028\u2029] -> channel(HIDDEN);
NEWLINE    : ('\r\n' | [\r\n]) -> channel(HIDDEN);

// tokens char and string
CHAR_LITERAL: '\'' ( ~['\\\n\r\t] | QUOTE_ESCAPE | ASCII_ESCAPE | UNICODE_ESCAPE) '\'';

// canon: a backslash in a string always starts an escape, as the Rust reference says. Upstream let a
// backslash also stand for itself, so a string ending in an escaped backslash, such as "/\\", could
// end at a later quote instead, and canon's lexer takes the longest match.
STRING_LITERAL: '"' ( ~["\\] | QUOTE_ESCAPE | ASCII_ESCAPE | UNICODE_ESCAPE | ESC_NEWLINE)* '"';

RAW_STRING_LITERAL: 'r' RAW_STRING_CONTENT;

fragment RAW_STRING_CONTENT: '#' RAW_STRING_CONTENT '#' | '"' .*? '"';

BYTE_LITERAL: 'b\'' (. | QUOTE_ESCAPE | BYTE_ESCAPE) '\'';

// canon: as for STRING_LITERAL, a backslash always starts an escape.
BYTE_STRING_LITERAL: 'b"' (~["\\] | QUOTE_ESCAPE | BYTE_ESCAPE | ESC_NEWLINE)* '"';

RAW_BYTE_STRING_LITERAL: 'br' RAW_STRING_CONTENT;

// canon: C string literals, c"..." and cr#"..."#, stable since Rust 1.77.
C_STRING_LITERAL: 'c"' (~["\\] | QUOTE_ESCAPE | BYTE_ESCAPE | UNICODE_ESCAPE | ESC_NEWLINE)* '"';

RAW_C_STRING_LITERAL: 'cr' RAW_STRING_CONTENT;

fragment ASCII_ESCAPE: '\\x' OCT_DIGIT HEX_DIGIT | COMMON_ESCAPE;

fragment BYTE_ESCAPE: '\\x' HEX_DIGIT HEX_DIGIT | COMMON_ESCAPE;

fragment COMMON_ESCAPE: '\\' [nrt\\0];

// canon: the digits of a unicode escape are one loop, which may hold underscores as rustc allows.
// Upstream's five optional digits matched \u{202e} in ten ways, and canon's lexer, which keeps every
// way, took the rest of a string once for each, so a string of eight such escapes took seconds.
fragment UNICODE_ESCAPE: '\\u{' HEX_DIGIT (HEX_DIGIT | '_')* '}';

fragment QUOTE_ESCAPE: '\\' ['"];

// canon: a line continuation may end in a carriage return and line feed.
fragment ESC_NEWLINE: '\\' '\r'? '\n';

// number

INTEGER_LITERAL: ( DEC_LITERAL | BIN_LITERAL | OCT_LITERAL | HEX_LITERAL) INTEGER_SUFFIX?;

DEC_LITERAL: DEC_DIGIT (DEC_DIGIT | '_')*;

HEX_LITERAL: '0x' '_'* HEX_DIGIT (HEX_DIGIT | '_')*;

OCT_LITERAL: '0o' '_'* OCT_DIGIT (OCT_DIGIT | '_')*;

BIN_LITERAL: '0b' '_'* [01] [01_]*;

// canon: without the base-class predicates, a literal ending in a bare dot such as 1. would swallow
// the first dot of a range 1..2 and of a method call 1.max(2), so that form is dropped and 1.0 must be
// written; and 0.1 after a dot is a float here, which the parser accepts as two tuple indices.
FLOAT_LITERAL: DEC_LITERAL ( '.' DEC_LITERAL)? FLOAT_EXPONENT? FLOAT_SUFFIX?;

fragment INTEGER_SUFFIX:
    'u8'
    | 'u16'
    | 'u32'
    | 'u64'
    | 'u128'
    | 'usize'
    | 'i8'
    | 'i16'
    | 'i32'
    | 'i64'
    | 'i128'
    | 'isize'
;

// canon: the f16 and f128 suffixes of the half and quadruple precision float types.
fragment FLOAT_SUFFIX: 'f16' | 'f32' | 'f64' | 'f128';

fragment FLOAT_EXPONENT: [eE] [+-]? '_'* DEC_LITERAL;

fragment OCT_DIGIT: [0-7];

fragment DEC_DIGIT: [0-9];

fragment HEX_DIGIT: [0-9a-fA-F];

// LIFETIME_TOKEN: '\'' IDENTIFIER_OR_KEYWORD | '\'_';

LIFETIME_OR_LABEL: '\'' NON_KEYWORD_IDENTIFIER;

PLUS    : '+';
MINUS   : '-';
STAR    : '*';
SLASH   : '/';
PERCENT : '%';
CARET   : '^';
NOT     : '!';
AND     : '&';
OR      : '|';
ANDAND  : '&&';
OROR    : '||';
//SHL: '<<'; SHR: '>>'; removed to avoid confusion in type parameter
PLUSEQ     : '+=';
MINUSEQ    : '-=';
STAREQ     : '*=';
SLASHEQ    : '/=';
PERCENTEQ  : '%=';
CARETEQ    : '^=';
ANDEQ      : '&=';
OREQ       : '|=';
SHLEQ      : '<<=';
SHREQ      : '>>=';
EQ         : '=';
EQEQ       : '==';
NE         : '!=';
GT         : '>';
LT         : '<';
GE         : '>=';
LE         : '<=';
AT         : '@';
UNDERSCORE : '_';
DOT        : '.';
DOTDOT     : '..';
DOTDOTDOT  : '...';
DOTDOTEQ   : '..=';
COMMA      : ',';
SEMI       : ';';
COLON      : ':';
PATHSEP    : '::';
RARROW     : '->';
FATARROW   : '=>';
POUND      : '#';
DOLLAR     : '$';
QUESTION   : '?';
// canon: the tilde is a token of Rust's lexer though no expression uses it, and macros such as
// anyhow's take it as input.
TILDE: '~';

LCURLYBRACE    : '{';
RCURLYBRACE    : '}';
LSQUAREBRACKET : '[';
RSQUAREBRACKET : ']';
LPAREN         : '(';
RPAREN         : ')';
