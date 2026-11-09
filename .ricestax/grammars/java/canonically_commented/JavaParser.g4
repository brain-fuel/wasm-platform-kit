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

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

parser grammar JavaParser;

// Insert here @header.

options {
    tokenVocab = JavaLexer;
    superClass = JavaParserBase;
}

/** A source file is an ordinary compilation unit, with an optional package, imports, and type declarations up to end of input, or a modular one holding a module declaration. In the dialect a canonical comment before the package declaration is the Why of the package unit, whose What is the package name, a comment before an import is an orphan, and a modular unit binds its comment to the module. ref:DEC-grammar-carries-extraction-rules */
compilationUnit
    : (why = canonicalComment? packageDeclaration)? ((orphan = canonicalComment)* importDeclaration | ';')* (typeDeclaration | ';')* EOF # package
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) modularCompulationUnit EOF # module
    ;

/** A module-info file: imports followed by one module declaration. The rule name keeps the misspelling grammars-v4 publishes so that generated parser code stays compatible. */
modularCompulationUnit
    : importDeclaration* moduleDeclaration
    ;

/** Names the package the file belongs to, with any package annotations, which is the file-level Where of everything declared in it. The qualified name is the What of the package unit. */
packageDeclaration
    : annotation* PACKAGE what = qualifiedName ';'
    ;

/** Brings a type, a static member, or with a star every member of a package or type into scope. */
importDeclaration
    : IMPORT STATIC? qualifiedName ('.' '*')? ';'
    ;

/** A top-level class, enum, interface, annotation type, or record, with the modifiers that apply to types. Each alternative is a unit of its kind: a canonical comment before the modifiers is its Why, public among the modifiers makes that comment required, and of two comments in a row the last one binds. ref:DEC-marker-label An annotation among the modifiers is a marker, which canon reads to recognise tests. ref:DEC-marker-label */
typeDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | classOrInterfaceModifier | orphan = canonicalComment)* classDeclaration # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | classOrInterfaceModifier | orphan = canonicalComment)* enumDeclaration # enum
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | classOrInterfaceModifier | orphan = canonicalComment)* interfaceDeclaration # interface
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | classOrInterfaceModifier | orphan = canonicalComment)* annotationTypeDeclaration # annotationType
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | classOrInterfaceModifier | orphan = canonicalComment)* recordDeclaration # record
    ;

/** Any modifier a member may carry: the type modifiers plus native, synchronized, transient, and volatile, which apply only to methods and fields. */
modifier
    : classOrInterfaceModifier
    | NATIVE
    | SYNCHRONIZED
    | TRANSIENT
    | VOLATILE
    ;

/** The modifiers a class or interface may carry, including annotations and the sealed and non-sealed markers of Java 17. */
classOrInterfaceModifier
    : annotation
    | PUBLIC
    | PROTECTED
    | PRIVATE
    | STATIC
    | ABSTRACT
    | FINAL // FINAL for class only -- does not apply to interfaces
    | STRICTFP
    | SEALED
    | NON_SEALED
    ;

/** A local variable or parameter may be final and may be annotated. */
variableModifier
    : FINAL
    | annotation
    ;

/** A class: its name, type parameters, superclass, interfaces, permitted subclasses, and body. The name is the What and the body the How. */
classDeclaration
    : CLASS what = identifier typeParameters? (EXTENDS typeType)? (IMPLEMENTS typeList)? (
        PERMITS typeList
    )?
    how = classBody
    ;

/** The angle-bracketed list of type parameters of a generic class, interface, method, or constructor. */
typeParameters
    : '<' typeParameter (',' typeParameter)* '>'
    ;

/** One type parameter with optional annotations and an optional bound. */
typeParameter
    : annotation* identifier (EXTENDS annotation* typeBound)?
    ;

/** The bound of a type parameter: one type, or an intersection of several joined by ampersands. */
typeBound
    : typeType ('&' typeType)*
    ;

/** An enum: its name, interfaces, constants, and any members after the semicolon. The name is the What. */
enumDeclaration
    : ENUM what = identifier (IMPLEMENTS typeList)? '{' enumConstants? ','? enumBodyDeclarations? '}'
    ;

/** The comma-separated constants of an enum. */
enumConstants
    : enumConstant (',' enumConstant)*
    ;

/** One enum constant, optionally annotated, with constructor arguments and a class body that makes it an anonymous subclass. A constant is a unit whose comment is optional and whose What is its name. */
enumConstant
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) annotation* what = identifier arguments? classBody? # enumConstant
    ;

/** The members of an enum after its constants, introduced by a semicolon. */
enumBodyDeclarations
    : ';' classBodyDeclaration*
    ;

/** An interface: its name, type parameters, superinterfaces, permitted subtypes, and body. The name is the What and the body the How. */
interfaceDeclaration
    : INTERFACE what = identifier typeParameters? (EXTENDS typeList)? (PERMITS typeList)? how = interfaceBody
    ;

/** The brace-delimited members of a class, enum constant body, or anonymous class. */
classBody
    : '{' classBodyDeclaration* '}'
    ;

/** The brace-delimited members of an interface. */
interfaceBody
    : '{' interfaceBodyDeclaration* '}'
    ;

/** One member of a class body: an empty declaration, an initializer block, or a modified member declaration. Each member alternative is a unit of its kind: a comment before the modifiers is the Why, public makes it required, a comment after an annotation or before an initializer is an orphan, and of two comments in a row the last one binds. ref:DEC-marker-label An annotation among the modifiers is a marker, which canon reads to recognise tests. ref:DEC-marker-label */
classBodyDeclaration
    : ';' # emptyMember
    | (orphan = canonicalComment)* STATIC? block # initializer
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* recordDeclaration # record
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* methodDeclaration # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* genericMethodDeclaration # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* fieldDeclaration # field
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* constructorDeclaration # constructor
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* genericConstructorDeclaration # constructor
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* interfaceDeclaration # interface
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* annotationTypeDeclaration # annotationType
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* classDeclaration # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* enumDeclaration # enum
    ;

/** The kinds of member a class body may hold: records, methods, fields, constructors, and nested types. */
memberDeclaration
    : recordDeclaration
    | methodDeclaration
    | genericMethodDeclaration
    | fieldDeclaration
    | constructorDeclaration
    | genericConstructorDeclaration
    | interfaceDeclaration
    | annotationTypeDeclaration
    | classDeclaration
    | enumDeclaration
    ;

/* We use rule this even for void methods which cannot have [] after parameters.
   This simplifies grammar and we can consider void to be a type, which
   renders the [] matching as a context-sensitive issue or a semantic check
   for invalid return type after parsing.
 */
/** A method: return type or void, name, parameters, legacy array brackets after the parameters, throws clause, and body or semicolon. The name is the What and the body the How. */
methodDeclaration
    : typeTypeOrVoid what = identifier formalParameters ('[' ']')* (THROWS qualifiedNameList)? how = methodBody
    ;

/** A method body is a block, or a semicolon for abstract and native methods. */
methodBody
    : block
    | ';'
    ;

/** A method result: a type or void. */
typeTypeOrVoid
    : typeType
    | VOID
    ;

/** A method whose own type parameters precede its return type. */
genericMethodDeclaration
    : typeParameters methodDeclaration
    ;

/** A constructor with its own type parameters. */
genericConstructorDeclaration
    : typeParameters constructorDeclaration
    ;

/** A constructor: the class name, parameters, throws clause, and body. The name is the What and the body the How. */
constructorDeclaration
    : what = identifier formalParameters (THROWS qualifiedNameList)? how = block
    ;

/** The compact canonical constructor of a record, which has no parameter list because the record header supplies it. It is a unit whose comment is required when it is public. An annotation among the modifiers is a marker, which canon reads to recognise tests. ref:DEC-marker-label */
compactConstructorDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | marker = annotation | modifier | orphan = canonicalComment)* what = identifier how = block # compactConstructor
    ;

/** A field declaration: a type followed by one or more declarators. */
fieldDeclaration
    : typeType variableDeclarators ';'
    ;

/** One member of an interface body: a modified member declaration or an empty declaration. Every member alternative is a unit whose comment is required, because interface members are public. ref:DEC-marker-label An annotation among the modifiers is a marker, which canon reads to recognise tests. ref:DEC-marker-label */
interfaceBodyDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (marker = annotation | modifier | orphan = canonicalComment)* required = recordDeclaration # record
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (marker = annotation | modifier | orphan = canonicalComment)* required = constDeclaration # constant
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (marker = annotation | modifier | orphan = canonicalComment)* required = interfaceMethodDeclaration # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (marker = annotation | modifier | orphan = canonicalComment)* required = genericInterfaceMethodDeclaration # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (marker = annotation | modifier | orphan = canonicalComment)* required = interfaceDeclaration # interface
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (marker = annotation | modifier | orphan = canonicalComment)* required = annotationTypeDeclaration # annotationType
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (marker = annotation | modifier | orphan = canonicalComment)* required = classDeclaration # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (marker = annotation | modifier | orphan = canonicalComment)* required = enumDeclaration # enum
    | ';' # emptyMember
    ;

/** The kinds of member an interface may hold: records, constants, methods, and nested types. */
interfaceMemberDeclaration
    : recordDeclaration
    | constDeclaration
    | interfaceMethodDeclaration
    | genericInterfaceMethodDeclaration
    | interfaceDeclaration
    | annotationTypeDeclaration
    | classDeclaration
    | enumDeclaration
    ;

/** An interface constant declaration: a type and one or more initialised declarators. */
constDeclaration
    : typeType constantDeclarator (',' constantDeclarator)* ';'
    ;

/** One interface constant with its mandatory initializer. The name is the What of the constant unit. */
constantDeclarator
    : what = identifier ('[' ']')* '=' variableInitializer
    ;

// Early versions of Java allows brackets after the method name, eg.
// public int[] return2DArray() [] { ... }
// is the same as
// public int[][] return2DArray() { ... }
/** An interface method with the modifiers interfaces allow, including default and static since Java 8. */
interfaceMethodDeclaration
    : interfaceMethodModifier* interfaceCommonBodyDeclaration
    ;

/** The modifiers an interface method may carry. */
interfaceMethodModifier
    : annotation
    | PUBLIC
    | ABSTRACT
    | DEFAULT
    | STATIC
    | STRICTFP
    ;

/** An interface method with its own type parameters. */
genericInterfaceMethodDeclaration
    : interfaceMethodModifier* typeParameters interfaceCommonBodyDeclaration
    ;

/** The part of an interface method shared by generic and non-generic forms: annotations, result, name, parameters, throws, and body. The name is the What and the body the How. */
interfaceCommonBodyDeclaration
    : annotation* typeTypeOrVoid what = identifier formalParameters ('[' ']')* (THROWS qualifiedNameList)? how = methodBody
    ;

/** One or more comma-separated declarators sharing a type. */
variableDeclarators
    : variableDeclarator (',' variableDeclarator)*
    ;

/** A declared name with an optional initializer. */
variableDeclarator
    : variableDeclaratorId ('=' variableInitializer)?
    ;

/** A declared name, with legacy array brackets after it. The name is the What of a field unit. */
variableDeclaratorId
    : what = identifier ('[' ']')*
    ;

/** An initializer is an array initializer or an expression. */
variableInitializer
    : arrayInitializer
    | expression
    ;

/** A brace-delimited, comma-separated list of initializers, with a trailing comma allowed. */
arrayInitializer
    : '{' (variableInitializer (',' variableInitializer)* ','?)? '}'
    ;

/** A class or interface type as the specification writes it: a possibly qualified, possibly annotated name with type arguments at each level. */
classType:
    (
      ( packageName '.' annotation* )? typeIdentifier typeArguments?
    )+ ( '.' annotation* typeIdentifier typeArguments? )*
    ;

/** A dotted package name. */
packageName:
    identifier ('.' identifier)*
    ;

/** A type argument: a type, or a wildcard with an optional upper or lower bound. */
typeArgument
    : typeType
    | annotation* '?' ((EXTENDS | SUPER) typeType)?
    ;

/** A comma-separated list of qualified names, used by throws clauses. */
qualifiedNameList
    : qualifiedName (',' qualifiedName)*
    ;

/** The parenthesised parameter list of a method or constructor, which may start with a receiver parameter. */
formalParameters
    : '(' (
       ( receiverParameter | formalParameter ) (',' formalParameterList)*
    )? ')'
    ;

/** The explicit this parameter that lets a method or constructor annotate its receiver type. */
receiverParameter
    : typeType (identifier '.')* THIS
    ;

/** One or more comma-separated formal parameters. */
formalParameterList
    : formalParameter (',' formalParameter)*
    ;

/** One parameter: modifiers, type, an optional varargs ellipsis, and the declared name. */
formalParameter
    : variableModifier* typeType (annotation* '...')? variableDeclaratorId
    ;

// local variable type inference
/** A lambda parameter list written with var, which uses local variable type inference. */
lambdaLVTIList
    : lambdaLVTIParameter (',' lambdaLVTIParameter)*
    ;

/** One lambda parameter declared with var. */
lambdaLVTIParameter
    : variableModifier* VAR identifier
    ;

/** A dotted sequence of identifiers. */
qualifiedName
    : identifier ('.' identifier)*
    ;

/** Any literal: integer, floating point, character, string, boolean, null, or text block. */
literal
    : integerLiteral
    | floatLiteral
    | CHAR_LITERAL
    | STRING_LITERAL
    | BOOL_LITERAL
    | NULL_LITERAL
    | TEXT_BLOCK
    ;

/** An integer literal in decimal, hexadecimal, octal, or binary form. */
integerLiteral
    : DECIMAL_LITERAL
    | HEX_LITERAL
    | OCT_LITERAL
    | BINARY_LITERAL
    ;

/** A floating point literal in decimal or hexadecimal form. */
floatLiteral
    : FLOAT_LITERAL
    | HEX_FLOAT_LITERAL
    ;

// ANNOTATIONS
/** An annotation whose at sign sits inside a qualified name, kept for compatibility though the annotation rule does not use it. */
altAnnotationQualifiedName
    : (identifier DOT)* '@' identifier
    ;

//annotation
//    : ('@' qualifiedName /* | altAnnotationQualifiedName */) ( '(' ( elementValuePairs | elementValue)? ')')?
//    ;

/** An annotation: an at sign, the annotation type name, and optional field values. */
annotation :
    ('@' qualifiedName /* | altAnnotationQualifiedName */) annotationFieldValues?
    ;

/** The parenthesised values of an annotation, either a single value or named pairs. */
annotationFieldValues:
	'(' ( annotationFieldValue ( ',' annotationFieldValue )* )? ')'
	;

/** One annotation value, named or positional; the predicate decides which by looking ahead for an equals sign. */
annotationFieldValue:
	{ this.IsNotIdentifierAssign() }? annotationValue
	| identifier '=' annotationValue
	;

/** What an annotation field may hold: an expression, a nested annotation, or a brace-delimited array of values. */
annotationValue:
	expression //conditionalExpression
	| annotation
	| '{' ( annotationValue ( ',' annotationValue )* )? ','? '}'
	;

//elementValuePairs
//    : elementValuePair (',' elementValuePair)*
//    ;

//elementValuePair
//    : identifier '=' elementValue
//    ;

/** An annotation element value: an expression, an annotation, or an array initializer. */
elementValue
    : expression
    | annotation
    | elementValueArrayInitializer
    ;

/** A brace-delimited list of annotation element values. */
elementValueArrayInitializer
    : '{' (elementValue (',' elementValue)*)? ','? '}'
    ;

/** An annotation type: at sign, the interface keyword, a name, and a body. The name is the What and the body the How. */
annotationTypeDeclaration
    : '@' INTERFACE what = identifier how = annotationTypeBody
    ;

/** The brace-delimited elements of an annotation type. */
annotationTypeBody
    : '{' annotationTypeElementDeclaration* '}'
    ;

/** One element of an annotation type, or an empty declaration, which the compiler accepts although the specification does not. An element is a unit whose comment is required. An annotation among the modifiers is a marker, which canon reads to recognise tests. ref:DEC-marker-label */
annotationTypeElementDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (marker = annotation | modifier | orphan = canonicalComment)* required = annotationTypeElementRest # annotationElement
    | ';' # emptyElement // this is not allowed by the grammar, but apparently allowed by the actual compiler
    ;

/** What an annotation type element is: a typed method or constant, or a nested type. */
annotationTypeElementRest
    : typeType annotationMethodOrConstantRest ';'
    | classDeclaration ';'?
    | interfaceDeclaration ';'?
    | enumDeclaration ';'?
    | annotationTypeDeclaration ';'?
    | recordDeclaration ';'?
    ;

/** After the type of an annotation element comes either a method with an optional default or a constant. */
annotationMethodOrConstantRest
    : annotationMethodRest
    | annotationConstantRest
    ;

/** An annotation method: a name, empty parentheses, and an optional default value. The name is the What of the element unit. */
annotationMethodRest
    : what = identifier '(' ')' defaultValue?
    ;

/** An annotation type constant, which is a variable declarator list. */
annotationConstantRest
    : variableDeclarators
    ;

/** The default keyword followed by the element value an annotation method defaults to. */
defaultValue
    : DEFAULT elementValue
    ;

/** A module declaration: optional annotations, optional open, the module keyword, its name, and its directives. The module name is the What of the module unit. */
moduleDeclaration
    : annotation* OPEN? MODULE what = qualifiedName '{' moduleDirective* '}'
    ;

/** One module directive: requires, exports, opens, uses, or provides with. */
moduleDirective
    : REQUIRES requiresModifier* qualifiedName ';'
    | EXPORTS qualifiedName (TO qualifiedName (',' qualifiedName)* )? ';'
    | OPENS qualifiedName (TO qualifiedName (',' qualifiedName)* )? ';'
    | USES qualifiedName ';'
    | PROVIDES qualifiedName WITH qualifiedName (',' qualifiedName)* ';'
    ;

/** A requires directive may be transitive or static. */
requiresModifier
    : TRANSITIVE
    | STATIC
    ;

/** A record: its name, type parameters, header of components, interfaces, and body. The name is the What and the body the How. */
recordDeclaration
    : RECORD what = identifier typeParameters? recordHeader (IMPLEMENTS typeList)? how = recordBody
    ;

/** The parenthesised component list of a record. */
recordHeader
    : '(' recordComponentList? ')'
    ;

/** One or more comma-separated record components; the predicate checks the last one. */
recordComponentList
    : recordComponent (',' recordComponent)* { this.DoLastRecordComponent() }?
    ;

/** One record component: annotations, a type, an optional varargs ellipsis, and a name. */
recordComponent
    : annotation* typeType (annotation* ELLIPSIS)? identifier
    ;

/** The members of a record, which may include compact constructors. */
recordBody
    : '{' (classBodyDeclaration | compactConstructorDeclaration)* '}'
    ;

// STATEMENTS / BLOCKS

/** A brace-delimited sequence of block statements. */
block
    : '{' blockStatement* '}'
    ;

/** A statement inside a block: a local variable declaration, a local type declaration, or a statement. A canonical comment before any of them binds to nothing and is an orphan. */
blockStatement
    : (orphan = canonicalComment)* localVariableDeclaration ';'
    | (orphan = canonicalComment)* localTypeDeclaration
    | (orphan = canonicalComment)* statement
    ;

/** A local variable: modifiers then either var with an initializer or a type with declarators. */
localVariableDeclaration
    : variableModifier* (VAR identifier '=' expression | typeType variableDeclarators)
    ;

/** An identifier, including the contextual keywords that remain usable as names. */
identifier
    : IDENTIFIER
    | MODULE
    | OPEN
    | REQUIRES
    | EXPORTS
    | OPENS
    | TO
    | USES
    | PROVIDES
    | WHEN
    | WITH
    | TRANSITIVE
    | YIELD
    | SEALED
    | PERMITS
    | RECORD
    | VAR
    ;

/** An identifier usable as a type name, which excludes the contextual keywords reserved for type declarations. */
typeIdentifier // Identifiers that are not restricted for type declarations
    : IDENTIFIER
    | MODULE
    | OPEN
    | REQUIRES
    | EXPORTS
    | OPENS
    | TO
    | USES
    | PROVIDES
    | WITH
    | TRANSITIVE
    | SEALED
    ;

/** A class, interface, record, or enum declared inside a block. */
localTypeDeclaration
    : classOrInterfaceModifier* (classDeclaration | interfaceDeclaration | recordDeclaration | enumDeclaration)
    ;

/** Every statement form of the language, from blocks and control flow to labeled statements and expression statements. */
statement
    : blockLabel = block
    | ASSERT expression (':' expression)? ';'
    | IF '(' expression ')' statement (ELSE statement)?
    | FOR '(' forControl ')' statement
    | WHILE '(' expression ')' statement
    | DO statement WHILE '(' expression ')' ';'
    | TRY block (catchClause+ finallyBlock? | finallyBlock)
    | TRY resourceSpecification block catchClause* finallyBlock?
    | SWITCH '(' expression ')' '{' switchBlockStatementGroup* switchLabel* '}'
    | SYNCHRONIZED '(' expression ')' block
    | RETURN expression? ';'
    | THROW expression ';'
    | BREAK identifier? ';'
    | CONTINUE identifier? ';'
    | YIELD expression ';'
    | SEMI
    | statementExpression = expression ';'
    | switchExpression ';'?
    | identifierLabel = identifier ':' statement
    ;

/** A catch clause: modifiers, one or more exception types, a name, and a block. */
catchClause
    : CATCH '(' variableModifier* catchType identifier ')' block
    ;

/** The exception types of a catch clause, joined by vertical bars in a multi-catch. */
catchType
    : qualifiedName ('|' qualifiedName)*
    ;

/** The finally keyword and its block. */
finallyBlock
    : FINALLY block
    ;

/** The parenthesised resources of a try-with-resources statement, with an optional trailing semicolon. */
resourceSpecification
    : '(' resources ';'? ')'
    ;

/** One or more resources separated by semicolons. */
resources
    : resource (';' resource)*
    ;

/** A resource: a declared and initialised variable, or an existing effectively final variable named by a qualified name. */
resource
    : variableModifier* (classOrInterfaceType variableDeclaratorId | VAR identifier) '=' expression
    | qualifiedName
    ;

/** Matches cases then statements, both of which are mandatory.
 *  To handle empty cases at the end, we add switchLabel* to statement.
 */
switchBlockStatementGroup
    : (switchLabel ':')+ blockStatement+
    ;

/** A case label with a constant, an enum constant name, or a type pattern, or the default label. */
switchLabel
    : CASE (
        constantExpression = expression
        | enumConstantName = IDENTIFIER
        | typeType varName = identifier
    )
    | DEFAULT
    ;

/** The header of a for statement: an enhanced for, or init, condition, and update separated by semicolons. */
forControl
    : enhancedForControl
    | forInit? ';' expression? ';' forUpdate = expressionList?
    ;

/** The initializer of a basic for statement: a local variable declaration or an expression list. */
forInit
    : localVariableDeclaration
    | expressionList
    ;

/** The header of an enhanced for statement: a declared variable, a colon, and the iterated expression. */
enhancedForControl
    : variableModifier* (typeType | VAR) variableDeclaratorId ':' expression
    ;

// EXPRESSIONS

/** One or more comma-separated expressions. */
expressionList
    : expression (',' expression)*
    ;

/** A method invocation on a name, this, or super, with its arguments. */
methodCall
    : (identifier | THIS | SUPER) arguments
    ;

/** Every expression form, listed from the tightest binding to the loosest so that ANTLR resolves precedence by alternative order and the assoc option marks the right-associative operators. */
expression
    // Expression order in accordance with https://introcs.cs.princeton.edu/java/11precedence/
    // Level 16, Primary, array and member access
    : primary                                                       #PrimaryExpression
    | expression '[' expression ']'                                 #SquareBracketExpression
    | expression bop = '.' (
        identifier
        | methodCall
        | THIS
        | NEW nonWildcardTypeArguments? innerCreator
        | SUPER superSuffix
        | explicitGenericInvocation
    )                                                               #MemberReferenceExpression
    // Method calls and method references are part of primary, and hence level 16 precedence
    | methodCall                                                    #MethodCallExpression
    | expression '::' typeArguments? identifier                     #MethodReferenceExpression
    | typeType '::' (typeArguments? identifier | NEW)               #MethodReferenceExpression
    | classType '::' typeArguments? NEW                             #MethodReferenceExpression
    
    | switchExpression                                              #ExpressionSwitch

    // Level 15 Post-increment/decrement operators
    | expression postfix = ('++' | '--')                            #PostIncrementDecrementOperatorExpression

    // Level 14, Unary operators
    | prefix = ('+' | '-' | '++' | '--' | '~' | '!') expression     #UnaryOperatorExpression

    // Level 13 Cast and object creation
    | '(' annotation* typeType ('&' typeType)* ')' expression       #CastExpression
    | NEW creator                                                   #ObjectCreationExpression

    // Level 12 to 1, Remaining operators
    // Level 12, Multiplicative operators
    | expression bop = ('*' | '/' | '%') expression           #BinaryOperatorExpression
    // Level 11, Additive operators
    | expression bop = ('+' | '-') expression                 #BinaryOperatorExpression
    // Level 10, Shift operators
    | expression ('<' '<' | '>' '>' '>' | '>' '>') expression #BinaryOperatorExpression
    // Level 9, Relational operators
    | expression bop = ('<=' | '>=' | '>' | '<') expression   #BinaryOperatorExpression
    | expression bop = INSTANCEOF (typeType | pattern)        #InstanceOfOperatorExpression
    // Level 8, Equality Operators
    | expression bop = ('==' | '!=') expression               #BinaryOperatorExpression
    // Level 7, Bitwise AND
    | expression bop = '&' expression                         #BinaryOperatorExpression
    // Level 6, Bitwise XOR
    | expression bop = '^' expression                         #BinaryOperatorExpression
    // Level 5, Bitwise OR
    | expression bop = '|' expression                         #BinaryOperatorExpression
    // Level 4, Logic AND
    | expression bop = '&&' expression                        #BinaryOperatorExpression
    // Level 3, Logic OR
    | expression bop = '||' expression                        #BinaryOperatorExpression
    // Level 2, Ternary
    | <assoc = right> expression bop = '?' expression ':' expression #TernaryExpression
    // Level 1, Assignment
    | <assoc = right> expression bop = (
        '='
        | '+='
        | '-='
        | '*='
        | '/='
        | '&='
        | '|='
        | '^='
        | '>>='
        | '>>>='
        | '<<='
        | '%='
    ) expression                                              #BinaryOperatorExpression

    // Level 0, Lambda Expression
    | lambdaExpression                                        #ExpressionLambda
    ;

/** A pattern for instanceof and switch: a type pattern binding a variable, or a record deconstruction pattern. */
pattern
    : variableModifier* typeType annotation* variableDeclarators
    | typeType '(' componentPatternList? ')'
    ;

/** The comma-separated nested patterns of a record pattern. */
componentPatternList :
    componentPattern ( ',' componentPattern )*
    ;

/** One nested pattern inside a record pattern. */
componentPattern :
    pattern
    ;

/** A lambda: parameters, an arrow, and a body. */
lambdaExpression
    : lambdaParameters '->' lambdaBody
    ;

/** Lambda parameters in any of their forms: a bare name, a typed list, an untyped list, or a var list. */
lambdaParameters
    : identifier
    | '(' formalParameterList? ')'
    | '(' identifier (',' identifier)* ')'
    | '(' lambdaLVTIList? ')'
    ;

/** A lambda body is an expression or a block. */
lambdaBody
    : expression
    | block
    ;

/** A primary expression: a parenthesised expression, this, super, a literal, a name, a class literal, or a generic invocation. */
primary
    : '(' expression ')'
    | THIS
    | SUPER
    | literal
    | identifier
    | typeTypeOrVoid '.' CLASS
    | nonWildcardTypeArguments (explicitGenericInvocationSuffix | THIS arguments)
    ;

/** A switch used as an expression, whose cases are rules. */
switchExpression
    : SWITCH '(' expression ')' '{' switchLabeledRule* '}'
    ;

/** One rule of a switch expression: case with expressions, null, or patterns and a guard, or default, then an arrow or colon and an outcome. */
switchLabeledRule
    : CASE (
	expressionList
	| NULL_LITERAL (',' DEFAULT)?
	| casePattern (',' casePattern)* guard?
	) (ARROW | COLON) switchRuleOutcome
    | DEFAULT (ARROW | COLON) switchRuleOutcome
    ;

/** A guard on a case pattern: the contextual keyword when and a boolean expression. */
guard 
    : 'when' expression
    ;

/** A pattern used as a case label. */
casePattern
    : pattern
    ;

/** What a switch rule produces: a block or a sequence of statements. */
switchRuleOutcome
    : block
    | blockStatement* // is *-operator correct??? I don't think so. https://docs.oracle.com/javase/specs/jls/se24/html/jls-14.html#jls-BlockStatements
    ;

/** A class or interface type; without a symbol table the two cannot be told apart, so both are a class type. */
classOrInterfaceType
    : classType // classType, interfaceType are all essentially identical to classOrInterfaceType because of no symbol table.
    ;

/** What follows new: a class instance creation with optional type arguments, or an array creation. */
creator
    : nonWildcardTypeArguments? createdName classCreatorRest
    | createdName arrayCreatorRest
    ;

/** The type being created: a dotted name with type arguments or a diamond at each level, or a primitive type for arrays. */
createdName
    : identifier typeArgumentsOrDiamond? ('.' identifier typeArgumentsOrDiamond?)*
    | primitiveType
    ;

/** Creation of an inner class instance qualified by an outer instance. */
innerCreator
    : identifier nonWildcardTypeArgumentsOrDiamond? classCreatorRest
    ;

/** After the element type of a new array: dimensions with an initializer, or sized dimensions followed by unsized ones. */
arrayCreatorRest
    : ('[' ']')+ arrayInitializer
    | ('[' expression ']')+ ('[' ']')*
    ;

/** After the type of a new instance: constructor arguments and an optional anonymous class body. */
classCreatorRest
    : arguments classBody?
    ;

/** A generic method invocation with explicit type arguments before the name. */
explicitGenericInvocation
    : nonWildcardTypeArguments explicitGenericInvocationSuffix
    ;

/** Type arguments, or the empty diamond that asks for inference. */
typeArgumentsOrDiamond
    : '<' '>'
    | typeArguments
    ;

/** Non-wildcard type arguments, or the empty diamond. */
nonWildcardTypeArgumentsOrDiamond
    : '<' '>'
    | nonWildcardTypeArguments
    ;

/** Angle-bracketed type arguments that must be concrete types, as explicit method type arguments must be. */
nonWildcardTypeArguments
    : '<' typeList '>'
    ;

/** One or more comma-separated types. */
typeList
    : typeType (',' typeType)*
    ;

/** A type: an optionally annotated class or primitive type with any number of array dimensions. */
typeType
    : annotation* (classOrInterfaceType | primitiveType) (annotation* '[' ']')*
    ;

/** The eight primitive types. */
primitiveType
    : BOOLEAN
    | CHAR
    | BYTE
    | SHORT
    | INT
    | LONG
    | FLOAT
    | DOUBLE
    ;

/** Angle-bracketed, comma-separated type arguments, which may include wildcards. */
typeArguments
    : '<' typeArgument (',' typeArgument)* '>'
    ;

/** What may follow super: constructor arguments, or a member access with optional type arguments and arguments. */
superSuffix
    : arguments
    | '.' typeArguments? identifier arguments?
    ;

/** After explicit type arguments: a super invocation or a named method call. */
explicitGenericInvocationSuffix
    : SUPER superSuffix
    | identifier arguments
    ;

/** A parenthesised, possibly empty argument list. */
arguments
    : '(' expressionList? ')'
    ;

/** A canonical comment: the Why of the unit it precedes, holding prose, reference citations, and license citations between its delimiters. A comment the grammar accepts but binds to nothing is labeled orphan and reported. ref:DEC-comment-reasons ref:DEC-grammar-carries-extraction-rules */
canonicalComment
    : DOC_OPEN docPart* DOC_CLOSE
    ;

/** One piece of a canonical comment: a reference citation, a license citation, or prose. ref:DEC-grammar-carries-extraction-rules */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
