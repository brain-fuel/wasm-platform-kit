// JSON syntax for CALM ingestion. Architecture checks run over the parsed model.
grammar Calm;
json: value EOF;
value: object | array | STRING | NUMBER | 'true' | 'false' | 'null';
object: '{' (pair (',' pair)*)? '}';
pair: STRING ':' value;
array: '[' (value (',' value)*)? ']';
STRING: '"' (ESC | ~["\\\u0000-\u001F])* '"';
fragment ESC: '\\' (["\\/bfnrt] | 'u' HEX HEX HEX HEX);
fragment HEX: [0-9a-fA-F];
NUMBER: '-'? ('0' | [1-9] [0-9]*) ('.' [0-9]+)? ([eE] [+-]? [0-9]+)?;
WS: [ \t\r\n]+ -> skip;
