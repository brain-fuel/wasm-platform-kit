/**
BSD License
license:BSD-3-Clause
Copyright (c) 2020, Evgeniy Slobodkin
All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. Neither the name of Tom Everett nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

parser grammar HaskellParser;

options {
    tokenVocab = HaskellLexer;
}

/** A source file: optional explicit braces and semicolons, pragmas, then either a module header with its body or a bare body, up to end of input. */
module
    : OCURLY? semi* pragmas? semi* (module_content | body) CCURLY? semi? EOF
    ;

/** The module header: the module keyword, the module name, an optional export list, and the where that introduces the body. In the dialect a canonical comment before the module keyword is the Why of the module unit, whose What is the module name. ref:DEC-haskell-dialect */
module_content
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'module' what = modid exports? where_module # module
    ;

/** The where keyword that introduces a module body. */
where_module
    : 'where' module_body
    ;

/** A module body is a layout block, virtual or explicit, holding imports and top-level declarations. */
module_body
    : open_ body close semi*
    ;

/** One or more file-header pragmas before the module keyword. */
pragmas
    : pragma+
    ;

/** A file-header pragma: LANGUAGE, OPTIONS_GHC, or OPTIONS. */
pragma
    : language_pragma
    | options_ghc
    | simple_options
    ;

/** A LANGUAGE pragma listing extensions. */
language_pragma
    : '{-#' 'LANGUAGE' extension_ (',' extension_)* '#-}' semi?
    ;

/** An OPTIONS_GHC pragma listing compiler flags. */
options_ghc
    : '{-#' 'OPTIONS_GHC' ('-' (varid | conid))* '#-}' semi?
    ;

/** An OPTIONS pragma listing compiler flags. */
simple_options
    : '{-#' 'OPTIONS' ('-' (varid | conid))* '#-}' semi?
    ;

/** The name of a language extension, which is a constructor identifier. */
extension_
    : CONID
    ;

/** What a module body holds: imports, top-level declarations, or both. */
body
    : (impdecls topdecls)
    | impdecls
    | topdecls
    ;

/** One or more import declarations, with the blank lines and virtual semicolons the layout algorithm leaves between them. */
impdecls
    : (impdecl | NEWLINE | semi)+
    ;

/** The parenthesised export list, which is the public API of the module. Each entry is labeled export so that canon requires a comment on exactly the exported units. ref:DEC-export-rule */
exports
    : '(' (export = exprt (',' export = exprt)*)? ','? ')'
    ;

/** One export: a variable, a type with all or some of its constructors, a class with all or some of its methods, or a whole module. */
exprt
    : qvar
    | ( qtycon ( ('(' '..' ')') | ('(' (cname (',' cname)*)? ')'))?)
    | ( qtycls ( ('(' '..' ')') | ('(' (qvar (',' qvar)*)? ')'))?)
    | ( 'module' modid)
    ;

/** An import: optional qualified, the module name, an optional alias, and an optional import specification. */
impdecl
    : 'import' 'qualified'? modid ('as' modid)? impspec? semi+
    ;

/** The parenthesised list of imported names, or the hidden ones. */
impspec
    : ('(' (himport (',' himport)* ','?)? ')')
    | ( 'hiding' '(' (himport (',' himport)* ','?)? ')')
    ;

/** One imported name: a variable, a type with constructors, or a class with methods. */
himport
    : var_
    | ( tycon ( ('(' '..' ')') | ('(' (cname (',' cname)*)? ')'))?)
    | ( tycls ( ('(' '..' ')') | ('(' sig_vars? ')'))?)
    ;

/** A constructor or variable name inside an import or export item. */
cname
    : var_
    | con
    ;

// -------------------------------------------
// Fixity Declarations

/** A fixity keyword: infix, infixl, or infixr. */
fixity
    : 'infix'
    | 'infixl'
    | 'infixr'
    ;

/** One or more comma-separated operators in a fixity declaration. */
ops
    : op (',' op)*
    ;

// -------------------------------------------
// Top-Level Declarations
/** The top-level declarations of a module, separated by virtual or explicit semicolons. A canonical comment that no declaration follows is an orphan. */
topdecls
    : (topdecl semi+ | NEWLINE | semi | orphan = canonicalComment)+
    ;

/** A top-level declaration: class, type, kind signature, instance, standalone deriving, role annotation, default, foreign, pragma, annotation, ordinary declaration, or a naked Template Haskell splice. In the dialect each form that is a unit is its own alternative: class, type, typeFamily, data, newtype, dataFamily, instance, typeInstance, dataInstance, newtypeInstance, and function for a type signature; a canonical comment before it is its Why, the declared name is its What, and the body is its How. A function's signature is its own label, and each binding that follows is labeled too, so the extractor can attach the equations to the signature by name and the function's How is its equations rather than its type. An instance head is not an exportable name, so an instance never requires a comment. ref:DEC-haskell-dialect ref:DEC-export-rule ref:DEC-binding-label */
topdecl
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'class' tycl_hdr fds? how = where_cls? # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'type' what = type_ '=' ktypedoc # type
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'type' 'family' what = type_ opt_tyfam_kind_sig? opt_injective_info? where_type_family? # typeFamily
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'data' capi_ctype? tycl_hdr how = constrs derivings? # data
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'newtype' capi_ctype? tycl_hdr how = constrs derivings? # newtype
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'data' capi_ctype? tycl_hdr opt_kind_sig? how = gadt_constrlist? derivings? # data
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'newtype' capi_ctype? tycl_hdr opt_kind_sig? how = gadt_constrlist? derivings? # newtype
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'data' 'family' what = type_ opt_datafam_kind_sig? # dataFamily
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'instance' overlap_pragma? what = inst_type how = where_inst? # instance
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'type' 'instance' what = ty_fam_inst_eqn # typeInstance
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'data' 'instance' capi_ctype? what = tycl_hdr_inst derivings? # dataInstance
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'newtype' 'instance' capi_ctype? what = tycl_hdr_inst derivings? # newtypeInstance
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'data' 'instance' capi_ctype? what = tycl_hdr_inst opt_kind_sig? gadt_constrlist? derivings? # dataInstance
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* 'newtype' 'instance' capi_ctype? what = tycl_hdr_inst opt_kind_sig? gadt_constrlist? derivings? # newtypeInstance
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* what = infixexp '::' signature = sigtypedoc # function
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* what = var_ ',' sig_vars '::' signature = sigtypedoc # function
    | cl_decl # plainClass
    | ty_decl # plainType
    // Check KindSignatures
    | standalone_kind_sig # kindSignature
    | inst_decl # plainInstance
    | standalone_deriving # deriving
    | role_annot # role
    | ('default' '(' comma_types? ')') # defaultDeclaration
    | ('foreign' fdecl) # foreign
    | ('{-#' 'DEPRECATED' deprecations? '#-}') # deprecated
    | ('{-#' 'WARNING' warnings? '#-}') # warning
    | ('{-#' 'RULES' rules? '#-}') # rules
    | annotation # annotationPragma
    | binding = decl_no_th # declaration
    // -- Template Haskell Extension
    //  The $(..) form is one possible form of infixexp
    //  but we treat an arbitrary expression just as if
    //  it had a $(..) wrapped around it
    | infixexp # spliceExpression
    ;

// Type classes
//
/** A class declaration: header, functional dependencies, and body. */
cl_decl
    : 'class' tycl_hdr fds? where_cls?
    ;

// Type declarations (toplevel)
//
/** A type-level declaration: type synonym, type family, data or newtype in ordinary or GADT form, or data family. */
ty_decl
    :
    // ordinary type synonyms
    'type' type_ '=' ktypedoc
    // type family declarations
    | 'type' 'family' type_ opt_tyfam_kind_sig? opt_injective_info? where_type_family?
    // ordinary data type or newtype declaration
    | 'data' capi_ctype? tycl_hdr constrs derivings?
    | 'newtype' capi_ctype? tycl_hdr constrs derivings?
    // ordinary GADT declaration
    | 'data' capi_ctype? tycl_hdr opt_kind_sig? gadt_constrlist? derivings?
    | 'newtype' capi_ctype? tycl_hdr opt_kind_sig? gadt_constrlist? derivings?
    // data/newtype family
    | 'data' 'family' type_ opt_datafam_kind_sig?
    ;

// standalone kind signature

/** A standalone kind signature for one or more type constructors. */
standalone_kind_sig
    : 'type' sks_vars '::' ktypedoc
    ;

// See also: sig_vars
/** The type constructors a standalone kind signature covers. */
sks_vars
    : oqtycon (',' oqtycon)*
    ;

/** An instance declaration for a class, or a type, data, or newtype family instance. */
inst_decl
    : ('instance' overlap_pragma? inst_type where_inst?)
    | ('type' 'instance' ty_fam_inst_eqn)
    // 'constrs' in the end of this rules in GHC
    // This parser no use docs
    | ('data' 'instance' capi_ctype? tycl_hdr_inst derivings?)
    | ('newtype' 'instance' capi_ctype? tycl_hdr_inst derivings?)
    // For GADT
    | ('data' 'instance' capi_ctype? tycl_hdr_inst opt_kind_sig? gadt_constrlist? derivings?)
    | ('newtype' 'instance' capi_ctype? tycl_hdr_inst opt_kind_sig? gadt_constrlist? derivings?)
    ;

/** An overlap pragma on an instance. */
overlap_pragma
    : '{-#' 'OVERLAPPABLE' '#-}'
    | '{-#' 'OVERLAPPING' '#-}'
    | '{-#' 'OVERLAPS' '#-}'
    | '{-#' 'INCOHERENT' '#-}'
    ;

/** A deriving strategy other than via. */
deriv_strategy_no_via
    : 'stock'
    | 'anyclass'
    | 'newtype'
    ;

/** The via deriving strategy with the type derived through. */
deriv_strategy_via
    : 'via' ktype
    ;

/** A deriving strategy on a standalone deriving declaration. */
deriv_standalone_strategy
    : 'stock'
    | 'anyclass'
    | 'newtype'
    | deriv_strategy_via
    ;

// Injective type families

/** The optional injectivity annotation of a type family. */
opt_injective_info
    : '|' injectivity_cond
    ;

/** An injectivity condition: the result variable and the variables it determines. */
injectivity_cond
    :
    // but in GHC new tyvarid rule
    tyvarid '->' inj_varids
    ;

/** The type variables an injectivity condition names. */
inj_varids
    : tyvarid+
    ;

// Closed type families

/** The where that introduces a closed type family's equations. */
where_type_family
    : 'where' ty_fam_inst_eqn_list
    ;

/** The layout block of type family equations. */
ty_fam_inst_eqn_list
    : (open_ ty_fam_inst_eqns? close)
    | ('{' '..' '}')
    | (open_ '..' close)
    ;

/** One or more type family equations. */
ty_fam_inst_eqns
    : ty_fam_inst_eqn (semi+ ty_fam_inst_eqn)* semi*
    ;

/** One type family equation with optional quantification. */
ty_fam_inst_eqn
    : 'forall' tv_bndrs? '.' type_ '=' ktype
    | type_ '=' ktype
    ;

//  Associated type family declarations

//  * They have a different syntax than on the toplevel (no family special
//    identifier).

//  * They also need to be separate from instances; otherwise, data family
//    declarations without a kind signature cause parsing conflicts with empty
//    data declarations.

/** An associated type or data family declaration inside a class. */
at_decl_cls
    : ('data' 'family'? type_ opt_datafam_kind_sig?)
    | ('type' 'family'? type_ opt_at_kind_inj_sig?)
    | ('type' 'instance'? ty_fam_inst_eqn)
    ;

// Associated type instances
//
/** An associated type or data family instance inside an instance. */
at_decl_inst
    :
    // type instance declarations, with optional 'instance' keyword
    ('type' 'instance'? ty_fam_inst_eqn)
    // data/newtype instance declaration, with optional 'instance' keyword
    | ('data' 'instance'? capi_ctype? tycl_hdr_inst constrs derivings?)
    | ('newtype' 'instance'? capi_ctype? tycl_hdr_inst constrs derivings?)
    // GADT instance declaration, with optional 'instance' keyword
    | ('data' 'instance'? capi_ctype? tycl_hdr_inst opt_kind_sig? gadt_constrlist? derivings?)
    | ('newtype' 'instance'? capi_ctype? tycl_hdr_inst opt_kind_sig? gadt_constrlist? derivings?)
    ;

// Family result/return kind signatures

/** An optional kind signature. */
opt_kind_sig
    : '::' kind
    ;

/** An optional kind signature on a data family. */
opt_datafam_kind_sig
    : '::' kind
    ;

/** An optional result kind or result variable on a type family. */
opt_tyfam_kind_sig
    : ('::' kind)
    | ('=' tv_bndr)
    ;

/** An optional kind or injectivity signature on an associated type. */
opt_at_kind_inj_sig
    : ('::' kind)
    | ('=' tv_bndr_no_braces '|' injectivity_cond)
    ;

/** The header of a type or class declaration: an optional context and the declared type. The dialect prefers to read the declared name as a bare type constructor with binders, so that the What of a type or class is its name; the full type is the fallback for exotic heads. */
tycl_hdr
    : (tycl_context '=>' (what = oqtycon tv_bndrs? | type_))
    | (what = oqtycon tv_bndrs? | type_)
    ;

/** The header of a family instance: optional quantification, optional context, and the instance type. */
tycl_hdr_inst
    : ('forall' tv_bndrs? '.' tycl_context '=>' type_)
    | ('forall' tv_bndrs? '.' type_)
    | (tycl_context '=>' type_)
    | type_
    ;

/** A CTYPE pragma naming the C type of a data type. */
capi_ctype
    : ('{-#' 'CTYPE' STRING STRING '#-}')
    | ('{-#' 'CTYPE' STRING '#-}')
    ;

// -------------------------------------------
// Stand-alone deriving

/** A standalone deriving declaration. */
standalone_deriving
    : 'deriving' deriv_standalone_strategy? 'instance' overlap_pragma? inst_type
    ;

// -------------------------------------------
// Role annotations

/** A role annotation for a type constructor. */
role_annot
    : 'type' 'role' oqtycon roles?
    ;

/** One or more roles. */
roles
    : role+
    ;

/** A role name or an underscore. */
role
    : varid
    | '_'
    ;

// -------------------------------------------
// Pattern synonyms
/** A pattern synonym declaration in unidirectional, bidirectional, or explicitly bidirectional form. */
pattern_synonym_decl
    : ('pattern' pattern_synonym_lhs '=' pat)
    | ('pattern' pattern_synonym_lhs '<-' pat where_decls?)
    ;

/** The left-hand side of a pattern synonym: prefix, infix, or record form. */
pattern_synonym_lhs
    : (con vars_?)
    | (varid conop varid)
    | (con '{' cvars '}')
    ;

/** One or more variables. */
vars_
    : varid+
    ;

/** Comma-separated variables of a record pattern synonym. */
cvars
    : var_ (',' var_)*
    ;

/** The where block of an explicitly bidirectional pattern synonym. */
where_decls
    : 'where' open_ decls? close
    ;

/** A pattern synonym type signature. */
pattern_synonym_sig
    : 'pattern' con_list '::' sigtypedoc
    ;

// -------------------------------------------
// Nested declaration

// Declaration in class bodies

/** A declaration inside a class body: an associated family, an ordinary declaration, or a default signature. A type signature inside a class is a method unit whose comment is required when the class exports it. */
decl_cls
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* what = infixexp '::' signature = sigtypedoc # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (semi | NEWLINE)* what = var_ ',' sig_vars '::' signature = sigtypedoc # method
    | at_decl_cls # associatedType
    | decl # classDeclaration
    | 'default' infixexp '::' sigtypedoc # defaultSignature
    ;

/** The declarations of a class body. */
decls_cls
    : decl_cls (semi+ decl_cls)* semi*
    ;

/** The layout block of a class body. */
decllist_cls
    : open_ decls_cls? close
    ;

// Class body
//
/** The where that introduces a class body. */
where_cls
    : 'where' decllist_cls
    ;

// Declarations in instance bodies
//
/** A declaration inside an instance body: an associated family instance or an ordinary declaration. */
decl_inst
    : at_decl_inst
    | decl
    ;

/** The declarations of an instance body. A canonical comment on an instance method binding is an orphan. */
decls_inst
    : (orphan = canonicalComment)* decl_inst (semi+ (orphan = canonicalComment)* decl_inst)* semi*
    ;

/** The layout block of an instance body. */
decllist_inst
    : open_ decls_inst? close
    ;

// Instance body
//
/** The where that introduces an instance body. */
where_inst
    : 'where' decllist_inst
    ;

// Declarations in binding groups other than classes and instances
//
/** The declarations of a binding group. A canonical comment on a local binding is an orphan. */
decls
    : (orphan = canonicalComment)* decl (semi+ (orphan = canonicalComment)* decl)* semi*
    ;

/** The layout block of a binding group. */
decllist
    : open_ decls? close
    ;

// Binding groups other than those of class and instance declarations
//
/** The bindings of a where or let. */
binds
    : decllist
    | (open_ dbinds? close)
    ;

/** The where that introduces local bindings. */
wherebinds
    : 'where' binds
    ;

// -------------------------------------------
// Transformation Rules

/** The rewrite rules of a RULES pragma. */
rules
    : pragma_rule (semi pragma_rule)* semi?
    ;

/** One rewrite rule: its name, activation, quantified variables, and the two sides. */
pragma_rule
    : pstring rule_activation? rule_foralls? infixexp '=' exp
    ;

/** The tilde that marks a rule as active before a phase. */
rule_activation_marker
    : '~'
    | varsym
    ;

/** The phase in which a rule is active. */
rule_activation
    : ('[' integer ']')
    | ('[' rule_activation_marker integer ']')
    | ('[' rule_activation_marker ']')
    ;

/** The variables a rule quantifies over. */
rule_foralls
    : ('forall' rule_vars? '.' ('forall' rule_vars? '.')?)
    ;

/** One or more rule variables. */
rule_vars
    : rule_var+
    ;

/** A rule variable, optionally with a type. */
rule_var
    : varid
    | ('(' varid '::' ctype ')')
    ;

// -------------------------------------------
// Warnings and deprecations (c.f. rules)

/** The entries of a WARNING pragma. */
warnings
    : pragma_warning (semi pragma_warning)* semi?
    ;

/** One warning: the names it applies to and the message. */
pragma_warning
    : namelist strings
    ;

/** The entries of a DEPRECATED pragma. */
deprecations
    : pragma_deprecation (semi pragma_deprecation)* semi?
    ;

/** One deprecation: the names it applies to and the message. */
pragma_deprecation
    : namelist strings
    ;

/** One string or a bracketed list of strings. */
strings
    : pstring
    | ('[' stringlist? ']')
    ;

/** Comma-separated strings. */
stringlist
    : pstring (',' pstring)*
    ;

// -------------------------------------------
// Annotations

/** An ANN pragma on a name, a type, or the module. */
annotation
    : ('{-#' 'ANN' name_var aexp '#-}')
    | ('{-#' 'ANN' tycon aexp '#-}')
    | ('{-#' 'ANN' 'module' aexp '#-}')
    ;

// -------------------------------------------
// Foreign import and export declarations

/** A foreign import or export. */
fdecl
    : ('import' callconv safety? fspec)
    | ('export' callconv fspec)
    ;

/** A foreign calling convention. */
callconv
    : 'ccall'
    | 'stdcall'
    | 'cplusplus'
    | 'javascript'
    ;

/** The safety of a foreign import. */
safety
    : 'unsafe'
    | 'safe'
    | 'interruptible'
    ;

/** The entity string, name, and type of a foreign declaration. */
fspec
    : pstring? var_ '::' sigtypedoc
    ;

// -------------------------------------------
// Type signatures

/** An optional type annotation. */
opt_sig
    : '::' sigtype
    ;

/** An optional type constructor signature. */
opt_tyconsig
    : '::' gtycon
    ;

/** The type of a signature. */
sigtype
    : ctype
    ;

/** The type of a signature where documentation may appear. */
sigtypedoc
    : ctypedoc
    ;

/** The comma-separated names of one type signature. */
sig_vars
    : var_ (',' var_)*
    ;

/** One or more comma-separated signature types. */
sigtypes1
    : sigtype (',' sigtype)*
    ;

// -------------------------------------------
// Types

/** An UNPACK or NOUNPACK pragma on a field. */
unpackedness
    : ('{-#' 'UNPACK' '#-}')
    | ('{-#' 'NOUNPACK' '#-}')
    ;

/** The dot or arrow after a forall, which decides whether the quantification is visible. */
forall_vis_flag
    : '.'
    | '->'
    ;

// A ktype/ktypedoc is a ctype/ctypedoc, possibly with a kind annotation
/** A type possibly annotated with a kind. */
ktype
    : ctype
    | (ctype '::' kind)
    ;

/** A type possibly annotated with a kind, where documentation may appear. */
ktypedoc
    : ctypedoc
    | ctypedoc '::' kind
    ;

// A ctype is a for-all type
/** A type with optional quantification and context. */
ctype
    : 'forall' tv_bndrs? forall_vis_flag ctype
    | btype '=>' ctype
    | var_ '::' type_ // not sure about this rule
    | type_
    ;

// -- Note [ctype and ctypedoc]
// -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// -- It would have been nice to simplify the grammar by unifying `ctype` and
// -- ctypedoc` into one production, allowing comments on types everywhere (and
// -- rejecting them after parsing, where necessary).  This is however not possible
// -- since it leads to ambiguity. The reason is the support for comments on record
// -- fields:
// --         data R = R { field :: Int -- ^ comment on the field }
// -- If we allow comments on types here, it's not clear if the comment applies
// -- to 'field' or to 'Int'. So we must use `ctype` to describe the type.

/** A type with optional quantification and context, where documentation may appear. */
ctypedoc
    : 'forall' tv_bndrs? forall_vis_flag ctypedoc
    | tycl_context '=>' ctypedoc
    | var_ '::' type_
    | typedoc
    ;

// In GHC this rule is context
/** The context of a type or class header. */
tycl_context
    : btype
    ;

// constr_context rule

// {- Note [GADT decl discards annotations]
// ~~~~~~~~~~~~~~~~~~~~~
// The type production for

//     btype `->`         ctypedoc
//     btype docprev `->` ctypedoc

// add the AnnRarrow annotation twice, in different places.

// This is because if the type is processed as usual, it belongs on the annotations
// for the type as a whole.

// But if the type is passed to mkGadtDecl, it discards the top level SrcSpan, and
// the top-level annotation will be disconnected. Hence for this specific case it
// is connected to the first type too.
// -}

/** The context of a constructor. */
constr_context
    : constr_btype
    ;

// {- Note [GADT decl discards annotations]
// ~~~~~~~~~~~~~~~~~~~~~
// The type production for

//     btype `->`         ctypedoc
//     btype docprev `->` ctypedoc

// add the AnnRarrow annotation twice, in different places.

// This is because if the type is processed as usual, it belongs on the annotations
// for the type as a whole.

// But if the type is passed to mkGadtDecl, it discards the top level SrcSpan, and
// the top-level annotation will be disconnected. Hence for this specific case it
// is connected to the first type too.
// -}

/** A type: an applied type or a function type. */
type_
    : btype
    | btype '->' ctype
    ;

/** A type where documentation may appear. */
typedoc
    : btype
    | btype '->' ctypedoc
    ;

/** The applied type of a constructor. */
constr_btype
    : constr_tyapps
    ;

/** The type applications of a constructor. */
constr_tyapps
    : constr_tyapp+
    ;

/** One type application inside a constructor. */
constr_tyapp
    : tyapp
    ;

/** An applied type. */
btype
    : tyapps
    ;

/** One or more type applications. */
tyapps
    : tyapp+
    ;

/** One type application: an atomic type, a visible application, or an operator. */
tyapp
    : atype
    | ('@' atype)
    | qtyconop
    | tyvarop
    | ('\'' qconop)
    | ('\'' varop)
    | unpackedness
    ;

/** An atomic type: a constructor, variable, tuple, list, parenthesised type, literal, or promoted form. */
atype
    : ntgtycon
    | tyvar
    | '*'
    | ('~' atype)
    | ('!' atype)
    | ('{' fielddecls? '}')
    | ('(' ')')
    | ('(' ktype ',' comma_types ')')
    | ('(#' '#)')
    | ('(#' comma_types '#)')
    | ('(#' bar_types2 '#)')
    | ('[' ktype ']')
    | ('(' ktype ')')
    | quasiquote
    | splice_untyped
    | ('\'' qcon_nowiredlist)
    | ('\'' '(' ktype ',' comma_types ')')
    | ('\'' '[' comma_types? ']')
    | ('\'' var_)
    // Two or more [ty, ty, ty] must be a promoted list type, just as
    // if you had written '[ty, ty, ty]
    // (One means a list type, zero means the list type constructor,
    // so you have to quote those.)
    | ('[' ktype ',' comma_types ']')
    | integer
    | pstring
    | '_'
    ;

/** The type an instance is declared for. */
inst_type
    : sigtype
    ;

/** The comma-separated classes of a deriving clause. */
deriv_types
    : ktypedoc (',' ktypedoc)*
    ;

/** Comma-separated types. */
comma_types
    : ktype (',' ktype)*
    ;

/** Two or more bar-separated types. */
bar_types2
    : ktype '|' ktype ('|' ktype)*
    ;

/** One or more type variable binders. */
tv_bndrs
    : tv_bndr+
    ;

/** A type variable binder, possibly braced for inferred variables. */
tv_bndr
    : tv_bndr_no_braces
    | ('{' tyvar '}')
    | ('{' tyvar '::' kind '}')
    ;

/** A type variable binder: a variable or a kinded variable in parentheses. */
tv_bndr_no_braces
    : tyvar
    | ('(' tyvar '::' kind ')')
    ;

/** The functional dependencies of a class. */
fds
    : '|' fds1
    ;

/** Comma-separated functional dependencies. */
fds1
    : fd (',' fd)*
    ;

/** One functional dependency between two sets of variables. */
fd
    : varids0? '->' varids0?
    ;

/** Zero or more type variables. */
varids0
    : tyvar+
    ;

// -------------------------------------------
// Kinds

/** A kind, which is syntactically a type. */
kind
    : ctype
    ;

// {- Note [Promotion]
//    ~~~~~~~~~~~~~~~~

// - Syntax of promoted qualified names
// We write 'Nat.Zero instead of Nat.'Zero when dealing with qualified
// names. Moreover ticks are only allowed in types, not in kinds, for a
// few reasons:
//   1. we don't need quotes since we cannot define names in kinds
//   2. if one day we merge types and kinds, tick would mean look in DataName
//   3. we don't have a kind namespace anyway

// - Name resolution
// When the user write Zero instead of 'Zero in types, we parse it a
// HsTyVar ("Zero", TcClsName) instead of HsTyVar ("Zero", DataName). We
// deal with this in the renamer. If a HsTyVar ("Zero", TcClsName) is not
// bounded in the type level, then we look for it in the term level (we
// change its namespace to DataName, see Note [Demotion] in GHC.Types.Names.OccName).
// And both become a HsTyVar ("Zero", DataName) after the renamer.

// -}

// -------------------------------------------
// Datatype declarations

/** The where block of GADT constructors. */
gadt_constrlist
    : 'where' open_ gadt_constrs? semi* close
    ;

/** One or more GADT constructors. */
gadt_constrs
    : gadt_constr_with_doc (semi gadt_constr_with_doc)*
    ;

// We allow the following forms:
//      C :: Eq a => a -> T a
//      C :: forall a. Eq a => !a -> T a
//      D { x,y :: a } :: T a
//      forall a. Eq a => D { x,y :: a } :: T a

/** A GADT constructor where documentation may appear. */
gadt_constr_with_doc
    : gadt_constr
    ;

/** A GADT constructor: its names and its signature. */
gadt_constr
    : con_list '::' sigtypedoc
    ;

// {- Note [Difference in parsing GADT and data constructors]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// GADT constructors have simpler syntax than usual data constructors:
// in GADTs, types cannot occur to the left of '::', so they cannot be mixed
// with constructor names (see Note [Parsing data constructors is hard]).

// Due to simplified syntax, GADT constructor names (left-hand side of '::')
// use simpler grammar production than usual data constructor names. As a
// consequence, GADT constructor names are restricted (names like '(*)' are
// allowed in usual data constructors, but not in GADTs).
// -}

// NOT AS IN GHC
// constrs
//     :
//     constr ('|' constr)*
//     ;

/** The equals sign and constructors of a data or newtype declaration. */
constrs
    : '=' constrs1
    ;

/** One or more bar-separated constructors. Constructors are not units in this pass, so a canonical comment on one is an orphan. */
constrs1
    : (orphan = canonicalComment)* constr ('|' (orphan = canonicalComment)* constr)*
    ;

// {- Note [Constr variations of non-terminals]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// In record declarations we assume that 'ctype' used to parse the type will not
// consume the trailing docprev:

//   data R = R { field :: Int -- ^ comment on the field }

// In 'R' we expect the comment to apply to the entire field, not to 'Int'. The
// same issue is detailed in Note [ctype and ctypedoc].

// So, we do not want 'ctype'  to consume 'docprev', therefore
//     we do not want 'btype'  to consume 'docprev', therefore
//     we do not want 'tyapps' to consume 'docprev'.

// At the same time, when parsing a 'constr', we do want to consume 'docprev':

//   data T = C Int  -- ^ comment on Int
//              Bool -- ^ comment on Bool

// So, we do want 'constr_stuff' to consume 'docprev'.

// The problem arises because the clauses in 'constr' have the following
// structure:

//   (a)  context '=>' constr_stuff   (e.g.  data T a = Ord a => C a)
//   (b)               constr_stuff   (e.g.  data T a =          C a)

// and to avoid a reduce/reduce conflict, 'context' and 'constr_stuff' must be
// compatible. And for 'context' to be compatible with 'constr_stuff', it must
// consume 'docprev'.

// So, we want 'context'  to consume 'docprev', therefore
//     we want 'btype'    to consume 'docprev', therefore
//     we want 'tyapps'   to consume 'docprev'.

// Our requirements end up conflicting: for parsing record types, we want 'tyapps'
// to leave 'docprev' alone, but for parsing constructors, we want it to consume
// 'docprev'.

// As the result, we maintain two parallel hierarchies of non-terminals that
// either consume 'docprev' or not:

//   tyapps      constr_tyapps
//   btype       constr_btype
//   context     constr_context
//   ...

// They must be kept identical except for their treatment of 'docprev'.

// -}

// constr
//     :
//     (con ('!'? atype)*)
//     | ((btype | ('!' atype)) conop (btype | ('!' atype)))
//     | (con '{' fielddecls? '}')
//     ;

/** A constructor with optional quantification and context. */
constr
    : forall? (constr_context '=>')? constr_stuff
    ;

/** An explicit quantification. */
forall
    : 'forall' tv_bndrs? '.'
    ;

/** The shape of a constructor: its type applications. */
constr_stuff
    : constr_tyapps
    ;

/** Comma-separated record fields. */
fielddecls
    : fielddecl (',' fielddecl)*
    ;

/** One record field declaration: names and type. */
fielddecl
    : sig_vars '::' ctype
    ;

// A list of one or more deriving clauses at the end of a datatype
/** One or more deriving clauses. */
derivings
    : deriving+
    ;

// The outer Located is just to allow the caller to
// know the rightmost extremity of the 'deriving' clause
/** A deriving clause with an optional strategy. */
deriving
    : ('deriving' deriv_clause_types)
    | ('deriving' deriv_strategy_no_via deriv_clause_types)
    | ('deriving' deriv_clause_types deriv_strategy_via)
    ;

/** The classes named by a deriving clause. */
deriv_clause_types
    : qtycon
    | '(' ')'
    | '(' deriv_types ')'
    ;

// -------------------------------------------
// Value definitions (CHECK!!!)

// {- Note [Declaration/signature overlap]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// There's an awkward overlap with a type signature.  Consider
//         f :: Int -> Int = ...rhs...
//    Then we can't tell whether it's a type signature or a value
//    definition with a result signature until we see the '='.
//    So we have to inline enough to postpone reductions until we know.
// -}

// {-
//   ATTENTION: Dirty Hackery Ahead! If the second alternative of vars is var
//   instead of qvar, we get another shift/reduce-conflict. Consider the
//   following programs:

//      { (^^) :: Int->Int ; }          Type signature; only var allowed

//      { (^^) :: Int->Int = ... ; }    Value defn with result signature;
//                                      qvar allowed (because of instance decls)

//   We can't tell whether to reduce var to qvar until after we've read the signatures.
// -}

/** An ordinary declaration: a signature, a binding, a pattern synonym, or empty. */
decl_no_th
    : sigdecl
    | (infixexp opt_sig? rhs)
    | pattern_synonym_decl
    // | docdecl
    | semi+
    ;

/** A declaration in a binding group, including a Template Haskell splice. */
decl
    : decl_no_th

    // Why do we only allow naked declaration splices in top-level
    // declarations and not here? Short answer: because readFail009
    // fails terribly with a panic in cvBindsAndSigs otherwise.
    | splice_exp
    | semi+
    ;

/** The right-hand side of a binding: an expression or guarded expressions, with optional where bindings. */
rhs
    : ('=' exp wherebinds?)
    | (gdrhs wherebinds?)
    ;

/** One or more guarded right-hand sides. */
gdrhs
    : gdrh+
    ;

/** One guarded right-hand side. */
gdrh
    : '|' guards '=' exp
    ;

/** A signature-like declaration: a type signature, a fixity declaration, a pattern synonym signature, or a pragma on a name. */
sigdecl
    : (infixexp '::' sigtypedoc)
    | (var_ ',' sig_vars '::' sigtypedoc)
    | (fixity integer? ops)
    | (pattern_synonym_sig)
    | ('{-#' 'COMPLETE' con_list opt_tyconsig? '#-}')
    | ('{-#' ('INLINE' | 'NOINLINE') activation? qvar '#-}')
    | ('{-#' 'SCC' qvar pstring? '#-}')
    | ('{-#' 'SPECIALISE' activation? qvar '::' sigtypes1 '#-}')
    | ('{-#' 'SPECIALISE_INLINE' activation? qvar '::' sigtypes1 '#-}')
    | ('{-#' 'SPECIALISE' 'instance' inst_type '#-}')
    | ('{-#' 'MINIMAL' '#-}' name_boolformula_opt? '#-}')
    | (semi+)
    ;

/** The activation phase of an INLINE or SPECIALISE pragma. */
activation
    : ('[' integer ']')
    | ('[' rule_activation_marker integer ']')
    ;

// -------------------------------------------
// Expressions

/** A quasi-quotation with an unqualified quoter. */
th_quasiquote
    : '[' varid '|'
    ;

/** A quasi-quotation with a qualified quoter. */
th_qquasiquote
    : '[' qvarid '|'
    ;

/** A quasi-quotation. */
quasiquote
    : th_quasiquote
    | th_qquasiquote
    ;

/** An expression, possibly with a type annotation or an arrow-notation form. */
exp
    : (infixexp '::' sigtype)
    | (infixexp '-<' exp)
    | (infixexp '>-' exp)
    | (infixexp '-<<' exp)
    | (infixexp '>>-' exp)
    | infixexp
    ;

/** An expression built from operands and infix operators; precedence is not resolved here because fixities are declared. */
infixexp
    : exp10 (qop exp10p)*
    ;

/** An operand of an infix expression. */
exp10p
    : exp10
    ;

/** A possibly negated function application or a keyword expression. */
exp10
    : '-'? fexp
    ;

/** A function application: one or more atomic expressions with optional type applications. */
fexp
    : aexp+ ('@' atype)?
    ;

/** An atomic expression with prefixes: as-pattern, laziness, strictness, lambda, let, if, case, do, or procedure. */
aexp
    : (qvar '@' aexp)
    | ('~' aexp)
    | ('!' aexp)
    | ('\\' apats '->' exp)
    | ('let' decllist 'in' exp)
    | (LCASE alts)
    | ('if' exp semi? 'then' exp semi? 'else' exp)
    | ('if' ifgdpats)
    | ('case' exp 'of' alts)
    | ('do' stmtlist)
    | ('mdo' stmtlist)
    | aexp1
    ;

/** An atomic expression with record construction or update braces. */
aexp1
    : aexp2 ('{' fbinds? '}')*
    ;

/** The atomic expressions proper: names, literals, parentheses, tuples, lists, quotations, and holes. */
aexp2
    : qvar
    | qcon
    | varid
    | literal
    | pstring
    | integer
    | pfloat
    // N.B.: sections get parsed by these next two productions.
    // This allows you to write, e.g., '(+ 3, 4 -)', which isn't
    // correct Haskell (you'd have to write '((+ 3), (4 -))')
    // but the less cluttered version fell out of having texps.
    | ('(' texp ')')
    | ('(' tup_exprs ')')
    | ('(#' texp '#)')
    | ('(#' tup_exprs '#)')
    | ('[' list_ ']')
    | '_'
    // Template Haskell
    | splice_untyped
    | splice_typed
    | ('\'' qvar)
    | ('\'' qcon)
    | ('\'\'' tyvar)
    | ('\'\'' gtycon)
    | '\'\''
    | '[|' exp '|]'
    | '[||' exp '||]'
    | '[t|' ktype '|]'
    | '[p|' infixexp '|]'
    | '[d|' cvtopbody '|]'
    | quasiquote
    | (AopenParen aexp cmdargs? AopenParen)
    ;

/** A Template Haskell splice, typed or untyped. */
splice_exp
    : splice_typed
    | splice_untyped
    ;

/** An untyped splice. */
splice_untyped
    : '$' aexp
    ;

/** A typed splice. */
splice_typed
    : '$$' aexp
    ;

/** The arguments of an arrow command. */
cmdargs
    : acmd+
    ;

/** One argument of an arrow command. */
acmd
    : aexp
    ;

/** The body of a declaration quotation. */
cvtopbody
    : open_ cvtopdecls0? close
    ;

/** The declarations inside a declaration quotation. */
cvtopdecls0
    : topdecls semi*
    ;

// -------------------------------------------
// Tuple expressions

/** A tuple section element: an expression, a section, or a view pattern. */
texp
    : exp
    | (infixexp qop)
    | (qopm infixexp)
    | (exp '->' texp)
    ;

/** The elements of a tuple, with optional gaps for sections. */
tup_exprs
    : (texp commas_tup_tail)
    | (texp bars)
    | (commas tup_tail?)
    | (bars texp bars?)
    ;

/** Commas followed by the rest of a tuple. */
commas_tup_tail
    : commas tup_tail?
    ;

/** The rest of a tuple after a comma. */
tup_tail
    : texp commas_tup_tail
    | texp
    ;

// -------------------------------------------
// List expressions

/** The inside of list brackets: an element list, a range, or a comprehension. */
list_
    : texp
    | lexps
    | texp '..'
    | texp ',' exp '..'
    | texp '..' exp
    | texp ',' exp '..' exp
    | texp '|' flattenedpquals
    ;

/** Two or more comma-separated list elements. */
lexps
    : texp ',' texp (',' texp)*
    ;

// -------------------------------------------
// List Comprehensions

/** The qualifiers of a comprehension, flattened. */
flattenedpquals
    : pquals
    ;

/** Parallel comprehension qualifiers separated by bars. */
pquals
    : squals ('|' squals)*
    ;

/** Comma-separated comprehension qualifiers. */
squals
    : transformqual (',' transformqual)*
    | transformqual (',' qual)*
    | qual (',' transformqual)*
    | qual (',' qual)*
    ;

/** A transform comprehension qualifier: then, then by, then group. */
transformqual
    : 'then' exp
    | 'then' exp 'by' exp
    | 'then' 'group' 'using' exp
    | 'then' 'group' 'by' exp 'using' exp
    ;

// Note that 'group' is a special_id, which means that you can enable
// TransformListComp while still using Data.List.group. However, this
// introduces a shift/reduce conflict. Happy chooses to resolve the conflict
// in by choosing the "group by" variant, which is what we want.

// -------------------------------------------
// Guards (Different from GHC)

/** Comma-separated guards. */
guards
    : guard_ (',' guard_)*
    ;

/** One guard: a pattern guard, a let, or a boolean. */
guard_
    : pat '<-' infixexp
    | 'let' decllist
    | infixexp
    ;

// -------------------------------------------
// Case alternatives

/** The alternatives of a case, in a layout block. */
alts
    : (open_ (alt semi*)+ close)
    | (open_ close)
    ;

/** One case alternative: a pattern and its right-hand side. */
alt
    : pat alt_rhs
    ;

/** The right-hand side of an alternative with optional where bindings. */
alt_rhs
    : ralt wherebinds?
    ;

/** An unguarded or guarded alternative body. */
ralt
    : ('->' exp)
    | gdpats
    ;

/** One or more guarded alternative bodies. */
gdpats
    : gdpat+
    ;

// In ghc parser on GitLab second rule is 'gdpats close'
// Unclearly, is there possible errors with this implemmentation
/** Guarded alternatives in explicit braces, for multi-way if. */
ifgdpats
    : '{' gdpats '}'
    | gdpats
    ;

/** One guarded alternative body. */
gdpat
    : '|' guards '->' exp
    ;

/** A pattern, which is parsed as an expression because the two share syntax. */
pat
    : exp
    ;

/** A pattern on the left of a bind arrow. */
bindpat
    : exp
    ;

/** An atomic pattern. */
apat
    : aexp
    ;

/** One or more atomic patterns. */
apats
    : apat+
    ;

/** A field pattern in a record pattern. */
fpat
    : qvar '=' pat
    ;

// -------------------------------------------
// Statement sequences

/** The layout block of statements of a do block. */
stmtlist
    : open_ stmts? close
    ;

/** One or more statements. */
stmts
    : stmt (semi+ stmt)* semi*
    ;

/** A statement: a qualifier or a recursive block. */
stmt
    : qual
    | ('rec' stmtlist)
    | semi+
    ;

/** A qualifier: a bind, a let, or an expression. */
qual
    : bindpat '<-' exp
    | exp
    | 'let' binds
    ;

// -------------------------------------------
// Record Field Update/Construction

/** The field bindings of a record construction or update, with an optional wildcard. */
fbinds
    : (fbind (',' fbind)*)
    | ('..')
    ;

// In GHC 'texp', not 'exp'

// 1) RHS is a 'texp', allowing view patterns (#6038)
// and, incidentally, sections.  Eg
// f (R { x = show -> s }) = ...
//
// 2) In the punning case, use a place-holder
// The renamer fills in the final value
/** One field binding, possibly punned. */
fbind
    : (qvar '=' exp)
    | qvar
    ;

// -------------------------------------------
// Implicit Parameter Bindings

/** Implicit parameter bindings. */
dbinds
    : dbind (semi+ dbind) semi*
    ;

/** One implicit parameter binding. */
dbind
    : varid '=' exp
    ;

// -------------------------------------------

// Warnings and deprecations

/** A MINIMAL pragma formula: disjunctions of conjunctions. */
name_boolformula_opt
    : name_boolformula_and ('|' name_boolformula_and)*
    ;

/** A conjunction in a MINIMAL formula. */
name_boolformula_and
    : name_boolformula_and_list
    ;

/** The comma-separated atoms of a conjunction. */
name_boolformula_and_list
    : name_boolformula_atom (',' name_boolformula_atom)*
    ;

/** An atom of a MINIMAL formula: a name or a parenthesised formula. */
name_boolformula_atom
    : ('(' name_boolformula_opt ')')
    | name_var
    ;

/** Comma-separated names. */
namelist
    : name_var (',' name_var)*
    ;

/** A variable or constructor name. */
name_var
    : var_
    | con
    ;

// -------------------------------------------
// Data constructors
// There are two different productions here as lifted list constructors
// are parsed differently.

/** A qualified constructor other than the list constructor. */
qcon_nowiredlist
    : gen_qcon
    | sysdcon_nolist
    ;

/** A qualified constructor, including the built-in ones. */
qcon
    : gen_qcon
    | sysdcon
    ;

/** A qualified constructor in prefix or parenthesised operator form. */
gen_qcon
    : qconid
    | ( '(' qconsym ')')
    ;

/** A constructor in prefix or parenthesised operator form. */
con
    : conid
    | ( '(' consym ')')
    | sysdcon
    ;

/** Comma-separated constructors. */
con_list
    : con (',' con)*
    ;

/** A built-in constructor other than the list: unit, tuples, and unboxed tuples. */
sysdcon_nolist
    : ('(' ')')
    | ('(' commas ')')
    | ('(#' '#)')
    | ('(#' commas '#)')
    ;

/** A built-in constructor, including the empty list. */
sysdcon
    : sysdcon_nolist
    | ('[' ']')
    ;

/** A constructor operator, symbolic or backquoted. */
conop
    : consym
    | ('`' conid '`')
    ;

/** A qualified constructor operator. */
qconop
    : gconsym
    | ('`' qconid '`')
    ;

/** A constructor symbol, including cons. */
gconsym
    : ':'
    | qconsym
    ;

// -------------------------------------------
// Type constructors (Be careful!!!)

/** A type constructor, including the built-in ones. */
gtycon
    : ntgtycon
    | ('(' ')')
    | ('(#' '#)')
    ;

/** A type constructor other than tuples and lists, or the built-in ones written out. */
ntgtycon
    : oqtycon
    | ('(' commas ')')
    | ('(#' commas '#)')
    | ('(' '->' ')')
    | ('[' ']')
    ;

/** A qualified type constructor in prefix or parenthesised operator form. */
oqtycon
    : qtycon
    | ('(' qtyconsym ')')
    ;

// {- Note [Type constructors in export list]
// ~~~~~~~~~~~~~~~~~~~~~
// Mixing type constructors and data constructors in export lists introduces
// ambiguity in grammar: e.g. (*) may be both a type constructor and a function.

// -XExplicitNamespaces allows to disambiguate by explicitly prefixing type
// constructors with 'type' keyword.

// This ambiguity causes reduce/reduce conflicts in parser, which are always
// resolved in favour of data constructors. To get rid of conflicts we demand
// that ambiguous type constructors (those, which are formed by the same
// productions as variable constructors) are always prefixed with 'type' keyword.
// Unambiguous type constructors may occur both with or without 'type' keyword.

// Note that in the parser we still parse data constructors as type
// constructors. As such, they still end up in the type constructor namespace
// until after renaming when we resolve the proper namespace for each exported
// child.
// -}

/** A qualified type constructor operator. */
qtyconop
    : qtyconsym
    | ('`' qtycon '`')
    ;

/** A qualified type constructor. */
qtycon
    : (modid '.')? tycon
    ;

/** A type constructor name. */
tycon
    : conid
    ;

/** A qualified type constructor symbol. */
qtyconsym
    : qconsym
    | qvarsym
    | tyconsym
    ;

/** A type constructor symbol. */
tyconsym
    : consym
    | varsym
    | ':'
    | '-'
    | '.'
    ;

// -------------------------------------------
// Operators

/** An operator: variable or constructor. */
op
    : varop
    | conop
    ;

/** A variable operator, symbolic or backquoted. */
varop
    : varsym
    | ('`' varid '`')
    ;

/** A qualified operator. */
qop
    : qvarop
    | qconop
    ;

/** A qualified operator other than minus, for left sections. */
qopm
    : qvaropm
    | qconop
    | hole_op
    ;

/** A backquoted underscore, the typed hole operator. */
hole_op
    : '`' '_' '`'
    ;

/** A qualified variable operator. */
qvarop
    : qvarsym
    | ('`' qvarid '`')
    ;

/** A qualified variable operator other than minus. */
qvaropm
    : qvarsym_no_minus
    | ('`' qvarid '`')
    ;

// -------------------------------------------
// Type variables

/** A type variable. */
tyvar
    : varid
    ;

/** A backquoted type variable operator. */
tyvarop
    : '`' tyvarid '`'
    ;

// Expand this rule later
// In GHC:
// tyvarid : VARID | special_id | 'unsafe'
//         | 'safe' | 'interruptible';

/** A type variable identifier, including the contextual keywords allowed there. */
tyvarid
    : varid
    | special_id
    | 'unsafe'
    | 'safe'
    | 'interruptible'
    ;

/** A class name. */
tycls
    : conid
    ;

/** A qualified class name. */
qtycls
    : (modid '.')? tycls
    ;

// -------------------------------------------
// Variables

/** A variable in prefix or parenthesised operator form. */
var_
    : varid
    | ( '(' varsym ')')
    ;

/** A qualified variable. */
qvar
    : qvarid
    | ( '(' qvarsym ')')
    ;

// We've inlined qvarsym here so that the decision about
// whether it's a qvar or a var can be postponed until
// *after* we see the close paren
/** A qualified variable identifier. */
qvarid
    : (modid '.')? varid
    ;

// Note that 'role' and 'family' get lexed separately regardless of
// the use of extensions. However, because they are listed here,
// this is OK and they can be used as normal varids.
/** A variable identifier, including the contextual keywords that stay usable as names. The list is longer than upstream so that by, group, using, pattern, family, role, and rec parse as ordinary names. ref:DEC-haskell-grammar-fixes */
varid
    : (VARID | special_id) '#'*
    ;

/** A qualified variable symbol. */
qvarsym
    : (modid '.')? varsym
    ;

/** A qualified variable symbol other than minus. */
qvarsym_no_minus
    : varsym_no_minus
    | qvarsym
    ;

/** A variable symbol. */
varsym
    : varsym_no_minus
    | '-'
    ;

/** A variable symbol other than minus. */
varsym_no_minus
    : ascSymbol+
    ;

// These special_ids are treated as keywords in various places,
// but as ordinary ids elsewhere.   'special_id' collects all these
// except 'unsafe', 'interruptible', 'forall', 'family', 'role', 'stock', and
// 'anyclass', whose treatment differs depending on context
/** The contextual keywords accepted as identifiers. */
special_id
    : 'as'
    | 'qualified'
    | 'hiding'
    | 'export'
    | 'by'
    | 'group'
    | 'using'
    | 'pattern'
    | 'family'
    | 'role'
    | 'rec'
    | 'stdcall'
    | 'ccall'
    | 'capi'
    | 'javascript'
    | 'stock'
    | 'anyclass'
    | 'via'
    | 'unsafe'
    | 'safe'
    | 'interruptible'
    ;

// -------------------------------------------
// Data constructors

/** A qualified constructor identifier. */
qconid
    : (modid '.')? conid
    ;

/** A constructor identifier, including pragma names such as SCC that are legitimate constructor names. ref:DEC-haskell-grammar-fixes */
conid
    : CONID '#'*
    | 'SCC'
    | 'LANGUAGE'
    | 'OPTIONS'
    | 'INLINE'
    | 'NOINLINE'
    | 'SPECIALISE'
    | 'SOURCE'
    | 'RULES'
    | 'DEPRECATED'
    | 'WARNING'
    | 'UNPACK'
    | 'NOUNPACK'
    | 'ANN'
    | 'MINIMAL'
    | 'CTYPE'
    | 'OVERLAPPING'
    | 'OVERLAPPABLE'
    | 'OVERLAPS'
    | 'INCOHERENT'
    | 'COMPLETE'
    ;

/** A qualified constructor symbol. */
qconsym
    : (modid '.')? consym
    ;

/** A constructor symbol: a colon followed by symbol characters. */
consym
    : ':' ascSymbol*
    ;

// -------------------------------------------
// Literals

/** A literal: integer, float, character, or string. */
literal
    : integer
    | pfloat
    | pchar
    | pstring
    ;

// -------------------------------------------
// Layout

/** An opening brace, virtual or explicit. */
open_
    : VOCURLY
    | OCURLY
    ;

/** A closing brace, virtual or explicit. */
close
    : VCCURLY
    | CCURLY
    ;

/** A semicolon, explicit or virtual. */
semi
    : ';'
    | SEMI
    ;

// -------------------------------------------
// Miscellaneous (mostly renamings)

/** A dotted module name. */
modid
    : (conid '.')* conid
    ;

/** One or more commas. */
commas
    : ','+
    ;

/** One or more bars. */
bars
    : '|'+
    ;

// -------------------------------------------

/** The special characters that are not symbol characters. */
special
    : '('
    | ')'
    | ','
    | ';'
    | '['
    | ']'
    | '`'
    | '{'
    | '}'
    ;

/** A symbol character. */
symbol
    : ascSymbol
    ;

/** An ASCII symbol character. */
ascSymbol
    : '!'
    | '#'
    | '$'
    | '%'
    | '&'
    | '*'
    | '+'
    | '.'
    | '/'
    | '<'
    | '='
    | '>'
    | '?'
    | '@'
    | '\\'
    | '^'
    | '|'
    | '~'
    | ':'
    ;

/** An integer literal in any base. */
integer
    : DECIMAL
    | OCTAL
    | HEXADECIMAL
    ;

/** A floating point literal. */
pfloat
    : FLOAT
    ;

/** A character literal. */
pchar
    : CHAR
    ;

/** A string literal. */
pstring
    : STRING
    ;

/** A canonical comment: the Why of the unit it precedes, holding prose, reference citations, and license citations. A Haddock line comment ends at its line break, which stays a NEWLINE token; a block comment ends at its closer. ref:DEC-comment-reasons ref:DEC-haskell-dialect */
canonicalComment
    : DOC_OPEN docPart*
    | DOC_BLOCK_OPEN docPart* DOC_BLOCK_CLOSE
    ;

/** One piece of a canonical comment: a reference citation, a license citation, or prose. ref:DEC-grammar-carries-extraction-rules */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
