/**
 * [The "BSD license"]
 *  Copyright (c) 2012-2015 Terence Parr
 *  Copyright (c) 2012-2015 Sam Harwell
 *  Copyright (c) 2015 Gerald Rosenberg
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *
 *  1. Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *  3. The name of the author may not be used to endorse or promote products
 *     derived from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 *  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 *  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 *  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 *  NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 *  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 *  license:BSD-3-Clause
 */
/*
 *	A grammar for ANTLR v4 implemented using v4 syntax
 *
 *	Modified 2015.06.16 gbr
 *	-- update for compatibility with Antlr v4.5
 */

// $antlr-format alignTrailingComments on, columnLimit 130, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments off
// $antlr-format useTab off, allowShortRulesOnASingleLine off, allowShortBlocksOnASingleLine on, alignSemicolons hanging
// $antlr-format alignColons hanging

// ======================================================
// Lexer specification
// ======================================================

lexer grammar ANTLRv4Lexer;

options {
    superClass = LexerAdaptor;

    // Using a predefined list of tokens here to ensure the same order of the tokens as they were defined
    // in the old ANTLR3 tree parsers (to avoid having to change the tree parsers code).
    // The actual values of the tokens doesn't matter, but the order does.
    // tokenVocab = predefined;
    //
    // Instead of declaring predefined.tokens, which messes up the Maven tester for grammars-v4,
    // we define the total order of token type values. This should work because it was stated
    // that the "actual values of the tokens doesn't matter, but the order does." Declaring them
    // in the tokensSpec section preserves the total order.
}

// Insert here @header for lexer.

// Standard set of fragments
tokens {
    ACTION,
    ARG_ACTION,
    ARG_OR_CHARSET,
    ASSIGN,
    LEXER_CHAR_SET,
    RULE_REF,
    SEMPRED,
    STRING_LITERAL,
    TOKEN_REF,
    UNICODE_ESC,
    UNICODE_EXTENDED_ESC,
    WS,
    ALT,
    BLOCK,
    CLOSURE,
    ELEMENT_OPTIONS,
    EPSILON,
    LEXER_ACTION_CALL,
    LEXER_ALT_ACTION,
    OPTIONAL,
    POSITIVE_CLOSURE,
    RULE,
    RULEMODIFIERS,
    RULES,
    SET,
    WILDCARD
}

channels {
    OFF_CHANNEL,
    COMMENT
}

// -------------------------
// Comments

/** A comment opened with a slash and two stars is a canonical comment. Its contents are tokenized in the DocComment mode so the parser can read the Why, the references, and the licenses. ref:DEC-grammar-carries-extraction-rules */
DocOpen
    : '/**' -> pushMode (DocComment)
    ;

/** A comment opened with a slash and one star. It ends at the closer or at end of input, and goes to the comment channel. */
BLOCK_COMMENT
    : '/*' ~ [*] .*? ('*/' | EOF) -> channel (COMMENT)
    ;

/** A comment from two slashes to the end of the line, on the comment channel. */
LINE_COMMENT
    : '//' ~ [\r\n]* -> channel (COMMENT)
    ;

// -------------------------
// Integer

/** A decimal integer without leading zeros, used in options and element options. */
INT
    : '0'
    | [1-9] [0-9]*
    ;

// -------------------------
// Literal string
//
// ANTLR makes no distinction between a single character literal and a
// multi-character string. All literals are single quote delimited and
// may contain unicode escape sequences of the form \uxxxx, where x
// is a valid hexadecimal number (per Unicode standard).
/** A single-quoted literal with escapes, closed on the same line. */
STRING_LITERAL
    : '\'' (ESC_SEQUENCE | ~ ['\r\n\\])* '\''
    ;

/** A single-quoted literal that reaches the end of its line unclosed, kept as its own token so the error is reported precisely. */
UNTERMINATED_STRING_LITERAL
    : '\'' (ESC_SEQUENCE | ~ ['\r\n\\])*
    ;

// -------------------------
// Arguments
//
// Certain argument lists, such as those specifying call parameters
// to a rule invocation, or input parameters to a rule specification
// are contained within square brackets.
/** An opening square bracket. Its action asks the adaptor whether this begins an argument block or a lexer character set, which depends on the enclosing rule kind. */
BEGIN_ARGUMENT
    : '[' { this.handleBeginArgument(); }
    ;

// Many language targets use {} as block delimiters and so we
// must recursively match {} delimited blocks to balance the
// braces. Additionally, we must make some assumptions about
// literal string representation in the target language. We assume
// that they are delimited by ' or " and so consume these
// in their own alts so as not to inadvertently match {}.
/** A brace-delimited block of target code with nested braces, strings, and comments balanced. */
ACTION
    : NESTED_ACTION
    ;

fragment NESTED_ACTION
    : // Action and other blocks start with opening {
    '{' (
        NESTED_ACTION          // embedded {} block
        | STRING_LITERAL       // single quoted string
        | DoubleQuoteLiteral   // double quoted string
        | TripleQuoteLiteral   // string literal with triple quotes
        | BacktickQuoteLiteral // backtick quoted string
        | '/*' .*? '*/'        // block comment
        | '//' ~[\r\n]*        // line comment
        | '\\' .               // Escape sequence
        | ~(
            '\\'
            | '"'
            | '\''
            | '`'
            | '{'
        ) // Some other single character that is not handled above
    )*? '}'
    ;

// -------------------------
// Keywords
//
// 'options', 'tokens', and 'channels' are considered keywords
// but only when followed by '{', and considered as a single token.
// Otherwise, the symbols are tokenized as RULE_REF and allowed as
// an identifier in a labeledElement.
/** The options keyword together with its opening brace, so that options alone remains an ordinary identifier. */
OPTIONS
    : 'options' WS* '{'
    ;

/** The tokens keyword together with its opening brace, so that tokens alone remains an ordinary identifier. */
TOKENS
    : 'tokens' WS* '{'
    ;

/** The channels keyword together with its opening brace, so that channels alone remains an ordinary identifier. */
CHANNELS
    : 'channels' WS* '{'
    ;

/** The import keyword. */
IMPORT
    : 'import'
    ;

/** The fragment keyword, which marks a helper lexer rule. */
FRAGMENT
    : 'fragment'
    ;

/** The lexer keyword. */
LEXER
    : 'lexer'
    ;

/** The parser keyword. */
PARSER
    : 'parser'
    ;

/** The grammar keyword. */
GRAMMAR
    : 'grammar'
    ;

/** The protected modifier. */
PROTECTED
    : 'protected'
    ;

/** The public modifier. */
PUBLIC
    : 'public'
    ;

/** The private modifier. */
PRIVATE
    : 'private'
    ;

/** The returns keyword. */
RETURNS
    : 'returns'
    ;

/** The locals keyword. */
LOCALS
    : 'locals'
    ;

/** The throws keyword. */
THROWS
    : 'throws'
    ;

/** The catch keyword. */
CATCH
    : 'catch'
    ;

/** The finally keyword. */
FINALLY
    : 'finally'
    ;

/** The mode keyword. */
MODE
    : 'mode'
    ;

// -------------------------
// Punctuation

/** Separates a rule's header from its body. */
COLON
    : ':'
    ;

/** Separates a named action's scope from its name. */
COLONCOLON
    : '::'
    ;

/** Separates list items. */
COMMA
    : ','
    ;

/** Ends a rule, an option, an import list, or a mode declaration. */
SEMI
    : ';'
    ;

/** Opens a block. */
LPAREN
    : '('
    ;

/** Closes a block. */
RPAREN
    : ')'
    ;

/** Closes an options, tokens, or channels block. The opening brace is part of the keyword token. */
RBRACE
    : '}'
    ;

/** Introduces lexer commands. */
RARROW
    : '->'
    ;

/** Opens element options. */
LT
    : '<'
    ;

/** Closes element options. */
GT
    : '>'
    ;

/** Assigns a value to an option or binds a label. */
ASSIGN
    : '='
    ;

/** Marks an element optional, a loop non-greedy, or an action as a predicate. */
QUESTION
    : '?'
    ;

/** Marks zero or more repetitions. */
STAR
    : '*'
    ;

/** Binds a list label. */
PLUS_ASSIGN
    : '+='
    ;

/** Marks one or more repetitions. */
PLUS
    : '+'
    ;

/** Separates alternatives. */
OR
    : '|'
    ;

/** Reserved by ANTLR for attribute references inside actions. */
DOLLAR
    : '$'
    ;

/** Joins the two ends of a character range. */
RANGE
    : '..'
    ;

/** The wildcard, and the separator in dotted names. */
DOT
    : '.'
    ;

/** Introduces a named action or a rule action. */
AT
    : '@'
    ;

/** Introduces an alternative label. */
POUND
    : '#'
    ;

/** Negates a set. */
NOT
    : '~'
    ;

// -------------------------
// Identifiers - allows unicode rule/token names

/** An identifier. The adaptor retypes it to a token reference or a rule reference by the case of its first letter. */
ID
    : NameStartChar NameChar*
    ;

// -------------------------
// Whitespace

/** Whitespace, sent off channel. */
WS
    : [ \t\r\n\f]+ -> channel (OFF_CHANNEL)
    ;

// ======================================================
// Lexer modes
// -------------------------
// Arguments
mode Argument;

// E.g., [int x, List<String> a[]]
/** An opening bracket inside an argument block, which nests one level deeper. */
NESTED_ARGUMENT
    : '[' -> type (ARGUMENT_CONTENT), pushMode (Argument)
    ;

/** A backslash escape inside an argument block. */
ARGUMENT_ESCAPE
    : '\\' . -> type (ARGUMENT_CONTENT)
    ;

/** A double-quoted string inside an argument block, kept whole so a bracket inside it does not close the block. */
ARGUMENT_STRING_LITERAL
    : DoubleQuoteLiteral -> type (ARGUMENT_CONTENT)
    ;

/** A single-quoted literal inside an argument block, kept whole for the same reason as strings. */
ARGUMENT_CHAR_LITERAL
    : STRING_LITERAL -> type (ARGUMENT_CONTENT)
    ;

/** A closing bracket. Its action pops the mode and, if still nested, keeps the token as argument content. */
END_ARGUMENT
    : ']' { this.handleEndArgument(); }
    ;

// added this to return non-EOF token type here. EOF does something weird
/** End of input inside an argument block, which pops the mode so lexing can finish. */
UNTERMINATED_ARGUMENT
    : EOF -> popMode
    ;

/** Any other character inside an argument block. */
ARGUMENT_CONTENT
    : .
    ;

// -------------------------
mode LexerCharSet;

/** The characters of a character set, accumulated with more until the closing bracket. */
LEXER_CHAR_SET_BODY
    : (~ [\]\\] | '\\' .)+ -> more
    ;

/** The closing bracket of a character set, which emits the whole set as one token. */
LEXER_CHAR_SET
    : ']' -> popMode
    ;

/** End of input inside a character set, which pops the mode so lexing can finish. */
UNTERMINATED_CHAR_SET
    : EOF -> popMode
    ;

// ------------------------------------------------------------------------------
// Grammar specific Keywords, Punctuation, etc.

fragment ESC_SEQUENCE
    : '\\' ([btnfr"'\\] | UnicodeESC | . | EOF)
    ;

fragment HexDigit
    : [0-9a-fA-F]
    ;

fragment UnicodeESC
    : 'u' (HexDigit (HexDigit (HexDigit HexDigit?)?)?)?
    ;

fragment DoubleQuoteLiteral
    : '"' (ESC_SEQUENCE | ~["\r\n\\])*? '"'
    ;

fragment TripleQuoteLiteral
    : '"""' (ESC_SEQUENCE | .)*? '"""'
    ;

fragment BacktickQuoteLiteral
    : '`' (ESC_SEQUENCE | ~["\r\n\\])*? '`'
    ;

// -----------------------------------
// Character ranges

fragment NameChar
    : NameStartChar
    | '0' .. '9'
    | '_'
    | '\u00B7'
    | '\u0300' .. '\u036F'
    | '\u203F' .. '\u2040'
    ;

fragment NameStartChar
    : 'A' .. 'Z'
    | 'a' .. 'z'
    | '\u00C0' .. '\u00D6'
    | '\u00D8' .. '\u00F6'
    | '\u00F8' .. '\u02FF'
    | '\u0370' .. '\u037D'
    | '\u037F' .. '\u1FFF'
    | '\u200C' .. '\u200D'
    | '\u2070' .. '\u218F'
    | '\u2C00' .. '\u2FEF'
    | '\u3001' .. '\uD7FF'
    | '\uF900' .. '\uFDCF'
    | '\uFDF0' .. '\uFFFD'
    // ignores | ['\u10000-'\uEFFFF]
    ;

mode DocComment;

/** Closes a canonical comment and returns to the enclosing mode. ref:DEC-grammar-carries-extraction-rules */
DocClose
    : '*/' -> popMode
    ;

/** A citation of a registry reference inside a canonical comment. ref:DEC-grammar-carries-extraction-rules */
DocRef
    : 'ref:' DocKey
    ;

/** A citation of a registry license inside a canonical comment. ref:DEC-grammar-carries-extraction-rules */
DocLicense
    : 'license:' DocKey
    ;

/** A decorative star at the start of a comment line, dropped from the prose. ref:DEC-grammar-carries-extraction-rules */
DocStar
    : '*' -> skip
    ;

/** Whitespace inside a canonical comment. ref:DEC-grammar-carries-extraction-rules */
DocWs
    : [ \t\r\n]+ -> skip
    ;

/** Punctuation inside a canonical comment, kept separate so a citation followed by a comma is still a citation. ref:DEC-grammar-carries-extraction-rules */
DocPunct
    : [,.;:()!?[\]{}"'`<>=+]
    ;

/** A word of prose inside a canonical comment. ref:DEC-grammar-carries-extraction-rules */
DocWord
    : ~ [ \t\r\n*,.;:()!?[\]{}"'`<>=+]+
    ;

fragment DocKey
    : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])?
    ;
