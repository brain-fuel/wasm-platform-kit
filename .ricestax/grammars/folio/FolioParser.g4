/** The Folio parser: a page is optional front matter and then elements, each one line or one fenced block, in order. Heading depth, front-matter fields, info-string attributes, and citations are read from token text by canon, not by this grammar, which only decides where each line and block begins and ends. ref:DEC-folio-language */
parser grammar FolioParser;

options {
    tokenVocab = FolioLexer;
}

/** A page: front matter at the very top if any, then elements to the end. */
document : frontMatter? element* EOF ;

/** The front matter: fields between two delimiters, only at the top of the page, so a delimiter later is a thematic break. */
frontMatter : FRONT_FENCE NEWLINE (PROSE NEWLINE)* FRONT_FENCE NEWLINE ;

/** One thing on the page: a heading, a fenced block, a line of prose, a thematic break, or a blank line. */
element : heading | codeBlock | prose | rule | blank ;

/** A heading line, which starts a section and ends the prose that precedes it. */
heading : HEADING NEWLINE? ;

/** A fenced block: the fence with its info string, the body lines, and the closer, in either fence length. */
codeBlock
    : FENCE3 CODE_NL codeLine* CLOSE3 NEWLINE?
    | FENCE4 CODE_NL codeLine* CLOSE4 NEWLINE?
    ;

/** A body line, which may be empty. */
codeLine : CODE_LINE CODE_NL | CODE_NL ;

/** A line of prose. */
prose : PROSE NEWLINE? ;

/** A thematic break: three dashes alone on a line below the front matter. */
rule : FRONT_FENCE NEWLINE? ;

/** A blank line, which separates paragraphs and is kept in prose once prose has started. */
blank : NEWLINE ;
