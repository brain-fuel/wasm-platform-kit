/**
 [The "BSD licence"]
 license:BSD-3-Clause
 Copyright (c) 2013 Terence Parr, Sam Harwell
 Copyright (c) 2017 Ivan Kochurkin (upgrade to Java 8)
 Copyright (c) 2021 Michał Lorek (upgrade to Java 11)
 Copyright (c) 2022 Michał Lorek (upgrade to Java 17)
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 1. Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
 3. The name of the author may not be used to endorse or promote products
    derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// $antlr-format alignTrailingComments true, columnLimit 150, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine true, allowShortBlocksOnASingleLine true, minEmptyLines 0, alignSemicolons ownLine
// $antlr-format alignColons trailing, singleLineOverrulesHangingColon true, alignLexerCommands true, alignLabels true, alignTrailers true

lexer grammar JavaLexer;

// Keywords

/** The keyword abstract. */
ABSTRACT     : 'abstract';
/** The keyword assert. */
ASSERT       : 'assert';
/** The keyword boolean. */
BOOLEAN      : 'boolean';
/** The keyword break. */
BREAK        : 'break';
/** The keyword byte. */
BYTE         : 'byte';
/** The keyword case. */
CASE         : 'case';
/** The keyword catch. */
CATCH        : 'catch';
/** The keyword char. */
CHAR         : 'char';
/** The keyword class. */
CLASS        : 'class';
/** The reserved word const, which Java reserves but never uses, so that it cannot be an identifier. */
CONST        : 'const';
/** The keyword continue. */
CONTINUE     : 'continue';
/** The keyword default. */
DEFAULT      : 'default';
/** The keyword do. */
DO           : 'do';
/** The keyword double. */
DOUBLE       : 'double';
/** The keyword else. */
ELSE         : 'else';
/** The keyword enum. */
ENUM         : 'enum';
/** The contextual keyword exports, which the parser also accepts as an identifier where the context allows. */
EXPORTS    : 'exports';
/** The keyword extends. */
EXTENDS      : 'extends';
/** The keyword final. */
FINAL        : 'final';
/** The keyword finally. */
FINALLY      : 'finally';
/** The keyword float. */
FLOAT        : 'float';
/** The keyword for. */
FOR          : 'for';
/** The reserved word goto, which Java reserves but never uses, so that it cannot be an identifier. */
GOTO         : 'goto';
/** The keyword if. */
IF           : 'if';
/** The keyword implements. */
IMPLEMENTS   : 'implements';
/** The keyword import. */
IMPORT       : 'import';
/** The keyword instanceof. */
INSTANCEOF   : 'instanceof';
/** The keyword int. */
INT          : 'int';
/** The keyword interface. */
INTERFACE    : 'interface';
/** The keyword long. */
LONG         : 'long';
/** The contextual keyword module, which the parser also accepts as an identifier where the context allows. */
MODULE     : 'module';
/** The keyword native. */
NATIVE       : 'native';
/** The keyword new. */
NEW          : 'new';
/** The contextual keyword non-sealed, which the parser also accepts as an identifier where the context allows. */
NON_SEALED : 'non-sealed';
/** The contextual keyword open, which the parser also accepts as an identifier where the context allows. */
OPEN       : 'open';
/** The contextual keyword opens, which the parser also accepts as an identifier where the context allows. */
OPENS      : 'opens';
/** The keyword package. */
PACKAGE      : 'package';
/** The contextual keyword permits, which the parser also accepts as an identifier where the context allows. */
PERMITS    : 'permits';
/** The keyword private. */
PRIVATE      : 'private';
/** The keyword protected. */
PROTECTED    : 'protected';
/** The contextual keyword provides, which the parser also accepts as an identifier where the context allows. */
PROVIDES   : 'provides';
/** The keyword public. */
PUBLIC       : 'public';
/** The contextual keyword record, which the parser also accepts as an identifier where the context allows. */
RECORD: 'record';
/** The contextual keyword requires, which the parser also accepts as an identifier where the context allows. */
REQUIRES   : 'requires';
/** The keyword return. */
RETURN       : 'return';
/** The contextual keyword sealed, which the parser also accepts as an identifier where the context allows. */
SEALED     : 'sealed';
/** The keyword short. */
SHORT        : 'short';
/** The keyword static. */
STATIC       : 'static';
/** The keyword strictfp. */
STRICTFP     : 'strictfp';
/** The keyword super. */
SUPER        : 'super';
/** The keyword switch. */
SWITCH       : 'switch';
/** The keyword synchronized. */
SYNCHRONIZED : 'synchronized';
/** The keyword this. */
THIS         : 'this';
/** The keyword throw. */
THROW        : 'throw';
/** The keyword throws. */
THROWS       : 'throws';
/** The contextual keyword to, which the parser also accepts as an identifier where the context allows. */
TO         : 'to';
/** The keyword transient. */
TRANSIENT    : 'transient';
/** The contextual keyword transitive, which the parser also accepts as an identifier where the context allows. */
TRANSITIVE : 'transitive';
/** The keyword try. */
TRY          : 'try';
/** The contextual keyword uses, which the parser also accepts as an identifier where the context allows. */
USES       : 'uses';
/** The contextual keyword var, which the parser also accepts as an identifier where the context allows. */
VAR: 'var'; // reserved type name
/** The keyword void. */
VOID         : 'void';
/** The keyword volatile. */
VOLATILE     : 'volatile';
/** The contextual keyword when, which the parser also accepts as an identifier where the context allows. */
WHEN : 'when';
/** The keyword while. */
WHILE        : 'while';
/** The contextual keyword with, which the parser also accepts as an identifier where the context allows. */
WITH       : 'with';
/** The contextual keyword yield, which the parser also accepts as an identifier where the context allows. */
YIELD: 'yield'; // reserved type name from Java 14

// Literals

/** A decimal integer literal with optional underscores and an optional long suffix; a lone zero is decimal and any other leading zero is octal. */
DECIMAL_LITERAL : ('0' | [1-9] (Digits? | '_'+ Digits)) [lL]?;
/** A hexadecimal integer literal introduced by 0x, with optional underscores and long suffix. */
HEX_LITERAL     : '0' [xX] [0-9a-fA-F] ([0-9a-fA-F_]* [0-9a-fA-F])? [lL]?;
/** An octal integer literal introduced by a leading zero, with optional underscores and long suffix. */
OCT_LITERAL     : '0' '_'* [0-7] ([0-7_]* [0-7])? [lL]?;
/** A binary integer literal introduced by 0b, with optional underscores and long suffix. */
BINARY_LITERAL  : '0' [bB] [01] ([01_]* [01])? [lL]?;

/** A decimal floating point literal with an optional fraction, exponent, and float or double suffix. */
FLOAT_LITERAL:
    (Digits '.' Digits? | '.' Digits) ExponentPart? [fFdD]?
    | Digits (ExponentPart [fFdD]? | [fFdD])
;

/** A hexadecimal floating point literal, which must carry a binary exponent introduced by p. */
HEX_FLOAT_LITERAL: '0' [xX] (HexDigits '.'? | HexDigits? '.' HexDigits) [pP] [+-]? Digits [fFdD]?;

/** The boolean literals true and false. */
BOOL_LITERAL: 'true' | 'false';

/** A single character or escape sequence between single quotes. */
CHAR_LITERAL: '\'' (~['\\\r\n] | EscapeSequence) '\'';

/** Characters and escape sequences between double quotes on one line. */
STRING_LITERAL: '"' (~["\\\r\n] | EscapeSequence)* '"';

/** A multi-line string between triple double quotes, opened by a line break, from Java 15. */
TEXT_BLOCK: '"""' [ \t]* [\r\n] (. | EscapeSequence)*? '"""';

/** The null literal. */
NULL_LITERAL: 'null';

// Separators

/** Left parenthesis. */
LPAREN : '(';
/** Right parenthesis. */
RPAREN : ')';
/** Left brace. */
LBRACE : '{';
/** Right brace. */
RBRACE : '}';
/** Left square bracket. */
LBRACK : '[';
/** Right square bracket. */
RBRACK : ']';
/** Semicolon, the statement terminator. */
SEMI   : ';';
/** Comma, the list separator. */
COMMA  : ',';
/** Dot, for member access and qualified names. */
DOT    : '.';

// Operators

/** The assignment operator. */
ASSIGN   : '=';
/** Greater than, also one half of a closing type argument bracket, which is why the parser matches shifts as sequences of these. */
GT       : '>';
/** Less than, also the opening type argument bracket. */
LT       : '<';
/** Logical not. */
BANG     : '!';
/** Bitwise complement. */
TILDE    : '~';
/** The conditional operator and the wildcard type argument. */
QUESTION : '?';
/** Colon, used by the conditional operator, labels, cases, and enhanced for. */
COLON    : ':';
/** Equality comparison. */
EQUAL    : '==';
/** Less than or equal. */
LE       : '<=';
/** Greater than or equal. */
GE       : '>=';
/** Inequality comparison. */
NOTEQUAL : '!=';
/** Conditional and. */
AND      : '&&';
/** Conditional or. */
OR       : '||';
/** Increment. */
INC      : '++';
/** Decrement. */
DEC      : '--';
/** Addition and string concatenation, also unary plus. */
ADD      : '+';
/** Subtraction, also unary minus. */
SUB      : '-';
/** Multiplication, also the import wildcard. */
MUL      : '*';
/** Division. */
DIV      : '/';
/** Bitwise and, also the intersection type separator. */
BITAND   : '&';
/** Bitwise or, also the multi-catch separator. */
BITOR    : '|';
/** Bitwise exclusive or. */
CARET    : '^';
/** Remainder. */
MOD      : '%';

/** Compound addition assignment. */
ADD_ASSIGN     : '+=';
/** Compound subtraction assignment. */
SUB_ASSIGN     : '-=';
/** Compound multiplication assignment. */
MUL_ASSIGN     : '*=';
/** Compound division assignment. */
DIV_ASSIGN     : '/=';
/** Compound bitwise and assignment. */
AND_ASSIGN     : '&=';
/** Compound bitwise or assignment. */
OR_ASSIGN      : '|=';
/** Compound bitwise exclusive or assignment. */
XOR_ASSIGN     : '^=';
/** Compound remainder assignment. */
MOD_ASSIGN     : '%=';
/** Compound left shift assignment. */
LSHIFT_ASSIGN  : '<<=';
/** Compound signed right shift assignment. */
RSHIFT_ASSIGN  : '>>=';
/** Compound unsigned right shift assignment. */
URSHIFT_ASSIGN : '>>>=';

// Java 8 tokens

/** The arrow of lambdas and switch rules, from Java 8. */
ARROW      : '->';
/** The method reference operator, from Java 8. */
COLONCOLON : '::';

// Additional symbols not defined in the lexical specification

/** The at sign that introduces annotations and annotation types. */
AT       : '@';
/** The varargs ellipsis. */
ELLIPSIS : '...';

// Whitespace and comments

/** Whitespace, sent to the hidden channel. */
WS           : [ \t\r\n\u000C]+ -> channel(HIDDEN);
/** A block comment, sent to the hidden channel; a comment opened with two stars is a canonical comment instead, except the empty one. ref:DEC-grammar-carries-extraction-rules */
COMMENT      : ('/*' ~[*] .*? '*/' | '/**/') -> channel(HIDDEN);

/** A comment opened with a slash and two stars is a canonical comment. Its contents are tokenized in the DocComment mode so the parser can read the Why, the references, and the licenses. ref:DEC-grammar-carries-extraction-rules */
DOC_OPEN     : '/**' -> pushMode(DocComment);
/** A line comment, sent to the hidden channel. */
LINE_COMMENT : '//' ~[\r\n]*    -> channel(HIDDEN);

// Identifiers

/** An identifier: a Java letter followed by Java letters or digits, including characters above ASCII and surrogate pairs. */
IDENTIFIER: Letter LetterOrDigit*;

// Fragment rules

fragment ExponentPart: [eE] [+-]? Digits;

fragment EscapeSequence:
    '\\' 'u005c'? [bstnfr"'\\]
    | '\\' 'u005c'? ([0-3]? [0-7])? [0-7]
    | '\\' 'u'+ HexDigit HexDigit HexDigit HexDigit
;

fragment HexDigits: HexDigit ((HexDigit | '_')* HexDigit)?;

fragment HexDigit: [0-9a-fA-F];

fragment Digits: [0-9] ([0-9_]* [0-9])?;

fragment LetterOrDigit: Letter | [0-9];

fragment Letter:
    [a-zA-Z$_]                        // these are the "java letters" below 0x7F
    | ~[\u0000-\u007F\uD800-\uDBFF]   // covers all characters above 0x7F which are not a surrogate
    | [\uD800-\uDBFF] [\uDC00-\uDFFF] // covers UTF-16 surrogate pairs encodings for U+10000 to U+10FFFF
;

mode DocComment;

/** Closes a canonical comment and returns to the enclosing mode. ref:DEC-grammar-carries-extraction-rules */
DOC_CLOSE   : '*/' -> popMode;

/** A citation of a registry reference inside a canonical comment. ref:DEC-grammar-carries-extraction-rules */
DOC_REF     : 'ref:' DocKey;

/** A citation of a registry license inside a canonical comment. ref:DEC-grammar-carries-extraction-rules */
DOC_LICENSE : 'license:' DocKey;

/** A decorative star at the start of a comment line, dropped from the prose. ref:DEC-grammar-carries-extraction-rules */
DOC_STAR    : '*' -> skip;

/** Whitespace inside a canonical comment. ref:DEC-grammar-carries-extraction-rules */
DOC_WS      : [ \t\r\n]+ -> skip;

/** Punctuation inside a canonical comment, kept separate so a citation followed by a comma is still a citation. ref:DEC-grammar-carries-extraction-rules */
DOC_PUNCT   : [,.;:()!?[\]{}"'`<>=+];

/** A word of prose inside a canonical comment. ref:DEC-grammar-carries-extraction-rules */
DOC_WORD    : ~[ \t\r\n*,.;:()!?[\]{}"'`<>=+]+;

fragment DocKey : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])?;
