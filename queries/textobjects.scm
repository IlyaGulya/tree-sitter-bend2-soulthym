(function_definition) @function.outer
(function_definition body: (_) @function.inner)
(lambda_expression) @function.outer
(lambda_expression body: (_) @function.inner)
(type_definition) @class.outer
(type_definition (constructor_definition) @class.inner)
(law_definition) @class.outer
(law_definition body: (_) @class.inner)
(parameter) @parameter.inner
(parameter) @parameter.outer
(type_parameter) @parameter.inner
(type_parameter) @parameter.outer
(arguments argument: (_) @parameter.inner)
(case_clause) @conditional.outer
(case_clause body: (_) @conditional.inner)
(match_expression) @conditional.outer
(do_expression) @block.outer
(do_expression body: (_) @block.inner)
(call_expression) @call.outer
(call_expression arguments: (arguments argument: (_) @call.inner))
; A let node owns the remainder of its body, so capturing the entire node as
; assignment.outer would misleadingly select subsequent statements too.
(comment) @comment.outer
(comment) @comment.inner
