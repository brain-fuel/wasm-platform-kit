/**
 * [The "BSD license"]
 *  Copyright (c) 2012-2014 Terence Parr
 *  Copyright (c) 2012-2014 Sam Harwell
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

/*	A grammar for ANTLR v4 written in ANTLR v4.
 *
 *	Modified 2015.06.16 gbr
 *	-- update for compatibility with Antlr v4.5
 *	-- add mode for channels
 *	-- moved members to LexerAdaptor
 * 	-- move fragments to imports
 */

// $antlr-format alignTrailingComments on, columnLimit 130, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments off
// $antlr-format useTab off, allowShortRulesOnASingleLine off, allowShortBlocksOnASingleLine on, alignSemicolons hanging
// $antlr-format alignColons hanging

parser grammar ANTLRv4Parser;

options {
    tokenVocab = ANTLRv4Lexer;
}

// The main entry point for parsing a v4 grammar.
/** A grammar file is an optional file-level canonical comment, one declaration, any prequel constructs, the rules, then any lexer modes, up to end of input. The grammar is a unit whose What is its name and whose Why is the file-level comment, where a license lives. ref:grammars-v4 ref:DEC-grammar-carries-extraction-rules */
grammarSpec
    : why = canonicalComment? grammarDecl prequelConstruct* rules modeSpec* EOF # grammarDefinition
    ;

/** Names the grammar and says whether it is a lexer, parser, or combined grammar, which decides which rule kinds are allowed in it. */
grammarDecl
    : grammarType what = identifier SEMI
    ;

/** The three grammar kinds ANTLR distinguishes: lexer only, parser only, or combined. */
grammarType
    : LEXER GRAMMAR
    | PARSER GRAMMAR
    | GRAMMAR
    ;

// This is the list of all constructs that can be declared before
// the set of rules that compose the grammar, and is invoked 0..n
// times by the grammarPrequel rule.

/** Everything that may appear between the declaration and the first rule: options, imports, token and channel declarations, and named actions. */
prequelConstruct
    : optionsSpec
    | delegateGrammars
    | tokensSpec
    | channelsSpec
    | action_
    ;

// ------------
// Options - things that affect analysis and/or code generation

/** Key-value options that configure the tool or the generated code, such as tokenVocab and superClass. */
optionsSpec
    : OPTIONS (option SEMI)* RBRACE
    ;

/** One option: an identifier assigned a value. */
option
    : identifier ASSIGN optionValue
    ;

/** An option value is a dotted name, a string, an action block, or an integer. */
optionValue
    : identifier (DOT identifier)*
    | STRING_LITERAL
    | actionBlock
    | INT
    ;

// ------------
// Delegates

/** Imports of other grammars whose rules are merged into this one. */
delegateGrammars
    : IMPORT delegateGrammar (COMMA delegateGrammar)* SEMI
    ;

/** One import, optionally aliased with an identifier. */
delegateGrammar
    : identifier ASSIGN identifier
    | identifier
    ;

// ------------
// Tokens & Channels

/** Declares token types that no lexer rule defines, so a parser grammar can refer to them. */
tokensSpec
    : TOKENS idList? RBRACE
    ;

/** Declares named channels beyond the default and hidden ones, for lexer commands to route tokens to. */
channelsSpec
    : CHANNELS idList? RBRACE
    ;

/** A comma-separated identifier list with an optional trailing comma, shared by the tokens and channels blocks. */
idList
    : identifier (COMMA identifier)* COMMA?
    ;

// Match stuff like @parser::members {int i;}

/** A named action such as @header or @members, optionally scoped to the lexer or parser, holding target code. */
action_
    : AT (actionScopeName COLONCOLON)? identifier actionBlock
    ;

// Scope names could collide with keywords; allow them as ids for action scopes

/** The scope of a named action: an identifier, or the words lexer and parser, which are keywords elsewhere. */
actionScopeName
    : identifier
    | LEXER
    | PARSER
    ;

/** Target-language code in braces, kept opaque because ANTLR does not interpret it. */
actionBlock
    : ACTION
    ;

/** Target-language code in square brackets, used for rule arguments, return values, and locals. */
argActionBlock
    : BEGIN_ARGUMENT ARGUMENT_CONTENT*? END_ARGUMENT
    ;

/** A lexer mode: a name followed by the lexer rules that are active only in that mode. */
modeSpec
    : why = canonicalComment? MODE what = identifier SEMI lexerRuleSpec* # lexerMode
    ;

/** The rule section, which may be empty. */
rules
    : ruleSpec*
    ;

/** A rule is either a parser rule or a lexer rule, told apart by the case of its first letter. */
ruleSpec
    : parserRuleSpec
    | lexerRuleSpec
    ;

/** A parser rule: modifiers, name, arguments, returns, throws, locals, prequels, the alternatives, and exception handlers. The canonically commented dialect requires a canonical comment before every parser rule. ref:DEC-grammar-carries-extraction-rules */
parserRuleSpec
    : why = canonicalComment ruleModifiers? what = RULE_REF argActionBlock? ruleReturns? throwsSpec? localsSpec? rulePrequel* COLON how = ruleBlock SEMI
        exceptionGroup # parserRule
    ;

/** Optional catch handlers and a finally clause after a parser rule, mirroring the target language's exception handling. */
exceptionGroup
    : exceptionHandler* finallyClause?
    ;

/** One catch clause: an exception parameter and the code to run. */
exceptionHandler
    : CATCH argActionBlock actionBlock
    ;

/** Code run after a parser rule whether or not it failed. */
finallyClause
    : FINALLY actionBlock
    ;

/** Options or actions that precede a parser rule's colon. */
rulePrequel
    : optionsSpec
    | ruleAction
    ;

/** Declares the values a parser rule returns. */
ruleReturns
    : RETURNS argActionBlock
    ;

// --------------
// Exception spec
/** Declares the exceptions a parser rule may throw. */
throwsSpec
    : THROWS qualifiedIdentifier (COMMA qualifiedIdentifier)*
    ;

/** Declares local variables available to a parser rule's actions. */
localsSpec
    : LOCALS argActionBlock
    ;

/** Match stuff like @init {int i;} */
ruleAction
    : AT identifier actionBlock
    ;

/** One or more modifiers before a rule name. */
ruleModifiers
    : ruleModifier+
    ;

// An individual access modifier for a rule. The 'fragment' modifier
// is an internal indication for lexer rules that they do not match
// from the input but are like subroutines for other lexer rules to
// reuse for certain lexical patterns. The other modifiers are passed
// to the code generation templates and may be ignored by the template
// if they are of no use in that language.

/** The visibility modifiers ANTLR accepts, plus fragment, which marks a lexer rule as a helper that never produces a token by itself. */
ruleModifier
    : PUBLIC
    | PRIVATE
    | PROTECTED
    | FRAGMENT
    ;

/** The body of a parser rule. */
ruleBlock
    : ruleAltList
    ;

/** Alternatives separated by bars. Order matters because ANTLR resolves an ambiguity in favour of the earlier alternative. */
ruleAltList
    : labeledAlt (OR labeledAlt)*
    ;

/** An alternative with an optional #label, which names the alternative's node in the generated parse tree. */
labeledAlt
    : alternative (POUND identifier)?
    ;

// --------------------
// Lexer rules

/** A lexer rule: an optional fragment marker, the name, options, and the alternatives. The canonically commented dialect requires a canonical comment before every non-fragment lexer rule and allows one before a fragment. ref:DEC-grammar-carries-extraction-rules */
lexerRuleSpec
    : why = canonicalComment? FRAGMENT what = TOKEN_REF optionsSpec? COLON how = lexerRuleBlock SEMI # fragmentRule
    | why = canonicalComment what = TOKEN_REF optionsSpec? COLON how = lexerRuleBlock SEMI # lexerRule
    ;

/** The body of a lexer rule. */
lexerRuleBlock
    : lexerAltList
    ;

/** Lexer alternatives separated by bars. */
lexerAltList
    : lexerAlt (OR lexerAlt)*
    ;

/** A lexer alternative: its elements followed by optional commands, or nothing at all. */
lexerAlt
    : lexerElements lexerCommands?
    |
    // explicitly allow empty alts
    ;

/** The elements of a lexer alternative, possibly none. */
lexerElements
    : lexerElement+
    |
    ;

/** One lexer element: an atom or a block with an optional suffix, or an action that may be a predicate. */
lexerElement
    : lexerAtom ebnfSuffix?
    | lexerBlock ebnfSuffix?
    | actionBlock QUESTION?
    ;

// but preds can be anywhere

/** A parenthesised group of lexer alternatives. */
lexerBlock
    : LPAREN lexerAltList RPAREN
    ;

// E.g., channel(HIDDEN), skip, more, mode(INSIDE), push(INSIDE), pop

/** Commands such as skip, more, channel, and the mode changes, applied when the alternative matches. */
lexerCommands
    : RARROW lexerCommand (COMMA lexerCommand)*
    ;

/** One command, with or without an argument. */
lexerCommand
    : lexerCommandName LPAREN lexerCommandExpr RPAREN
    | lexerCommandName
    ;

/** A command name. The word mode is accepted here although it is a keyword elsewhere. */
lexerCommandName
    : identifier
    | MODE
    ;

/** A command argument: an identifier or an integer. */
lexerCommandExpr
    : identifier
    | INT
    ;

// --------------------
// Rule Alts

/** Parser alternatives separated by bars. */
altList
    : alternative (OR alternative)*
    ;

/** A parser alternative: optional element options followed by elements, or nothing at all. */
alternative
    : elementOptions? element+
    |
    // explicitly allow empty alts
    ;

/** One parser element: a labeled element, an atom, a block, or an action, each with an optional suffix or options. */
element
    : labeledElement (ebnfSuffix |)
    | atom (ebnfSuffix |)
    | ebnf
    | actionBlock QUESTION? predicateOptions?
    ;

/** Options attached to a semantic predicate, such as a failure message. */
predicateOptions
    : LT predicateOption (COMMA predicateOption)* GT
    ;

/** One predicate option, which unlike an element option may carry an action as its value. */
predicateOption
    : elementOption
    | identifier ASSIGN (actionBlock | INT | STRING_LITERAL)
    ;

/** An element bound to a label with = or +=, so that actions and listeners can reach it by name. */
labeledElement
    : identifier (ASSIGN | PLUS_ASSIGN) (atom | block)
    ;

// --------------------
// EBNF and blocks

/** A block with an optional repetition suffix. */
ebnf
    : block blockSuffix?
    ;

/** The suffix of a block. */
blockSuffix
    : ebnfSuffix
    ;

/** The repetition suffixes ?, *, and +, each with a non-greedy variant marked by a trailing question mark. */
ebnfSuffix
    : QUESTION QUESTION?
    | STAR QUESTION?
    | PLUS QUESTION?
    ;

/** The atoms a lexer rule can match: a character range, a terminal, a negated set, a character set, or any character. */
lexerAtom
    : characterRange
    | terminalDef
    | notSet
    | LEXER_CHAR_SET
    | wildcard
    ;

/** The atoms a parser rule can match: a terminal, a rule reference, a negated set, or any token. */
atom
    : terminalDef
    | ruleref
    | notSet
    | wildcard
    ;

/** The dot, matching any single character in a lexer rule or any token in a parser rule. */
wildcard
    : DOT elementOptions?
    ;

// --------------------
// Inverted element set
/** A negated set, matching anything except the listed elements. */
notSet
    : NOT setElement
    | NOT blockSet
    ;

/** A parenthesised list of set elements for a negation. */
blockSet
    : LPAREN setElement (OR setElement)* RPAREN
    ;

/** What may appear inside a set: a token reference, a literal, a character range, or a character set. */
setElement
    : TOKEN_REF elementOptions?
    | STRING_LITERAL elementOptions?
    | characterRange
    | LEXER_CHAR_SET
    ;

// -------------
// Grammar Block
/** A parenthesised group of alternatives, optionally with its own options and actions before a colon. */
block
    : LPAREN (optionsSpec? ruleAction* COLON)? altList RPAREN
    ;

// ----------------
// Parser rule ref
/** A reference to a parser rule, with optional arguments and options. */
ruleref
    : RULE_REF argActionBlock? elementOptions?
    ;

// ---------------
// Character Range
/** Two literals joined by .., matching any character between them inclusive. */
characterRange
    : STRING_LITERAL RANGE STRING_LITERAL
    ;

/** A token reference or a string literal, with optional element options. */
terminalDef
    : TOKEN_REF elementOptions?
    | STRING_LITERAL elementOptions?
    ;

// Terminals may be adorned with certain options when
// reference in the grammar: TOK<,,,>
/** Options in angle brackets on an element, such as assoc=right. */
elementOptions
    : LT elementOption (COMMA elementOption)* GT
    ;

/** One element option: a dotted name, or an identifier assigned a value. */
elementOption
    : qualifiedIdentifier
    | identifier ASSIGN (qualifiedIdentifier | STRING_LITERAL | INT)
    ;

/** An identifier is a rule reference or a token reference. The lexer decides which by the first letter's case. */
identifier
    : RULE_REF
    | TOKEN_REF
    ;

/** A dotted name, used in options and in imports. */
qualifiedIdentifier
    : identifier (DOT identifier)*
    ;

/** A canonical comment: the Why of the unit it precedes, holding prose, reference citations, and license citations between its delimiters. ref:DEC-comment-reasons ref:DEC-grammar-carries-extraction-rules */
canonicalComment
    : DocOpen docPart* DocClose
    ;

/** One piece of a canonical comment: a reference citation, a license citation, or prose. ref:DEC-grammar-carries-extraction-rules */
docPart
    : ref = DocRef
    | license = DocLicense
    | DocWord
    | DocPunct
    ;
