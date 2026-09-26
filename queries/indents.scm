; Conventional two-space presentation; the parser itself does not enforce it.
((function_definition) @indent.begin (#set! indent.immediate 1))
((type_definition) @indent.begin (#set! indent.immediate 1))
((law_definition) @indent.begin (#set! indent.immediate 1))
((match_expression) @indent.begin (#set! indent.immediate 1))
((case_clause) @indent.begin (#set! indent.immediate 1))
((do_expression) @indent.begin (#set! indent.immediate 1))

([(parameters) (arguments) (parenthesized_expression) (tuple_expression)] @indent.align
  (#set! indent.open_delimiter "(")
  (#set! indent.close_delimiter ")"))

([(list_expression) (array_expression) (index_expression)] @indent.align
  (#set! indent.open_delimiter "[")
  (#set! indent.close_delimiter "]"))

([(constructor_definition) (constructor_expression) (annotation_expression)
 (equality_expression) (eliminator)] @indent.align
  (#set! indent.open_delimiter "{")
  (#set! indent.close_delimiter "}"))

["(" "[" "{"] @indent.begin
[")" "]" "}"] @indent.branch
[(string) (comment)] @indent.auto
