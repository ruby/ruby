# This grammar is released under an MIT license
# Author: William Howard (http://github.com/whoward)
# Source: https://github.com/whoward/cadenza/blob/master/src/cadenza.y

class Cadenza::RaccParser

/* expect this many shift/reduce conflicts */
expect 37

rule
  target
    : document
    | /* none */ { result = nil }
    ;

  parameter_list
    : logical_expression                     { result = [val[0]] }
    | parameter_list ',' logical_expression  { result = val[0].push(val[2]) }
    ;

  /* this has a shift/reduce conflict but since Racc will shift in this case it is the correct behavior */
  primary_expression
    : IDENTIFIER                   { result = VariableNode.new(val[0].value) }
    | IDENTIFIER parameter_list    { result = VariableNode.new(val[0].value, val[1]) }
    | INTEGER                      { result = ConstantNode.new(val[0].value) }
    | REAL                         { result = ConstantNode.new(val[0].value) }
    | STRING                       { result = ConstantNode.new(val[0].value) }
    | '(' filtered_expression ')'   { result = val[1] }
    ;

  multiplicative_expression
    : primary_expression
    | multiplicative_expression '*' primary_expression { result = OperationNode.new(val[0], "*", val[2]) }
    | multiplicative_expression '/' primary_expression { result = OperationNode.new(val[0], "/", val[2]) }
    ;

  additive_expression
    : multiplicative_expression
    | additive_expression '+' multiplicative_expression { result = OperationNode.new(val[0], "+", val[2]) }
    | additive_expression '-' multiplicative_expression { result = OperationNode.new(val[0], "-", val[2]) }
    ;

  boolean_expression
    : additive_expression
    | boolean_expression OP_EQ additive_expression { result = OperationNode.new(val[0], "==", val[2]) }
    | boolean_expression OP_NEQ additive_expression { result = OperationNode.new(val[0], "!=", val[2]) }
    | boolean_expression OP_LEQ additive_expression { result = OperationNode.new(val[0], "<=", val[2]) }
    | boolean_expression OP_GEQ additive_expression { result = OperationNode.new(val[0], ">=", val[2]) }
    | boolean_expression '>' additive_expression  { result = OperationNode.new(val[0], ">", val[2]) }
    | boolean_expression '<' additive_expression  { result = OperationNode.new(val[0], "<", val[2]) }
    ;

  inverse_expression
    : boolean_expression
    | NOT boolean_expression { result = BooleanInverseNode.new(val[1]) }
    ;

  logical_expression
    : inverse_expression
    | logical_expression AND inverse_expression { result = OperationNode.new(val[0], "and", val[2]) }
    | logical_expression OR inverse_expression { result = OperationNode.new(val[0], "or", val[2]) }
    ;

  filter
    : IDENTIFIER                    { result = FilterNode.new(val[0].value) }
    | IDENTIFIER ':' parameter_list { result = FilterNode.new(val[0].value, val[2]) }
    ;

  filter_list
    : filter { result = [val[0]] }
    | filter_list '|' filter { result = val[0].push(val[2]) }
    ;

  filtered_expression
    : logical_expression
    | logical_expression '|' filter_list { result = FilteredValueNode.new(val[0], val[2]) }
    ;

  inject_statement
    : VAR_OPEN filtered_expression VAR_CLOSE { result = val[1] }
    ;

  if_tag
    : STMT_OPEN IF logical_expression STMT_CLOSE { open_scope!; result = val[2] }
    | STMT_OPEN UNLESS logical_expression STMT_CLOSE { open_scope!; result = BooleanInverseNode.new(val[2]) }
    ;

  else_tag
    : STMT_OPEN ELSE STMT_CLOSE { result = close_scope!; open_scope! }
    ;

  end_if_tag
    : STMT_OPEN ENDIF STMT_CLOSE { result = close_scope! }
    | STMT_OPEN ENDUNLESS STMT_CLOSE { result = close_scope! }
    ;

  if_block
    : if_tag end_if_tag { result = IfNode.new(val[0], val[1]) }
    | if_tag document end_if_tag { result = IfNode.new(val[0], val[2]) }
    | if_tag else_tag document end_if_tag { result = IfNode.new(val[0], val[1], val[3]) }
    | if_tag document else_tag end_if_tag { result = IfNode.new(val[0], val[2], val[3]) }
    | if_tag document else_tag document end_if_tag { result = IfNode.new(val[0], val[2], val[4]) }
    ;

  for_tag
    : STMT_OPEN FOR IDENTIFIER IN filtered_expression STMT_CLOSE { open_scope!; result = [val[2].value, val[4]] }
    ;

  end_for_tag
    : STMT_OPEN ENDFOR STMT_CLOSE { result = close_scope! }
    ;

  /* this has a shift/reduce conflict but since Racc will shift in this case it is the correct behavior */
  for_block
    : for_tag end_for_tag { result = ForNode.new(VariableNode.new(val[0].first), val[0].last, val[1]) }
    | for_tag document end_for_tag { result = ForNode.new(VariableNode.new(val[0].first), val[0].last, val[2]) }
    ;

  block_tag
    : STMT_OPEN BLOCK IDENTIFIER STMT_CLOSE { result = open_block_scope!(val[2].value) }
    ;

  end_block_tag
    : STMT_OPEN ENDBLOCK STMT_CLOSE { result = close_block_scope! }
    ;

  /* this has a shift/reduce conflict but since Racc will shift in this case it is the correct behavior */
  block_block
    : block_tag end_block_tag { result = BlockNode.new(val[0], val[1]) }
    | block_tag document end_block_tag { result = BlockNode.new(val[0], val[2]) }
    ;

  generic_block_tag
    : STMT_OPEN IDENTIFIER STMT_CLOSE { open_scope!; result = [val[1].value, []] }
    | STMT_OPEN IDENTIFIER parameter_list STMT_CLOSE { open_scope!; result = [val[1].value, val[2]] }
    ;

  end_generic_block_tag
    : STMT_OPEN END STMT_CLOSE { result = close_scope! }
    ;

  generic_block
    : generic_block_tag document end_generic_block_tag { result = GenericBlockNode.new(val[0].first, val[2], val[0].last) }
    ;

  extends_statement
    : STMT_OPEN EXTENDS STRING STMT_CLOSE { result = val[2].value }
    | STMT_OPEN EXTENDS IDENTIFIER STMT_CLOSE { result = VariableNode.new(val[2].value) }
    ;

  document_component
    : TEXT_BLOCK { result = TextNode.new(val[0].value) }
    | inject_statement
    | if_block
    | for_block
    | generic_block
    | block_block
    ;

  document
    : document_component { push val[0] }
    | document document_component { push val[1] }
    | extends_statement  { document.extends = val[0] }
    | document extends_statement { document.extends = val[1] }
    ;

---- header ----
# racc_parser.rb : generated by racc

---- inner ----
