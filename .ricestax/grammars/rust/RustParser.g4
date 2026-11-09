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

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

parser grammar RustParser;

// Insert here @header for C++ parser.

// canon: canon's interpreter has no port of RustParserBase; the two predicates that called into it
// are dropped from shl and shr below.
options
{
    tokenVocab = RustLexer;
    superClass = RustParserBase;
}

// entry point
// 4
crate
    : innerAttribute* item* EOF
    ;

// 3
macroInvocation
    : simplePath NOT delimTokenTree
    ;

delimTokenTree
    : LPAREN tokenTree* RPAREN
    | LSQUAREBRACKET tokenTree* RSQUAREBRACKET
    | LCURLYBRACE tokenTree* RCURLYBRACE
    ;

// canon: one token per tokenTree rather than a run of them, since tokenTree* over runs splits n
// tokens in exponentially many ways; canon's parser keeps every split, and a long macro body took
// minutes. The language is the same.
tokenTree
    : tokenTreeToken
    | delimTokenTree
    ;

tokenTreeToken
    : macroIdentifierLikeToken
    | macroLiteralToken
    | macroPunctuationToken
    | macroRepOp
    | DOLLAR
    ;

macroInvocationSemi
    : simplePath NOT LPAREN tokenTree* RPAREN SEMI
    | simplePath NOT LSQUAREBRACKET tokenTree* RSQUAREBRACKET SEMI
    | simplePath NOT LCURLYBRACE tokenTree* RCURLYBRACE
    ;

// 3.1
// canon: a declarative macro 2.0, macro name($x:expr) { ... } or macro name { rules }, which the
// standard library defines under the decl_macro feature, is a macro definition too.
macroRulesDefinition
    : itemPrefix (KW_MACRORULES NOT identifier macroRulesDef | KW_MACRO identifier (LPAREN tokenTree* RPAREN)? delimTokenTree)
    ;

macroRulesDef
    : LPAREN macroRules RPAREN SEMI
    | LSQUAREBRACKET macroRules RSQUAREBRACKET SEMI
    | LCURLYBRACE macroRules RCURLYBRACE
    ;

macroRules
    : macroRule (SEMI macroRule)* SEMI?
    ;

macroRule
    : macroMatcher FATARROW macroTranscriber
    ;

macroMatcher
    : LPAREN macroMatch* RPAREN
    | LSQUAREBRACKET macroMatch* RSQUAREBRACKET
    | LCURLYBRACE macroMatch* RCURLYBRACE
    ;

// canon: one token per macroMatch rather than a run of them, for the reason given at tokenTree.
macroMatch
    : macroMatchToken
    | macroMatcher
    // canon: a metavariable may be named by any keyword, as anyhow's $let:tt is, not only self, or by
    // an underscore, as $_:ident.
    | DOLLAR (identifier | keyword | UNDERSCORE) COLON macroFragSpec
    | DOLLAR LPAREN macroMatch+ RPAREN macroRepSep? macroRepOp
    ;

macroMatchToken
    : macroIdentifierLikeToken
    | macroLiteralToken
    | macroPunctuationToken
    | macroRepOp
    ;

macroFragSpec
    : identifier // do validate here is wasting token
    ;

macroRepSep
    : macroIdentifierLikeToken
    | macroLiteralToken
    | macroPunctuationToken
    | DOLLAR
    ;

macroRepOp
    : STAR
    | PLUS
    | QUESTION
    ;

macroTranscriber
    : delimTokenTree
    ;

//configurationPredicate
// : configurationOption | configurationAll | configurationAny | configurationNot ; configurationOption: identifier (
// EQ (STRING_LITERAL | RAW_STRING_LITERAL))?; configurationAll: 'all' LPAREN configurationPredicateList? RPAREN;
// configurationAny: 'any' LPAREN configurationPredicateList? RPAREN; configurationNot: 'not' LPAREN configurationPredicate RPAREN;

//configurationPredicateList
// : configurationPredicate (COMMA configurationPredicate)* COMMA? ; cfgAttribute: 'cfg' LPAREN configurationPredicate RPAREN;
// cfgAttrAttribute: 'cfg_attr' LPAREN configurationPredicate COMMA cfgAttrs? RPAREN; cfgAttrs: attr (COMMA attr)* COMMA?;

// 6
// canon: the outer attributes and the visibility of an item move from item into each kind of item,
// through itemPrefix, so that the parse-tree node of a function, struct, impl, and so on starts at its
// first attribute. canon binds the doc comment on the line directly above a unit to it, and in Rust
// that line is usually above the attributes. Each attribute is labeled marker, which canon reads to
// recognise #[test] functions. The same move is made in associatedItem and externalItem.
item
    : visItem
    | macroItem
    ;

visItem
    : module
    | externCrate
    | useDeclaration
    | function_
    | typeAlias
    | struct_
    | enumeration
    | union_
    | constantItem
    | staticItem
    | trait_
    | implementation
    | externBlock
    ;

macroItem
    : itemPrefix macroInvocationSemi
    | macroRulesDefinition
    ;

// canon: #[macro_export] is labeled required, since it makes a macro_rules macro visible outside
// its crate, as pub makes other items.
itemPrefix
    : (required = macroExportAttribute | marker += outerAttribute)* visibility?
    ;

macroExportAttribute
    : POUND LSQUAREBRACKET 'macro_export' RSQUAREBRACKET
    ;

// 6.1
module
    : itemPrefix KW_UNSAFE? KW_MOD identifier (SEMI | LCURLYBRACE innerAttribute* item* RCURLYBRACE)
    ;

// 6.2
externCrate
    : itemPrefix KW_EXTERN KW_CRATE crateRef asClause? SEMI
    ;

crateRef
    : identifier
    | KW_SELFVALUE
    ;

asClause
    : KW_AS (identifier | UNDERSCORE)
    ;

// 6.3
useDeclaration
    : itemPrefix KW_USE useTree SEMI
    ;

useTree
    : (simplePath? PATHSEP)? (STAR | LCURLYBRACE ( useTree (COMMA useTree)* COMMA?)? RCURLYBRACE)
    | simplePath (KW_AS (identifier | UNDERSCORE))?
    ;

// 6.4
function_
    : itemPrefix functionQualifiers KW_FN identifier genericParams? LPAREN functionParameters? RPAREN functionReturnType? whereClause? (
        blockExpression
        | SEMI
    )
    ;

// canon: an item in an unsafe extern block may be marked safe, as Rust 2024 allows; and default
// (specialization) and final (final trait methods) are the standard library's own qualifiers.
functionQualifiers
    : ('default' | KW_FINAL)? KW_CONST? KW_ASYNC? (KW_UNSAFE | 'safe')? (KW_EXTERN abi?)?
    ;

abi
    : STRING_LITERAL
    | RAW_STRING_LITERAL
    ;

functionParameters
    : selfParam COMMA?
    | (selfParam COMMA)? functionParam (COMMA functionParam)* COMMA?
    ;

selfParam
    : outerAttribute* (shorthandSelf | typedSelf)
    ;

shorthandSelf
    : (AND lifetime?)? KW_MUT? KW_SELFVALUE
    ;

typedSelf
    : KW_MUT? KW_SELFVALUE COLON type_
    ;

functionParam
    : outerAttribute* (functionParamPattern | DOTDOTDOT | type_)
    ;

functionParamPattern
    : pattern COLON (type_ | DOTDOTDOT)
    ;

functionReturnType
    : RARROW type_
    ;

// 6.5
// canon: an associated type may have bounds, as in type Buffer: 'static; which the upstream rule
// rejected; the Rust reference allows them.
// canon: a where clause may also follow the type, as Rust 1.61 prefers for a generic associated
// type, and an associated type of a specializing impl may be marked default.
typeAlias
    : itemPrefix 'default'? KW_TYPE identifier genericParams? (COLON typeParamBounds?)? whereClause? (EQ type_ whereClause?)? SEMI
    ;

// 6.6
struct_
    : structStruct
    | tupleStruct
    ;

structStruct
    : itemPrefix KW_STRUCT identifier genericParams? whereClause? (LCURLYBRACE structFields? RCURLYBRACE | SEMI)
    ;

tupleStruct
    : itemPrefix KW_STRUCT identifier genericParams? LPAREN tupleFields? RPAREN whereClause? SEMI
    ;

structFields
    : structField (COMMA structField)* COMMA?
    ;

structField
    : outerAttribute* visibility? identifier COLON type_
    ;

tupleFields
    : tupleField (COMMA tupleField)* COMMA?
    ;

tupleField
    : outerAttribute* visibility? type_
    ;

// 6.7
// canon: the variants are labeled inherited, so a variant needs a comment when its enum does.
enumeration
    : itemPrefix KW_ENUM identifier genericParams? whereClause? LCURLYBRACE (inherited = enumItems)? RCURLYBRACE
    ;

enumItems
    : enumItem (COMMA enumItem)* COMMA?
    ;

enumItem
    : outerAttribute* visibility? identifier (
        enumItemTuple
        | enumItemStruct
        | enumItemDiscriminant
    )?
    ;

enumItemTuple
    : LPAREN tupleFields? RPAREN
    ;

enumItemStruct
    : LCURLYBRACE structFields? RCURLYBRACE
    ;

enumItemDiscriminant
    : EQ expression
    ;

// 6.8
union_
    : itemPrefix KW_UNION identifier genericParams? whereClause? LCURLYBRACE structFields RCURLYBRACE
    ;

// 6.9
// canon: an associated constant of a specializing impl may be marked default.
constantItem
    : itemPrefix 'default'? KW_CONST (identifier | UNDERSCORE) COLON type_ (EQ expression)? SEMI
    ;

// 6.10
// canon: a static in an unsafe extern block may be marked safe or unsafe, as Rust 2024 allows.
staticItem
    : itemPrefix (KW_UNSAFE | 'safe')? KW_STATIC KW_MUT? identifier COLON type_ (EQ expression)? SEMI
    ;

// 6.11
// canon: the items of a trait are labeled inherited: an item needs a comment when the trait does,
// since it is as visible as the trait and says no pub of its own.
// canon: a trait alias, trait A = B;, and the standard library's auto, const, and impl-restricted
// traits, pub impl(crate) trait, are traits too.
trait_
    : itemPrefix implRestriction? KW_CONST? KW_UNSAFE? 'auto'? KW_TRAIT identifier genericParams? (COLON typeParamBounds?)? whereClause? (
        LCURLYBRACE innerAttribute* (inherited += associatedItem)* RCURLYBRACE
        | EQ typeParamBounds? whereClause? SEMI
    )
    ;

// canon: an impl restriction limits where a trait may be implemented, as visibility limits where it
// may be named.
implRestriction
    : KW_IMPL LPAREN (KW_CRATE | KW_SELFVALUE | KW_SUPER | KW_IN simplePath) RPAREN
    ;

// 6.12
implementation
    : inherentImpl
    | traitImpl
    ;

// canon: the standard library's const impls, const impl<T> X<T> and impl<T> const Trait for X<T>, and
// specializing default impls are impls too.
inherentImpl
    : itemPrefix KW_CONST? KW_IMPL genericParams? type_ whereClause? LCURLYBRACE innerAttribute* associatedItem* RCURLYBRACE
    ;

// canon: the trait and the self type of a trait impl are one rule, traitImplTarget, which names it,
// so the impls of one type for different traits are told apart by their traits.
traitImpl
    : itemPrefix 'default'? KW_CONST? KW_UNSAFE? KW_IMPL genericParams? KW_CONST? traitImplTarget whereClause? LCURLYBRACE innerAttribute* associatedItem* RCURLYBRACE
    ;

traitImplTarget
    : NOT? typePath KW_FOR type_
    ;

// 6.13
externBlock
    : itemPrefix KW_UNSAFE? KW_EXTERN abi? LCURLYBRACE innerAttribute* externalItem* RCURLYBRACE
    ;

// canon: an extern block may also declare a type, as the extern_types feature allows.
externalItem
    : itemPrefix macroInvocationSemi
    | staticItem
    | function_
    | typeAlias
    ;

// 6.14
genericParams
    : LT ((genericParam COMMA)* genericParam COMMA?)? GT
    ;

genericParam
    : outerAttribute* (lifetimeParam | typeParam | constParam)
    ;

lifetimeParam
    : outerAttribute? LIFETIME_OR_LABEL (COLON lifetimeBounds)?
    ;

typeParam
    : outerAttribute? identifier (COLON typeParamBounds?)? (EQ type_)?
    ;

// canon: a const parameter may have a default, as const N: usize = 3 or = { expr }.
constParam
    : KW_CONST identifier COLON type_ (EQ genericArgsConst)?
    ;

whereClause
    : KW_WHERE (whereClauseItem COMMA)* whereClauseItem?
    ;

whereClauseItem
    : lifetimeWhereClauseItem
    | typeBoundWhereClauseItem
    ;

lifetimeWhereClauseItem
    : lifetime COLON lifetimeBounds
    ;

typeBoundWhereClauseItem
    : forLifetimes? type_ COLON typeParamBounds?
    ;

forLifetimes
    : KW_FOR genericParams
    ;

// 6.15
associatedItem
    : itemPrefix macroInvocationSemi
    | typeAlias
    | constantItem
    | function_
    ;

// 7
innerAttribute
    : POUND NOT LSQUAREBRACKET attr RSQUAREBRACKET
    ;

outerAttribute
    : POUND LSQUAREBRACKET attr RSQUAREBRACKET
    ;

// canon: an unsafe attribute, #[unsafe(no_mangle)], is stable since Rust 1.82; and the value of an
// attribute may be any expression, as #[doc = include_str!("x.md")] or #[doc = concat!(..)].
attr
    : simplePath attrInput?
    | KW_UNSAFE LPAREN attr RPAREN
    ;

attrInput
    : delimTokenTree
    | EQ expression
    ;

//metaItem
// : simplePath ( EQ literalExpression //w | LPAREN metaSeq RPAREN )? ; metaSeq: metaItemInner (COMMA metaItemInner)* COMMA?;
// metaItemInner: metaItem | literalExpression; // w

//metaWord: identifier; metaNameValueStr: identifier EQ ( STRING_LITERAL | RAW_STRING_LITERAL); metaListPaths:
// identifier LPAREN ( simplePath (COMMA simplePath)* COMMA?)? RPAREN; metaListIdents: identifier LPAREN ( identifier (COMMA
// identifier)* COMMA?)? RPAREN; metaListNameValueStr : identifier LPAREN (metaNameValueStr ( COMMA metaNameValueStr)* COMMA?)? RPAREN
// ;

// 8
statement
    : SEMI
    | item
    | letStatement
    | expressionStatement
    | macroInvocationSemi
    ;

// canon: let else, stable since Rust 1.65, and the standard library's super let.
letStatement
    : outerAttribute* KW_SUPER? KW_LET patternNoTopAlt (COLON type_)? (EQ expression (KW_ELSE blockExpression)?)? SEMI
    ;

expressionStatement
    : expression SEMI
    | expressionWithBlock SEMI?
    ;

// 8.2
expression
    : outerAttribute+ expression                                     # AttributedExpression // technical, remove left recursive
    | literalExpression                                              # LiteralExpression_
    | pathExpression                                                 # PathExpression_
    | expression DOT pathExprSegment LPAREN callParams? RPAREN       # MethodCallExpression          // 8.2.10
    | expression DOT identifier                                      # FieldExpression               // 8.2.11
    | expression DOT tupleIndex                                      # TupleIndexingExpression       // 8.2.7
    | expression DOT KW_AWAIT                                        # AwaitExpression               // 8.2.18
    | expression LPAREN callParams? RPAREN                           # CallExpression                // 8.2.9
    | expression LSQUAREBRACKET expression RSQUAREBRACKET            # IndexExpression               // 8.2.6
    | expression QUESTION                                            # ErrorPropagationExpression    // 8.2.4
    // canon: a raw borrow, &raw const x or &raw mut x, stable since Rust 1.82.
    | (AND | ANDAND) (KW_MUT | 'raw' (KW_CONST | KW_MUT))? expression # BorrowExpression              // 8.2.4
    | STAR expression                                                # DereferenceExpression         // 8.2.4
    | (MINUS | NOT) expression                                         # NegationExpression            // 8.2.4
    | expression KW_AS typeNoBounds                                  # TypeCastExpression            // 8.2.4
    | expression (STAR | SLASH | PERCENT) expression                  # ArithmeticOrLogicalExpression // 8.2.4
    | expression (PLUS | MINUS) expression                            # ArithmeticOrLogicalExpression // 8.2.4
    | expression (shl | shr) expression                              # ArithmeticOrLogicalExpression // 8.2.4
    | expression AND expression                                      # ArithmeticOrLogicalExpression // 8.2.4
    | expression CARET expression                                    # ArithmeticOrLogicalExpression // 8.2.4
    | expression OR expression                                       # ArithmeticOrLogicalExpression // 8.2.4
    | expression comparisonOperator expression                       # ComparisonExpression          // 8.2.4
    | expression ANDAND expression                                   # LazyBooleanExpression         // 8.2.4
    | expression OROR expression                                     # LazyBooleanExpression         // 8.2.4
    | expression DOTDOT expression?                                  # RangeExpression               // 8.2.14
    | DOTDOT expression?                                             # RangeExpression               // 8.2.14
    | DOTDOTEQ expression                                            # RangeExpression               // 8.2.14
    | expression DOTDOTEQ expression                                 # RangeExpression               // 8.2.14
    | expression EQ expression                                       # AssignmentExpression          // 8.2.4
    | expression compoundAssignOperator expression                   # CompoundAssignmentExpression  // 8.2.4
    | KW_CONTINUE LIFETIME_OR_LABEL? expression?                     # ContinueExpression            // 8.2.13
    | KW_BREAK LIFETIME_OR_LABEL? expression?                        # BreakExpression               // 8.2.13
    | KW_RETURN expression?                                          # ReturnExpression              // 8.2.17
    | LPAREN innerAttribute* expression RPAREN                       # GroupedExpression             // 8.2.5
    | LSQUAREBRACKET innerAttribute* arrayElements? RSQUAREBRACKET   # ArrayExpression               // 8.2.6
    | LPAREN innerAttribute* tupleElements? RPAREN                   # TupleExpression               // 8.2.7
    | structExpression                                               # StructExpression_             // 8.2.8
    | enumerationVariantExpression                                   # EnumerationVariantExpression_
    | closureExpression                                              # ClosureExpression_            // 8.2.12
    | expressionWithBlock                                            # ExpressionWithBlock_
    | macroInvocation                                                # MacroInvocationAsExpression
    // canon: the underscore expression, the left side of a destructuring assignment such as _ = x;
    // stable since Rust 1.59.
    | UNDERSCORE                                                     # UnderscoreExpression
    ;

comparisonOperator
    : EQEQ
    | NE
    | GT
    | LT
    | GE
    | LE
    ;

compoundAssignOperator
    : PLUSEQ
    | MINUSEQ
    | STAREQ
    | SLASHEQ
    | PERCENTEQ
    | ANDEQ
    | OREQ
    | CARETEQ
    | SHLEQ
    | SHREQ
    ;

// canon: an inline const block, const { ... }, stable since Rust 1.79, a labeled block, 'a: { ... },
// stable since Rust 1.65, and the standard library's try block, try { ... }.
expressionWithBlock
    : outerAttribute+ expressionWithBlock // technical
    | blockExpression
    | asyncBlockExpression
    | unsafeBlockExpression
    | KW_CONST blockExpression
    | loopLabel blockExpression
    | KW_TRY blockExpression
    | loopExpression
    | ifExpression
    | ifLetExpression
    | matchExpression
    ;

// 8.2.1
// canon: C string literals; and a float written with a bare trailing dot, 1., which the lexer reads
// as an integer and a dot, since it cannot tell it from the 1 of 1..2 or 1.max(2) without upstream's
// base-class predicates.
literalExpression
    : CHAR_LITERAL
    | STRING_LITERAL
    | RAW_STRING_LITERAL
    | BYTE_LITERAL
    | BYTE_STRING_LITERAL
    | RAW_BYTE_STRING_LITERAL
    | C_STRING_LITERAL
    | RAW_C_STRING_LITERAL
    | INTEGER_LITERAL
    | FLOAT_LITERAL
    | INTEGER_LITERAL DOT
    | KW_TRUE
    | KW_FALSE
    ;

// 8.2.2
pathExpression
    : pathInExpression
    | qualifiedPathInExpression
    ;

// 8.2.3
blockExpression
    : LCURLYBRACE innerAttribute* statements? RCURLYBRACE
    ;

statements
    : statement+ expression?
    | expression
    ;

asyncBlockExpression
    : KW_ASYNC KW_MOVE? blockExpression
    ;

unsafeBlockExpression
    : KW_UNSAFE blockExpression
    ;

// 8.2.6
arrayElements
    : expression (COMMA expression)* COMMA?
    | expression SEMI expression
    ;

// 8.2.7
tupleElements
    : (expression COMMA)+ expression?
    ;

// canon: without the lexer's base-class predicate, the 0.1 of x.0.1 lexes as one float, which is
// two tuple indices here.
tupleIndex
    : INTEGER_LITERAL
    | FLOAT_LITERAL
    ;

// 8.2.8
structExpression
    : structExprStruct
    | structExprTuple
    | structExprUnit
    ;

structExprStruct
    : pathInExpression LCURLYBRACE innerAttribute* (structExprFields | structBase)? RCURLYBRACE
    ;

structExprFields
    : structExprField (COMMA structExprField)* (COMMA structBase | COMMA?)
    ;

// outerAttribute here is not in doc
structExprField
    : outerAttribute* (identifier | (identifier | tupleIndex) COLON expression)
    ;

structBase
    : DOTDOT expression
    ;

structExprTuple
    : pathInExpression LPAREN innerAttribute* (expression ( COMMA expression)* COMMA?)? RPAREN
    ;

structExprUnit
    : pathInExpression
    ;

enumerationVariantExpression
    : enumExprStruct
    | enumExprTuple
    | enumExprFieldless
    ;

enumExprStruct
    : pathInExpression LCURLYBRACE enumExprFields? RCURLYBRACE
    ;

enumExprFields
    : enumExprField (COMMA enumExprField)* COMMA?
    ;

enumExprField
    : identifier
    | (identifier | tupleIndex) COLON expression
    ;

enumExprTuple
    : pathInExpression LPAREN (expression (COMMA expression)* COMMA?)? RPAREN
    ;

enumExprFieldless
    : pathInExpression
    ;

// 8.2.9
callParams
    : expression (COMMA expression)* COMMA?
    ;

// 8.2.12
// canon: an async closure, async move |x| ..., stable since Rust 1.85, and the standard library's
// const closure, const |x| ....
closureExpression
    : KW_CONST? KW_ASYNC? KW_MOVE? (OROR | OR closureParameters? OR) (expression | RARROW typeNoBounds blockExpression)
    ;

closureParameters
    : closureParam (COMMA closureParam)* COMMA?
    ;

closureParam
    : outerAttribute* pattern (COLON type_)?
    ;

// 8.2.13
loopExpression
    : loopLabel? (
        infiniteLoopExpression
        | predicateLoopExpression
        | predicatePatternLoopExpression
        | iteratorLoopExpression
    )
    ;

infiniteLoopExpression
    : KW_LOOP blockExpression
    ;

// canon: the condition may chain let bindings, as condition below says.
predicateLoopExpression
    : KW_WHILE condition /*except structExpression*/ blockExpression
    ;

predicatePatternLoopExpression
    : KW_WHILE KW_LET pattern EQ expression blockExpression
    ;

iteratorLoopExpression
    : KW_FOR pattern KW_IN expression blockExpression
    ;

loopLabel
    : LIFETIME_OR_LABEL COLON
    ;

// 8.2.15
ifExpression
    : KW_IF condition blockExpression (KW_ELSE (blockExpression | ifExpression | ifLetExpression))?
    ;

// canon: the condition of an if, a while, or a match guard may chain let bindings with &&, as
// if let Some(x) = a && x > 0, stable since Rust 1.88.
condition
    : conditionOperand (ANDAND conditionOperand)*
    ;

conditionOperand
    : KW_LET pattern EQ expression
    | expression
    ;

ifLetExpression
    : KW_IF KW_LET pattern EQ expression blockExpression (
        KW_ELSE (blockExpression | ifExpression | ifLetExpression)
    )?
    ;

// 8.2.16
matchExpression
    : KW_MATCH expression LCURLYBRACE innerAttribute* matchArms? RCURLYBRACE
    ;

matchArms
    : (matchArm FATARROW matchArmExpression)* matchArm FATARROW expression COMMA?
    ;

matchArmExpression
    : expression COMMA
    | expressionWithBlock COMMA?
    ;

matchArm
    : outerAttribute* pattern matchArmGuard?
    ;

// canon: a guard may chain let bindings, as condition says.
matchArmGuard
    : KW_IF condition
    ;

// 9
pattern
    : OR? patternNoTopAlt (OR patternNoTopAlt)*
    ;

patternNoTopAlt
    : patternWithoutRange
    | rangePattern
    ;

patternWithoutRange
    : literalPattern
    | identifierPattern
    | wildcardPattern
    | restPattern
    | referencePattern
    | structPattern
    | tupleStructPattern
    | tuplePattern
    | groupedPattern
    | slicePattern
    | pathPattern
    | macroInvocation
    ;

// canon: C string literals are patterns too.
literalPattern
    : KW_TRUE
    | KW_FALSE
    | CHAR_LITERAL
    | BYTE_LITERAL
    | STRING_LITERAL
    | RAW_STRING_LITERAL
    | BYTE_STRING_LITERAL
    | RAW_BYTE_STRING_LITERAL
    | C_STRING_LITERAL
    | RAW_C_STRING_LITERAL
    | MINUS? INTEGER_LITERAL
    | MINUS? FLOAT_LITERAL
    ;

identifierPattern
    : KW_REF? KW_MUT? identifier (AT pattern)?
    ;

wildcardPattern
    : UNDERSCORE
    ;

restPattern
    : DOTDOT
    ;

// canon: an exclusive range pattern, a..b, stable since Rust 1.80, and a range pattern open at its
// start, ..=b, stable since Rust 1.66, or ..b, as the standard library writes.
rangePattern
    : rangePatternBound DOTDOTEQ rangePatternBound # InclusiveRangePattern
    | rangePatternBound DOTDOT rangePatternBound   # ExclusiveRangePattern
    | rangePatternBound DOTDOT                    # HalfOpenRangePattern
    | DOTDOTEQ rangePatternBound                  # InclusiveRangePattern
    | DOTDOT rangePatternBound                    # ExclusiveRangePattern
    | rangePatternBound DOTDOTDOT rangePatternBound # ObsoleteRangePattern
    ;

rangePatternBound
    : CHAR_LITERAL
    | BYTE_LITERAL
    | MINUS? INTEGER_LITERAL
    | MINUS? FLOAT_LITERAL
    | pathPattern
    ;

referencePattern
    : (AND | ANDAND) KW_MUT? patternWithoutRange
    ;

structPattern
    : pathInExpression LCURLYBRACE structPatternElements? RCURLYBRACE
    ;

structPatternElements
    : structPatternFields (COMMA structPatternEtCetera?)?
    | structPatternEtCetera
    ;

structPatternFields
    : structPatternField (COMMA structPatternField)*
    ;

structPatternField
    : outerAttribute* (tupleIndex COLON pattern | identifier COLON pattern | KW_REF? KW_MUT? identifier)
    ;

structPatternEtCetera
    : outerAttribute* DOTDOT
    ;

tupleStructPattern
    : pathInExpression LPAREN tupleStructItems? RPAREN
    ;

tupleStructItems
    : pattern (COMMA pattern)* COMMA?
    ;

tuplePattern
    : LPAREN tuplePatternItems? RPAREN
    ;

tuplePatternItems
    : pattern COMMA
    | restPattern
    | pattern (COMMA pattern)+ COMMA?
    ;

groupedPattern
    : LPAREN pattern RPAREN
    ;

slicePattern
    : LSQUAREBRACKET slicePatternItems? RSQUAREBRACKET
    ;

slicePatternItems
    : pattern (COMMA pattern)* COMMA?
    ;

pathPattern
    : pathInExpression
    | qualifiedPathInExpression
    ;

// 10.1
type_
    : typeNoBounds
    | implTraitType
    | traitObjectType
    ;

typeNoBounds
    : parenthesizedType
    | implTraitTypeOneBound
    | traitObjectTypeOneBound
    | typePath
    | tupleType
    | neverType
    | rawPointerType
    | referenceType
    | arrayType
    | sliceType
    | inferredType
    | qualifiedPathInType
    | bareFunctionType
    | macroInvocation
    ;

parenthesizedType
    : LPAREN type_ RPAREN
    ;

// 10.1.4
neverType
    : NOT
    ;

// 10.1.5
tupleType
    : LPAREN ((type_ COMMA)+ type_?)? RPAREN
    ;

// 10.1.6
arrayType
    : LSQUAREBRACKET type_ SEMI expression RSQUAREBRACKET
    ;

// 10.1.7
sliceType
    : LSQUAREBRACKET type_ RSQUAREBRACKET
    ;

// 10.1.13
// canon: && before a type is two references, &&str being & &str, since the lexer reads && as one
// token, as the pattern and borrow rules already allow.
referenceType
    : AND lifetime? KW_MUT? typeNoBounds
    | ANDAND lifetime? KW_MUT? typeNoBounds
    ;

rawPointerType
    : STAR (KW_MUT | KW_CONST) typeNoBounds
    ;

// 10.1.14
bareFunctionType
    : forLifetimes? functionTypeQualifiers KW_FN LPAREN functionParametersMaybeNamedVariadic? RPAREN bareFunctionReturnType?
    ;

functionTypeQualifiers
    : KW_UNSAFE? (KW_EXTERN abi?)?
    ;

bareFunctionReturnType
    : RARROW typeNoBounds
    ;

functionParametersMaybeNamedVariadic
    : maybeNamedFunctionParameters
    | maybeNamedFunctionParametersVariadic
    ;

maybeNamedFunctionParameters
    : maybeNamedParam (COMMA maybeNamedParam)* COMMA?
    ;

maybeNamedParam
    : outerAttribute* ((identifier | UNDERSCORE) COLON)? type_
    ;

// canon: the variadic part may be named, as in fn(_: *mut T, _: ...).
maybeNamedFunctionParametersVariadic
    : (maybeNamedParam COMMA)* maybeNamedParam COMMA outerAttribute* ((identifier | UNDERSCORE) COLON)? DOTDOTDOT
    ;

// 10.1.15
traitObjectType
    : KW_DYN? typeParamBounds
    ;

traitObjectTypeOneBound
    : KW_DYN? traitBound
    ;

implTraitType
    : KW_IMPL typeParamBounds
    ;

implTraitTypeOneBound
    : KW_IMPL traitBound
    ;

// 10.1.18
inferredType
    : UNDERSCORE
    ;

// 10.6
typeParamBounds
    : typeParamBound (PLUS typeParamBound)* PLUS?
    ;

// canon: a precise capturing bound, use<'a, T>, stable since Rust 1.82.
typeParamBound
    : lifetime
    | traitBound
    | KW_USE genericArgs
    ;

// canon: a bound may be async, async Fn(), stable since Rust 1.85, and the standard library's const
// trait bounds, [const] Trait, ~const Trait, and const Trait, are bounds too.
traitBound
    : QUESTION? forLifetimes? boundModifiers typePath
    | LPAREN QUESTION? forLifetimes? boundModifiers typePath RPAREN
    ;

boundModifiers
    : (LSQUAREBRACKET KW_CONST RSQUAREBRACKET | TILDE KW_CONST | KW_CONST)? KW_ASYNC?
    ;

lifetimeBounds
    : (lifetime PLUS)* lifetime?
    ;

lifetime
    : LIFETIME_OR_LABEL
    | KW_STATICLIFETIME
    | KW_UNDERLINELIFETIME
    ;

// 12.4
simplePath
    : PATHSEP? simplePathSegment (PATHSEP simplePathSegment)*
    ;

simplePathSegment
    : identifier
    | KW_SUPER
    | KW_SELFVALUE
    | KW_CRATE
    | KW_DOLLARCRATE
    ;

pathInExpression
    : PATHSEP? pathExprSegment (PATHSEP pathExprSegment)*
    ;

pathExprSegment
    : pathIdentSegment (PATHSEP genericArgs)?
    ;

pathIdentSegment
    : identifier
    | KW_SUPER
    | KW_SELFVALUE
    | KW_SELFTYPE
    | KW_CRATE
    | KW_DOLLARCRATE
    ;

//TODO: let x : T<_>=something;
genericArgs
    : LT GT
    | LT genericArgsLifetimes (COMMA genericArgsTypes)? (COMMA genericArgsBindings)? COMMA? GT
    | LT genericArgsTypes (COMMA genericArgsBindings)? COMMA? GT
    | LT (genericArg COMMA)* genericArg COMMA? GT
    ;

// canon: an associated type bound, Iterator<Item: Debug>, stable since Rust 1.79, and a binding of a
// generic associated type, Item<'a> = &'a T.
genericArg
    : lifetime
    | type_
    | genericArgsConst
    | genericArgsBinding
    | identifier genericArgs? COLON typeParamBounds
    ;

genericArgsConst
    : blockExpression
    | MINUS? literalExpression
    | simplePathSegment
    ;

genericArgsLifetimes
    : lifetime (COMMA lifetime)*
    ;

genericArgsTypes
    : type_ (COMMA type_)*
    ;

genericArgsBindings
    : genericArgsBinding (COMMA genericArgsBinding)*
    ;

// canon: a generic associated type is bound with its arguments, Item<'a> = &'a T.
genericArgsBinding
    : identifier genericArgs? EQ type_
    ;

qualifiedPathInExpression
    : qualifiedPathType (PATHSEP pathExprSegment)+
    ;

qualifiedPathType
    : LT type_ (KW_AS typePath)? GT
    ;

qualifiedPathInType
    : qualifiedPathType (PATHSEP typePathSegment)+
    ;

typePath
    : PATHSEP? typePathSegment (PATHSEP typePathSegment)*
    ;

typePathSegment
    : pathIdentSegment PATHSEP? (genericArgs | typePathFn)?
    ;

typePathFn
    : LPAREN typePathInputs? RPAREN (RARROW type_)?
    ;

typePathInputs
    : type_ (COMMA type_)* COMMA?
    ;

// 12.6
// canon: a bare pub is labeled required, since it makes an item visible outside its crate; pub(crate),
// pub(super), pub(self), and pub(in path) do not.
visibility
    : KW_PUB LPAREN (KW_CRATE | KW_SELFVALUE | KW_SUPER | KW_IN simplePath) RPAREN
    | required = KW_PUB
    ;

// technical
// canon: union is a weak keyword, a keyword only before a union's name, so it is also an identifier,
// as in the method call a.union(b). async, try, and dyn are identifiers in the 2015 edition, which
// canon reads without knowing a crate's edition, so they are identifiers too.
identifier
    : NON_KEYWORD_IDENTIFIER
    | RAW_IDENTIFIER
    | KW_MACRORULES
    | KW_UNION
    | KW_ASYNC
    | KW_TRY
    | KW_DYN
    ;

keyword
    : KW_AS
    | KW_BREAK
    | KW_CONST
    | KW_CONTINUE
    | KW_CRATE
    | KW_ELSE
    | KW_ENUM
    | KW_EXTERN
    | KW_FALSE
    | KW_FN
    | KW_FOR
    | KW_IF
    | KW_IMPL
    | KW_IN
    | KW_LET
    | KW_LOOP
    | KW_MATCH
    | KW_MOD
    | KW_MOVE
    | KW_MUT
    | KW_PUB
    | KW_REF
    | KW_RETURN
    | KW_SELFVALUE
    | KW_SELFTYPE
    | KW_STATIC
    | KW_STRUCT
    | KW_SUPER
    | KW_TRAIT
    | KW_TRUE
    | KW_TYPE
    | KW_UNSAFE
    | KW_USE
    | KW_WHERE
    | KW_WHILE

    // 2018+
    | KW_ASYNC
    | KW_AWAIT
    | KW_DYN
    // reserved
    | KW_ABSTRACT
    | KW_BECOME
    | KW_BOX
    | KW_DO
    | KW_FINAL
    | KW_MACRO
    | KW_OVERRIDE
    | KW_PRIV
    | KW_TYPEOF
    | KW_UNSIZED
    | KW_VIRTUAL
    | KW_YIELD
    | KW_TRY
    | KW_UNION
    | KW_STATICLIFETIME
    ;

macroIdentifierLikeToken
    : keyword
    | identifier
    | KW_MACRORULES
    | KW_UNDERLINELIFETIME
    | KW_DOLLARCRATE
    | LIFETIME_OR_LABEL
    ;

macroLiteralToken
    : literalExpression
    ;

// macroDelimiterToken: LCURLYBRACE | RCURLYBRACE | LSQUAREBRACKET | RSQUAREBRACKET | LPAREN | RPAREN;
macroPunctuationToken
    : MINUS
    //| PLUS | STAR
    | SLASH
    | PERCENT
    | CARET
    | NOT
    | AND
    | OR
    | ANDAND
    | OROR
    // already covered by LT and GT in macro | shl | shr
    | PLUSEQ
    | MINUSEQ
    | STAREQ
    | SLASHEQ
    | PERCENTEQ
    | CARETEQ
    | ANDEQ
    | OREQ
    | SHLEQ
    | SHREQ
    | EQ
    | EQEQ
    | NE
    | GT
    | LT
    | GE
    | LE
    | AT
    | UNDERSCORE
    | DOT
    | DOTDOT
    | DOTDOTDOT
    | DOTDOTEQ
    | COMMA
    | SEMI
    | COLON
    | PATHSEP
    | RARROW
    | FATARROW
    | POUND
    // canon: the tilde, which the lexer now has.
    | TILDE
    //| DOLLAR | QUESTION
    ;

// canon: the predicates that required the two angle brackets to touch are dropped, so a < < b also
// reads as a shift; that accepts code rustc rejects but never rejects code rustc accepts.
shl
    : LT LT
    ;

shr
    : GT GT
    ;
