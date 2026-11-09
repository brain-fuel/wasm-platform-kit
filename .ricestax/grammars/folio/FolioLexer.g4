/** The Folio lexer: one token per line, decided by longest match and rule order, so a document is read without hooks or predicates. A line that opens a heading, a fence, or a front-matter delimiter is its own token; every other line is prose. A fence pushes a code mode in which only its closer ends the block, so a three-backtick line inside a four-backtick block is code. ref:DEC-folio-language */
lexer grammar FolioLexer;

/** Three dashes alone on a line: the front-matter delimiter at the top of a page, and a thematic break anywhere else. */
FRONT_FENCE : '---' [ \t]* ;

/** A heading: one or more hashes, a space, and the title. Its depth is the number of hashes. */
HEADING : '#'+ ' ' ~[\r\n]* ;

/** A fence of four backticks with its info string, for a block whose body holds three-backtick lines; listed before the three-backtick fence so it wins their tie. */
FENCE4 : '````' ~[\r\n]* -> pushMode(Code4) ;

/** A fence of three backticks with its info string, which names the language, the file the block tangles to, and what it defines. */
FENCE3 : '```' ~[\r\n]* -> pushMode(Code3) ;

/** Any other line is prose: a paragraph line, a list item, a table row, a quotation, or a front-matter field. */
PROSE : ~[\r\n]+ ;

/** A line ending, which the parser uses to separate lines and to see blank ones. */
NEWLINE : '\r'? '\n' ;

/** Inside a three-backtick block. */
mode Code3;

/** The closer of a three-backtick block; it ties with a code line of the same text and wins by order. */
CLOSE3 : '```' [ \t]* -> popMode ;

/** A line of the block's body. */
CODE_LINE : ~[\r\n]+ ;

/** A line ending inside a block. */
CODE_NL : '\r'? '\n' ;

/** Inside a four-backtick block, where a three-backtick line is body. */
mode Code4;

/** The closer of a four-backtick block. */
CLOSE4 : '````' [ \t]* -> popMode ;

/** A line of the block's body, typed as a code line so the parser sees one kind. */
CODE4_LINE : ~[\r\n]+ -> type(CODE_LINE) ;

/** A line ending inside a four-backtick block, typed as a code line ending. */
CODE4_NL : '\r'? '\n' -> type(CODE_NL) ;
